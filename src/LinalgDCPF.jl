struct SA_result
    contingencies::Dict{ELabel,Int}
    branches::Dict{ELabel,Int}
    flows::Matrix{Float64}
end


function get_main_connected_component(g::MetaGraph, bus_orig::VLabel, outages::Set{ELabel}, tripping::Union{Nothing,ELabel}=nothing)

    function _r_connected_component!(cc_buses::Set{VLabel}, cc_edges::Set{ELabel}, g::MetaGraph, openbranches::Set{ELabel}, bus::VLabel)
        push!(cc_buses, bus)
        for edg in incident(g, bus)
            (edg in openbranches || edg in cc_edges) && continue
            push!(cc_edges, edg)
            bus_to = opposite(edg, bus)
            bus_to ∉ cc_buses && _r_connected_component!(cc_buses, cc_edges, g, openbranches, bus_to)
        end
    end

    cc_buses, cc_edges = Set{VLabel}(), Set{ELabel}()
    openbranches = Set{ELabel}(outages)
    !isnothing(tripping) && push!(openbranches, tripping)
    _r_connected_component!(cc_buses, cc_edges, g, openbranches, bus_orig)
    return (buses=cc_buses, edges=cc_edges)
end


function dcpf(gc::ElementaryCase, bus_orig::VLabel; outages::Set{ELabel}=Set{ELabel}(), tripping::Union{Nothing,ELabel}=nothing, connectivitiy_to_check::Bool=true)::Union{Nothing,NamedTuple}

    g = gc.g
    A = incidence_matrix(g; oriented=true)
    p_wo_orig = nothing
    orig_id, _buses, _edges = nothing, nothing, nothing

    if connectivitiy_to_check && !(isempty(outages) && isnothing(tripping))
        cc = get_main_connected_component(g, bus_orig, outages, tripping)

        _buses, cc_bus_ids = VLabel[], Int[]
        j = 1
        for (i, bus) in enumerate(labels(g))            # build cc_bus_ids, and update orig_id: the position of bus_id in the restriction to the connected component
            bus ∉ cc.buses && continue
            push!(_buses, bus)
            push!(cc_bus_ids, i)
            bus == bus_orig && (orig_id = j)
            j += 1
        end

        _edges, cc_edge_ids = ELabel[], Int[]
        for (j, edge) in enumerate(edge_labels(g))
            edge ∉ cc.edges && continue
            push!(_edges, edge)
            push!(cc_edge_ids, j)
        end

        A = A[cc_bus_ids, cc_edge_ids]
        p_wo_orig = [g[bus] for bus in labels(g) if (bus ∈ _buses) && (bus ≠ bus_orig)] # labels(g) needs to be trasversed to guarantee the ordering coherent as it is not the case in cc.buses

        imbalance = sum(p_wo_orig) + g[bus_orig]
        gen = sum(p for p in p_wo_orig if p ≤ 0) + (g[bus_orig] ≤ 0 ? g[bus_orig] : 0)
        if gen ≠ 0
            foreach(i -> p_wo_orig[i] ≤ 0 && (p_wo_orig[i] -= p_wo_orig[i] * imbalance / gen), eachindex(p_wo_orig)) # balance on generation. No need to involve bus_orig even if it is a gen as it is the slack node.
        else
            @error "connected component cannot be balanced without generation"
            return
        end
    else
        orig_id = code_for(g, bus_orig)
        _buses = labels(g)
        _edges = edge_labels(g)
        p_wo_orig = [g[bus] for bus in _buses if bus ≠ bus_orig]
    end

    D = spdiagm(map(e -> g[e...].b, _edges))
    B = A * D * A'
    B_wo_orig = B[1:end.≠orig_id, 1:end.≠orig_id]
    ϕ_wo_orig = B_wo_orig \ p_wo_orig
    ϕ = [ϕ_wo_orig[1:orig_id-1]; 0; ϕ_wo_orig[orig_id:end]]
    flows = D * A' * ϕ

    d_ϕ = Dict(b => 0. for b in labels(g))
    foreach(kv -> d_ϕ[kv[2]] = ϕ[kv[1]], enumerate(_buses))

    d_flows = Dict(e => 0. for e in edge_labels(g))
    foreach(kv -> (d_flows[kv[2]] = flows[kv[1]]), enumerate(_edges))

    d_p = Dict(b => 0. for b in labels(g))
    foreach(kv -> d_p[kv[2]] = p_wo_orig[kv[1]], enumerate((bus for bus in _buses if bus ≠ bus_orig)))
    d_p[bus_orig] = sum(br_sign[2] * d_flows[br_sign[1]] for br_sign in incident_signed(g, bus_orig))

    return (flows=d_flows, ϕ=d_ϕ, p=d_p)
end

function dcpf(rc::RichCase; kwargs...)
    dcpf(rc.gc, rc.bus_orig; kwargs...)
end

function dcpf!(gc::GridCase, bus_orig; kwargs...)
    pf_res = dcpf(gc, bus_orig; kwargs...)
    setflows!(gc.g, pf_res.flows)
    for bus in labels(gc.g)
        gc.g[bus] = pf_res.p[bus]
    end
    pf_res
end

function dcpf!(rc::RichCase; kwargs...)
    dcpf!(rc.gc, rc.bus_orig; kwargs...)
end


