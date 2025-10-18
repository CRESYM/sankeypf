const ELabel = Tuple{String,String}
const VLabel = String

mutable struct Branch
    b::Float64
    p_max::Float64
    v_nom1::Float64
    v_nom2::Float64
    p::Float64
    outage::Bool
    trip::Bool
end

Branch(b, p_max) = Branch(b, p_max, 0, 0, 0, false, false)
Branch(b, p_max, v_nom1, v_nom2) = Branch(b, p_max, v_nom1, v_nom2, 0, false, false)
Branch(b::Branch) = Branch(b.b, b.p_max, b.v_nom1, b.v_nom2, b.p, false, false)
Branch(b::Branch, p_max) = Branch(b.b, p_max, b.v_nom1, b.v_nom2, b.p, false, false)
Branch() = Branch(0, 0, 0, 0, 0, false, false)


function e_label_for(g::MetaGraph, e::Edge)
    l1 = label_for(g, src(e))
    l2 = label_for(g, dst(e))
    haskey(g, l1, l2) ? (l1, l2) : (l2, l1)
end

from(e::ELabel) = e[1]
to(e::ELabel) = e[2]

str(e::ELabel) = e[1] * "-" * e[2]

lsrc(g::MetaGraph, e::Graphs.SimpleEdge) = label_for(g, src(e))
ldst(g::MetaGraph, e::Graphs.SimpleEdge) = label_for(g, dst(e))

incident_signed(g::MetaGraph, bus::VLabel) = Iterators.flatten((
    (((busin, bus), 1) for busin in inneighbor_labels(g, bus)),
    (((bus, busout), -1) for busout in outneighbor_labels(g, bus))))

incident(g::MetaGraph, bus::VLabel) = Iterators.flatten((
    ((busin, bus) for busin in inneighbor_labels(g, bus)),
    ((bus, busout) for busout in outneighbor_labels(g, bus))))

opposite(e::ELabel, v::VLabel) = v == e[1] ? e[2] : e[1]



function _initgraph()
    MetaGraph(
        DiGraph();
        label_type=String,
        vertex_data_type=Float64,
        edge_data_type=Branch,
    )
end

function build_simple_grid(; micro=true)
    g = _initgraph()
    g["1"] = micro ? -2 : -3
    for i = 2:(micro ? 3 : 4)
        g["$i"] = 1
    end
    g["1", "2"] = Branch(1, 1)
    g["2", "3"] = Branch(1, 1)
    if micro
        g["1", "3"] = Branch(1, 1)
    else
        g["3", "4"] = Branch(1, 1)
        g["2", "4"] = Branch(1, 1)
        g["1", "4"] = Branch(1, 1)
    end
    g
end

function PGLibtograph(case::String, buslabels=num -> "$num")
    c = pglib(case)
    g = _initgraph()

    for (label, bus) in c["bus"]
        g[buslabels(bus["bus_i"])] = 0
    end

    for load in values(c["load"])
        g[buslabels(load["load_bus"])] += load["pd"]
    end
    for gen in values(c["gen"])
        g[buslabels(gen["gen_bus"])] -= gen["pg"]
    end

    for br in values(c["branch"])
        br_label = br["f_bus"] ≤ br["t_bus"] ?
                   (buslabels(br["f_bus"]), buslabels(br["t_bus"])) :
                   (buslabels(br["t_bus"]), buslabels(br["f_bus"]))
        g[br_label...] = Branch(1 / br["br_x"], br["rate_a"])
    end

    to_remove = []
    for node in vertices(g)
        if isempty(inneighbors(g, node)) && isempty(outneighbors(g, node))
            push!(to_remove, label_for(g, node))
        end
    end

    foreach(node -> rem_vertex!(g, code_for(g, node)), to_remove)

    g
end

@enum BalanceType all_non_zero_uniform gen_proportional

function balance!(g::MetaGraph, btype::BalanceType=gen_proportional)
    non_zeros = [label for label in labels(g) if g[label] ≠ 0]
    imbalance = sum(g[label] for label in non_zeros)

    if btype == all_non_zero_uniform
        uniform = imbalance / length(non_zeros)
        for label in non_zeros
            g[label] -= uniform
        end

    elseif btype == gen_proportional
        generators = [label for label in labels(g) if g[label] ≤ 0]
        if isempty(generators)
            println("no generator to balance")
        else
            total_gen = sum(g[label] for label in generators)
            for label in generators
                g[label] -= imbalance * g[label] / total_gen
            end
        end

    else
        println("BALANCE TYPE TO BE IMPLEMENTED")
    end #TODO oter types