function secured_dcpf(gc::GridCase, bus_orig::VLabel, outages::Set=Set(), contingencies::Union{Nothing,Vector{ELabel}}=nothing; bridge_to_pocket::Union{Nothing,Dict{ELabel,Pocket}}=nothing, include_base_case::Bool=true)
    g = gc.g
    _bridge_to_pocket = isnothing(bridge_to_pocket) ? create_bridge_to_pocket(g, bus_orig, collect(ELabel, outages)) : bridge_to_pocket
    BASECONTINGENCY = ("", "")
    _contingencies = include_base_case ? ELabel[BASECONTINGENCY] : ELabel[]
    append!(_contingencies, isnothing(contingencies) ? collect(edge_labels(g)) : contingencies)
    orig_id = code_for(g, bus_orig)
    edge_ids = Dict(e => i for (i, e) in enumerate(edge_labels(g)))

    A = incidence_matrix(g; oriented=true)
    for br in outages
        A[:, edge_ids[br]] .= 0
    end

    D = spdiagm(map(e -> g[e...].b, edge_labels(g)))
    B = A * D * A'

    B_wo_orig = B[1:end.≠orig_id, 1:end.≠orig_id]
    p_wo_orig = [g[bus] for bus in labels(g) if bus ≠ bus_orig]

    ϕ_wo_orig_to_ϕ = spzeros(nv(g), nv(g) - 1)
    foreach(i -> ϕ_wo_orig_to_ϕ[i+(i≥orig_id), i] = 1, 1:nv(g)-1)
    ϕ_to_flows = D * A' * ϕ_wo_orig_to_ϕ

    res_flows = zeros(length(_contingencies), ne(g))

    function _change_b_wo_orig(i, j, δb)
        (i == orig_id || j == orig_id) && return
        B_wo_orig[i-(i>orig_id), j-(j>orig_id)] += δb
    end

    for (i, br) in enumerate(_contingencies)
        br ≠ BASECONTINGENCY && (e_id = edge_ids[br])
        from_id, to_id = 0, 0

        if br ≠ BASECONTINGENCY
            from_id, to_id = code_for(g, from(br)), code_for(g, to(br))

            # remove the influence of the impedance of the open branch (don't do it if already open)
            b = g[br...].b
            if br ∉ outages
                _change_b_wo_orig(from_id, from_id, -b)
                _change_b_wo_orig(to_id, to_id, -b)
                _change_b_wo_orig(from_id, to_id, +b)
                _change_b_wo_orig(to_id, from_id, +b)
            end
        end

        if br in keys(_bridge_to_pocket)  # A pocket will be deenergized
            pk = _bridge_to_pocket[br]
            pkbuses = Set(pk.buses)
            inbus_ids, pkbus_ids = Int[], Int[]
            for (j, bus) in enumerate(labels(g))
                j == orig_id && continue
                k = j - (j ≥ orig_id)
                if (bus ∉ pkbuses)
                    push!(inbus_ids, k)
                else
                    push!(pkbus_ids, k)
                end
            end

            δp = zeros(nv(g)) # to be added to p_wo_orig

            #balancing inside the area
            imbalance = -sum(p_wo_orig[pkbus_ids]) # the global system is balanced, so the imbalance is minus what is in the pocket
            ingen_ids = [i for i in inbus_ids if p_wo_orig[i] ≤ 0]
            genglob = sum(p_wo_orig[ingen_ids]) + (g[bus_orig] ≤ 0 ? g[bus_orig] : 0)  # if the bus orig is a generator, it was part of the initial balance
            foreach(bus_id -> δp[bus_id] = -p_wo_orig[bus_id] * imbalance / genglob, ingen_ids)

            ϕ_wo_orig = zeros(nv(g) - 1)
            ϕ_wo_orig[inbus_ids] = B_wo_orig[inbus_ids, inbus_ids] \ (p_wo_orig[inbus_ids] + δp[inbus_ids])
            flows = ϕ_to_flows * ϕ_wo_orig
            br ≠ BASECONTINGENCY && (flows[e_id] = 0)
            res_flows[i, :] = flows

        else            # no imbalance to handle
            ϕ_wo_orig = B_wo_orig \ p_wo_orig
            flows = ϕ_to_flows * ϕ_wo_orig
            br ≠ BASECONTINGENCY && (flows[e_id] = 0)
            res_flows[i, :] = flows
        end

        # restore the influence of the impedance of the open branch for next iterations
        if br ≠ BASECONTINGENCY && br ∉ outages
            _change_b_wo_orig(from_id, from_id, +b)
            _change_b_wo_orig(to_id, to_id, +b)
            _change_b_wo_orig(from_id, to_id, -b)
            _change_b_wo_orig(to_id, from_id, -b)
        end
    end

    SA_result(
        Dict(e => i for (i, e) in enumerate(_contingencies)),
        edge_ids,
        res_flows
    )
end


flow(sr::SA_result, ctg::ELabel, br::ELabel) = sr.flows[sr.contingencies[ctg], sr.branches[br]]


function violated_branches(sr::SA_result, g::MetaGraph, contingency::ELabel)::Set{ELabel}
    branches = Set{ELabel}()
    for br in edge_labels(g)
        if abs(flow(sr, contingency, br)) > g[br...].p_max
            push!(branches, br)
        end
    end
    branches
end

function violated_branches(sr::SA_result, g::MetaGraph)::Dict{ELabel, Set{ELabel}}
    ctg_to_vbrs = Dict{ELabel, Set{ELabel}}()
    for ctg in keys(sr.contingencies)
        vbrs = violated_branches(sr, g, ctg)
        !isempty(vbrs) && (ctg_to_vbrs[ctg] = vbrs)
    end
    ctg_to_vbrs
end

function max_overload(sr::SA_result, g::MetaGraph, contingency::ELabel, branches::Vector{ELabel})
    maxval, index = findmax(br -> abs(flow(sr, contingency, br)) / g[br...].p_max, branches)
    maxval, branches[index]
end

function eval_risk(rc, openings)
    b2p = create_bridge_to_pocket(rc.gc.g, rc.bus_orig, openings)
    return sum(pk.d for pk in values(b2p))
end