end

function check_flow_consistency(g; v::Bool=false)
    flows = Dict(l => g[l...].p for l in edge_labels(g))
    injections = Dict(l => g[l] for l in labels(g))

    # Initialize net flows for each node
    net_flows = Dict{String,Float64}()

    # Update net flows based on branch flows
    for ((from, to), flow) in flows
        net_flows[from] = get(net_flows, from, 0.0) - flow
        net_flows[to] = get(net_flows, to, 0.0) + flow
    end

    # Compare with injections
    consistent = true

    v && println("\nComparison with injections:")
    for (node, injection) in injections
        net_flow = get(net_flows, node, 0.0)

        v && println("Node $node: Injection = $injection, Net Flow = $net_flow, Difference = $(injection - net_flow)")
        if abs(injection - net_flow) > 1e-9  # Tolerance for floating-point comparison
            consistent = false
        end
    end

    if v
        if consistent
            println("\nThe flows and injections are consistent.")
        else
            println("\nThe flows and injections are not consistent.")
        end
    end
    consistent
end


function scale_branch_limits!(g::MetaGraph, ratio)
    for br in edge_labels(g)
        g[br...].p_max *= ratio
    end
end

function getbridges(g::MetaGraph, outages::Vector{ELabel}=ELabel[])::Vector{ELabel}
    h = copy(g)
    for br in outages
        delete!(h, br...)
    end
    _bridges = Graphs.bridges(Graph(h.graph))
    [e_label_for(h, br) for br in _bridges]
end


mutable struct Pocket
    buses::Vector{VLabel}
    branches::Vector{ELabel}
    innerbranches::Vector{ELabel}
    d::Float64
end

function _build_pocket_innerbranches(pk::Pocket, g::MetaGraph)
    ib = pk.innerbranches
    for bus in pk.buses
        for br in incident(g, bus)
            if opposite(br, bus) in pk.buses && !(br in ib)
                push!(ib, br)
            end
        end
    end
end

function Pocket(g::MetaGraph, buses::Vector{VLabel}, branches::Vector, d::Float64)
    pk = Pocket(buses, branches, ELabel[], d)
    _build_pocket_innerbranches(pk, g)
    pk
end

function create_bridge_to_pocket(g::MetaGraph, bus_orig::VLabel, outages::Vector{ELabel}=ELabel[])::Dict{ELabel,Pocket}

    function r_visit_bridges!(bridge_to_pocket, bus::VLabel, outages::Vector{ELabel}, bridges, visited_buses=VLabel[], crossed_bridges=ELabel[])
        push!(visited_buses, bus)
        for br in incident(g, bus)
            if br in outages
                continue
            end
            other_bus = opposite(br, bus)
            other_bus in visited_buses && continue
            for bridge in crossed_bridges
                pk = bridge_to_pocket[bridge]
                push!(pk.buses, other_bus)
                pk.d += max(g[other_bus], 0)
            end
            if br in bridges
                bridge_to_pocket[br] = Pocket(VLabel[other_bus], ELabel[], ELabel[], max(g[other_bus], 0))
                crossed_bridges2 = copy(crossed_bridges)
                push!(crossed_bridges2, br)
                r_visit_bridges!(bridge_to_pocket, other_bus, outages, bridges, visited_buses, crossed_bridges2)
            else
                r_visit_bridges!(bridge_to_pocket, other_bus, outages, bridges, visited_buses, crossed_bridges)
            end
        end
    end

    bridge_to_pocket = Dict{ELabel,Pocket}()
    bridges = getbridges(g, outages)
    r_visit_bridges!(bridge_to_pocket, bus_orig, outages, bridges)

    for bridge in bridges
        !(bridge in keys(bridge_to_pocket)) && continue
        pk = bridge_to_pocket[bridge]
        _buses = pk.buses
        # identify for each branch that is a bridge, the outages that makes it become a bridge, ie, having one bus on both sides.
        for outage in outages
            (bus1, bus2) = outage
            b1 = bus1 in _buses
            b2 = bus2 in _buses
            if (b1 && !b2) || (b2 && !b1)
                push!(pk.branches, outage)
            end
        end

        #identify inner branches
        _build_pocket_innerbranches(pk, g)
    end
    bridge_to_pocket
end