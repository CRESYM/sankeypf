using Makie
using CairoMakie
const EMPTYBRANCH = ("", "")
const BUTTONWIDTH = 90

buses_to_branch_val(val::Dict{ELabel,<:Any}, bus1, bus2) = haskey(val, (bus1, bus2)) ? val[bus1, bus2] : val[bus2, bus1]

function separate_flows_per_direction(g, flows, bus)
    outgoing, incoming = [], []
    for br in incident(g, bus)
        p = flows[br...]
        if p == 0
            push!(outgoing, br)
            push!(incoming, br)
        elseif from(br) == bus && p > 0 || to(br) == bus && p < 0
            push!(outgoing, br)
        else
            push!(incoming, br)
        end
    end
    (outgoing=outgoing, incoming=incoming)
end

function _create_maxpmax(separate_flows, flows)
    mpm = Dict{VLabel,Float64}() # received the max between the sum of incoming and outgoing flows, the breadth of the Sankey node
    for (bus, sp) in pairs(separate_flows)
        maxpmax = 0
        for outbranches in values(sp)
            pmax = isempty(outbranches) ? 0 : sum(abs(flows[br...]) for br in outbranches)
            maxpmax = max(maxpmax, pmax)
        end
        mpm[bus] = maxpmax
    end
    return mpm
end

function _create_combine_opposite(g, separate_flows)
    # for each bus, each direction (incoming or outgoing), the possible combinations of buses reached by the branches in that direction
    combine_opposite = Dict(bus => Dict(direction => [(opposite(br1, bus), opposite(br2, bus))
                                                      for (i, br1) in enumerate(branches)
                                                      for (j, br2) in enumerate(branches)
                                                      if i < j]
                                        for (direction, branches) in pairs(separate_flows[bus]))
                            for bus in labels(g))
    return combine_opposite
end

function _create_neighbor_buses(g, states, maxpmax, tan_limit)
    res = Vector{Tuple{VLabel,VLabel}}()
    for i in 1:nv(g), j in i+1:nv(g)
        bus1, bus2 = label_for(g, i), label_for(g, j)
        M = max(maxpmax[bus1], maxpmax[bus2])
        M = maxpmax[bus1] + maxpmax[bus2]
        δstates = abs((states[bus1]) - (states[bus2]))
        if δstates * tan_limit ≤ M / 2
            push!(res, (bus1, bus2))
        end
    end
    res
end

function init_stack_coord(g::MetaGraph)
    stack_coord = Dict{VLabel,Float64}(bus => 0. for bus in labels(g))
    stack_coord_offset = Dict{VLabel,Dict{VLabel,Float64}}(bus1 => Dict{VLabel,Float64}(opposite(br, bus1) => 0. for br in incident(g, bus1)) for bus1 in labels(g))
    (stack_coord=stack_coord, stack_coord_offset=stack_coord_offset)
end

function rearrange_stack_coord_offset!(stack_coord_offset, states, flows, stack_coord, flow_per_direction, maxpmax)
    for bus in keys(to_value(stack_coord))
        for direction in keys(to_value(flow_per_direction)[bus])
            branches = to_value(flow_per_direction)[bus][direction]
            isempty(branches) && continue
            sorted_buses = sort([opposite(br, bus) for br in branches], by=busop ->
                (to_value(stack_coord)[busop] + to_value(stack_coord_offset)[busop][bus] - to_value(stack_coord)[bus]) / max(1e-10, abs(to_value(states)[bus] - to_value(states)[busop])))
            y0 = -to_value(maxpmax)[bus] / 2
            for busop in sorted_buses
                fl = abs(buses_to_branch_val(to_value(flows), bus, busop))
                stack_coord_offset.val[bus][busop] = y0 + fl / 2
                y0 += fl
            end
        end
    end
end

function rearrange_stack_coord!(stack_coord, states, flows, y, sfpd, maxpmax, tan_strength, d_repulse)
    dstack_coord_tan = Dict{VLabel,Float64}()
    dY_repulse = Dict{VLabel,Float64}()
    # Δstates = (maximum(values(to_value(states))) - minimum(values(to_value(states)))) / 20.
    for bus in keys(to_value(stack_coord))
        branches = [to_value(sfpd)[bus][:outgoing]; to_value(sfpd)[bus][:incoming]]
        dstack_coord_tan[bus] = sum([
            # maxpmax[opposite(br, bus)] *
            # abs(buses_to_branch_val(flows, bus, opposite(br, bus))) *
            (to_value(stack_coord)[bus] - to_value(stack_coord)[opposite(br, bus)])
            for br in branches])

        repulse = 0
        for bus2 in keys(to_value(stack_coord))
            bus == bus2 && continue
            dstates = abs(to_value(states)[bus] - to_value(states)[bus2])
            # dstates > Δstates && continue
            dy = to_value(stack_coord)[bus] - to_value(stack_coord)[bus2]
            width = (to_value(maxpmax)[bus] + to_value(maxpmax)[bus2]) / 2
            abs_dy_width = max(abs(dy) - width, 0)
            D2 = max(((abs_dy_width)^2 + 10 * dstates^2), 5e-2)
            repulse += to_value(maxpmax)[bus] * to_value(maxpmax)[bus2] * sign(dy) / (D2 == 0 ? 1 : D2)
        end
        dY_repulse[bus] = repulse
    end

    for bus in keys(to_value(stack_coord))
        stack_coord.val[bus] -= dstack_coord_tan[bus] * to_value(tan_strength)
        stack_coord.val[bus] += dY_repulse[bus] * to_value(d_repulse)
    end

end

function _band_path(x1, x2, y1, y2, width, is_horizontal)
    width2 = width / 2
    if is_horizontal
        return BezierPath(
            [
            MoveTo(Point(x1, y1 - width2)),
            CurveTo(
                Point((2 * x1 + x2) / 3, y1 - width2),
                Point((x1 + 2 * x2) / 3, y2 - width2),
                Point(x2, y2 - width2)),
            LineTo(Point(x2, y2 + width2)),
            CurveTo(
                Point((x1 + 2 * x2) / 3, y2 + width2),
                Point((2 * x1 + x2) / 3, y1 + width2),
                Point(x1, y1 + width2)),
            ClosePath()])
    end
    return BezierPath(
        [
        MoveTo(Point(y1 - width2, x1)),
        CurveTo(
            Point(y1 - width2, (2 * x1 + x2) / 3),
            Point(y2 - width2, (x1 + 2 * x2) / 3),
            Point(y2 - width2, x2)),
        LineTo(Point(y2 + width2, x2)),
        CurveTo(
            Point(y2 + width2, (x1 + 2 * x2) / 3),
            Point(y1 + width2, (2 * x1 + x2) / 3),
            Point(y1 + width2, x1)),
        ClosePath()])
end

function _triangle_injection(x, y1, y2, width, is_horizontal)
    if is_horizontal
        return BezierPath(
            [
            MoveTo(Point(x, y1)),
            LineTo(Point(x + width, (y1 + y2) / 2)),
            LineTo(Point(x, y2)),
            ClosePath()])
    else
        return BezierPath(
            [
            MoveTo(Point(y1, x)),
            LineTo(Point((y1 + y2) / 2, x + width)),
            LineTo(Point(y2, x)),
            ClosePath()])
    end
end

function _create_node_from_flows(flows)
    node_from_flows = Dict{VLabel,Float64}()
    for (br, p) in pairs(flows)
        f, t = from(br), to(br)
        node_from_flows[f] = get(node_from_flows, f, 0.) - p
        node_from_flows[t] = get(node_from_flows, t, 0.) + p
    end
    node_from_flows
end

function draw_sankey!(ax, flows, maxflows, state_pos, stack_coord, stack_coord_offset, maxpmax, outages, stretch, is_horizontal)
    hidedecorations!(ax)

    _stack_coord = @lift(Dict(bus => val * $stretch for (bus, val) in $stack_coord))

    for br in keys(flows[])
        f, t = from(br), to(br)
        p = @lift(abs($flows[br...]))
        loadratio = @lift($p / maxflows[br...])
        p_overload = @lift((1 - 1 / $loadratio) * p[])
        col = @lift($loadratio ≤ 0.8 ? :green : $loadratio ≤ 1. ? :orange : :red)
        strokecol = @lift(br in $outages[1] ? :black : :transparent)

        path = @lift(_band_path(state_pos[][f], state_pos[][t], $_stack_coord[f] + stack_coord_offset[][f][t], $_stack_coord[t] + stack_coord_offset[][t][f], $p, is_horizontal))
        poly!(ax, path, color=col, alpha=0.5, strokewidth=2, strokecolor=strokecol)

        alpha = @lift($loadratio ≤ 1 ? 0. : 0.5)
        path = @lift(_band_path(state_pos[][f], state_pos[][t],
            $_stack_coord[f] + stack_coord_offset[][f][t] + (p[] - p_overload[]) / 2,
            $_stack_coord[t] + stack_coord_offset[][t][f] + (p[] - p_overload[]) / 2, p_overload[], is_horizontal))
        poly!(ax, path, color=:red, alpha=alpha)
    end

    nodes = _create_node_from_flows(flows[])

    Δstates = maximum(values(state_pos[])) - minimum(values(state_pos[]))
    for (bus, value) in nodes
        if is_horizontal
            lines!(ax, @lift([$state_pos[bus], $state_pos[bus]]), @lift($_stack_coord[bus] .+ maxpmax[][bus] ./ 2 .* [-1, 1]), linewidth=1, color=:black)
        else
            lines!(ax, @lift($_stack_coord[bus] .+ maxpmax[][bus] ./ 2 .* [-1, 1]), @lift([$state_pos[bus], $state_pos[bus]]), linewidth=1, color=:black)
        end

        if value > 0
            path = @lift(_triangle_injection($state_pos[bus], $_stack_coord[bus] + maxpmax[][bus] / 2 - value, $_stack_coord[bus] + maxpmax[][bus] / 2, Δstates / 100, is_horizontal))
            poly!(ax, path, color=:blue)
        elseif value < 0
            path = @lift(_triangle_injection($state_pos[bus] - Δstates / 100, $_stack_coord[bus] + maxpmax[][bus] / 2 + value, $_stack_coord[bus] + maxpmax[][bus] / 2, Δstates / 100, is_horizontal))
            poly!(ax, path, color=:blue)
        end

        if is_horizontal
            text!(ax, @lift($state_pos[bus]), @lift($_stack_coord[bus]); text=bus)
        else
            text!(ax, @lift($_stack_coord[bus]), @lift($state_pos[bus]); text=bus)
        end
    end
end

function img_export(sk_widget, filename)
    bb = sk_widget.ax.layoutobservables.computedbbox[]
    sz = (bb.widths[1], bb.widths[2])
    CairoMakie.activate!()
    fig_export = Figure(size=sz)
    ax = Axis(fig_export[1, 1])

    draw_sankey!(ax, sk_widget.flows, sk_widget.maxflows, sk_widget.states, sk_widget.stack_coord, sk_widget.stack_coord_offset,
        sk_widget.maxpmax, sk_widget.outages, sk_widget.stretch, sk_widget.is_horizontal)

    save(filename, fig_export)
end

function random_reset_stack_coord!(sk_widget)
    for bus in keys(to_value(sk_widget.stack_coord))
        to_value(sk_widget.stack_coord)[bus] = rand() - 0.5
    end
    notify(sk_widget.stack_coord)
end

function transit_flows_state!(sk_widget)
    to_value(sk_widget.step) == sk_widget.nb_transition_steps && return
    sk_widget.step[] = to_value(sk_widget.step) + 1
    step = to_value(sk_widget.step)
    foreach(bus ->
            to_value(sk_widget.states)[bus] =
                (sk_widget.next_states[bus] * step +
                 sk_widget.prev_states[bus] * (sk_widget.nb_transition_steps - step)) /
                sk_widget.nb_transition_steps,
        labels(sk_widget.g))
    foreach(br ->
            to_value(sk_widget.flows)[br...] =
                (sk_widget.next_flows[br...] * step +
                 sk_widget.prev_flows[br...] * (sk_widget.nb_transition_steps - step)) /
                sk_widget.nb_transition_steps,
        edge_labels(sk_widget.g))
    notify(sk_widget.states)
    notify(sk_widget.flows)
end

function update_loop(sk_widget)
    transit_flows_state!(sk_widget)
    rearrange_stack_coord!(sk_widget.stack_coord, sk_widget.states, sk_widget.flows, sk_widget.stack_coord_offset, sk_widget.separate_flows_per_direction, sk_widget.maxpmax, sk_widget.tan_strength, sk_widget.d_repulse)
    rearrange_stack_coord_offset!(sk_widget.stack_coord_offset, sk_widget.states, sk_widget.flows, sk_widget.stack_coord, sk_widget.separate_flows_per_direction, sk_widget.maxpmax)
    notify(sk_widget.stack_coord)

    sk_widget.auto_scale[] && autolimits!(sk_widget.ax)
end

function store_stack_coord(sk_widget)
    open(sk_widget.storeYfn, "w") do io
        println(io, "stretch, $(sk_widget.stretch[])")
        println(io, "tan_strength, $(sk_widget.tan_strength[])")
        println(io, "d_repulse, $(sk_widget.d_repulse[])")
        for (bus, stack_pos) in pairs(sk_widget.stack_coord[])
            println(io, "$bus,\t$stack_pos")
        end
    end
end

function load_stack_coord(sk_widget)
    open(sk_widget.storeYfn, "r") do io
        i = 1
        for line in eachline(io)
            fields = split(line, ',')
            if i ≤ 3
                if fields[1] == "stretch"
                    sk_widget.stretch[] = parse(Float64, strip(fields[2]))
                elseif fields[1] == "tan_strength"
                    sk_widget.tan_strength[] = parse(Float64, strip(fields[2]))
                elseif fields[1] == "d_repulse"
                    sk_widget.d_repulse[] = parse(Float64, strip(fields[2]))
                end
                i += 1
                continue
            end
            bus = strip(fields[1])
            stack_pos = parse(Float64, strip(fields[2]))
            sk_widget.stack_coord.val[bus] = stack_pos
        end
    end
    notify(sk_widget.stack_coord)
end

function stack_pos_widget(sk_widget, subfig)
    sl_gl = GridLayout(subfig[1, 1])
    Label(sl_gl[1, 1], "Bus")
    tbBus = Textbox(sl_gl[2, 1], stored_string=" ", width=30)
    sl = Slider(sl_gl[3, 1], range=0:0.01:1, horizontal=false, startvalue=0)

    on(tbBus.stored_string) do s
        max_y, min_y = minimum(values(to_value(sk_widget.stack_coord))), maximum(values(to_value(sk_widget.stack_coord)))
        set_close_to!(sl, (sk_widget.stack_coord[][s] - min_y) / (max_y - min_y))
    end

    on(sl.value) do v
        min_y, max_y = minimum(values(to_value(sk_widget.stack_coord))), maximum(values(to_value(sk_widget.stack_coord)))
        to_value(sk_widget.stack_coord)[tbBus.stored_string[]] = min_y + v * (max_y - min_y)
        notify(sk_widget.stack_coord)
    end

    button_gl = GridLayout(subfig[1, 2], tellheight=false)
    store_Y_but = Button(button_gl[1, 1], label="Store Y", width=BUTTONWIDTH, tellwidth=false)
    on(store_Y_but.clicks) do n
        store_stack_coord(to_value(sk_widget))
    end

    load_Y_but = Button(button_gl[2, 1], label="Load Y", width=BUTTONWIDTH, tellwidth=false)
    on(load_Y_but.clicks) do n
        load_stack_coord(sk_widget)
    end

end

function _create_slider(subfig, title, range, startval, horizontal)
    gl = GridLayout(subfig)
    Label(gl[1, 1], title)
    sl = Slider(horizontal ? gl[1, 2] : gl[2, 1], range=range, horizontal=horizontal, startvalue=startval)
    Label(horizontal ? gl[1, 3] : gl[3, 1], @lift(string($(sl.value))))
    if horizontal
        colsize!(gl, 1, Fixed(80))
        colsize!(gl, 3, Fixed(20))
    end
    sl.value
end


function force_layout_widget(gl_force_layout, sliders_orientation_horizontal)
    sliders_orientation_horizontal = true
    sl_stretch = _create_slider(gl_force_layout[1, 1], "Stretch", 0:0.01:10, 1, sliders_orientation_horizontal)
    sl_d_repulse = _create_slider(gl_force_layout[2, 1], "Repulse", 0:0.01:5, 2, sliders_orientation_horizontal)
    sl_d_align = _create_slider(gl_force_layout[3, 1], "Align", 0:0.01:5, 3, sliders_orientation_horizontal)

    (sl_stretch=sl_stretch, sl_d_repulse=sl_d_repulse, sl_d_align=sl_d_align)
end

function autoscale_button(sk_widget, subfig)
    autoscale = Button(subfig, label="Autoscale", width=BUTTONWIDTH, tellwidth=false)
    on(autoscale.clicks) do n
        sk_widget.auto_scale[] = !sk_widget.auto_scale[]
    end
end

function run_button(sk_widget, subfig)
    run = Button(subfig, label="Stop", width=BUTTONWIDTH, tellwidth=false)

    function _ensure_loop_running()
        if sk_widget.loop_task[] === nothing || istaskdone(sk_widget.loop_task[])
            sk_widget.loop_task[] = @async begin
                while sk_widget.is_running[]
                    update_loop(sk_widget)
                    yield()
                end
            end
        end
    end

    _ensure_loop_running()

    on(run.clicks) do _
        sk_widget.is_running[] = !sk_widget.is_running[]
        sk_widget.is_running[] && _ensure_loop_running()
    end
end

function close_button(sk_widget, subfig)
    close = Button(subfig, label="Close", width=BUTTONWIDTH, tellwidth=false)
    on(close.clicks) do n
        sk_widget.is_running[] = false
        @async begin
            @info "Closing in 3 seconds..."
            sleep(3)
            @info "Closing now."
            GLMakie.closeall()
        end
    end
end

function save_button(sk_widget, subfig, filename="tmp/sankey_export.svg")
    fig_save = Button(subfig, label="Save in SVG", width=BUTTONWIDTH, tellwidth=false)
    on(fig_save.clicks) do n
        img_export(sk_widget, filename)
    end
end

function update_flows!(sankeywidget, states::Dict{VLabel,Float64}, flows::Dict{ELabel,Float64})
    for bus in labels(sankeywidget.g)
        sankeywidget.prev_states[bus] = to_value(sankeywidget.states)[bus]
        sankeywidget.next_states[bus] = states[bus]
    end
    for br in edge_labels(sankeywidget.g)
        sankeywidget.prev_flows[br...] = to_value(sankeywidget.flows)[br...]
        sankeywidget.next_flows[br...] = flows[br]
    end
    sankeywidget.step[] = 0
end


function outages_widget(sk_widget, gl_outages)

    function _parse_branch(s::AbstractString)::ELabel
        part = strip(s)
        fields = split(part, '-', limit=2)
        if length(fields) == 2
            f, t = strip(fields[1]), strip(fields[2])
            f = string(isnothing(tryparse(Int, f)) ? f : tryparse(Int, f))
            t = string(isnothing(tryparse(Int, t)) ? t : tryparse(Int, t))
            @info f,t
            return f ≤ t ? (f, t) : (t, f)
        end
        return EMPTYBRANCH
    end

    function _parse_outages(s::AbstractString)::Set{ELabel}
        result = Set{ELabel}()
        for part in split(s, ',')
            _parse_branch(part) ≠ EMPTYBRANCH && push!(result, _parse_branch(part))
        end
        return result
    end

    function _update_topo(sk_widget)
        tripping = to_value(sk_widget.tripping)[1] == EMPTYBRANCH ? nothing : to_value(sk_widget.tripping)[1]
        outages = to_value(sk_widget.outages)[1]
        pf_res = dcpf(sk_widget.rc; outages=outages, tripping=tripping)
        update_flows!(sk_widget, pf_res.ϕ, pf_res.flows)
    end

    function _update_sa(sk_widget, outages)
        to_value(sk_widget.outages)[1] = _parse_outages(outages)
        notify(sk_widget.outages)
        _update_topo(sk_widget)
        sa_res = secured_dcpf(sk_widget.rc.gc, sk_widget.rc.bus_orig, to_value(sk_widget.outages)[1])
        vbs = violated_branches(sa_res, sk_widget.rc.gc.g)
        if isempty(vbs)
            sk_widget.sa_result[] = rich(" ")
        else
            sk_widget.sa_result[] =
                rich((rich(
                    rich("$(ctg[1])-$(ctg[2])", font=:bold),
                    " → ",
                    join(["$(vb[1])-$(vb[2])" for vb in vbs], ", "),
                    "\n"
                ) for (ctg, vbs) in vbs)...)
        end

        notify(sk_widget.sa_result)
    end

    Label(gl_outages[1, 1], "Outages")
    tbOutages = Textbox(gl_outages[1, 2], validator=r"^\s*(?:[^,\s-]+-[^,\s-]+)?(?:\s*,\s*[^,\s-]+-[^,\s-]+)*\s*$", stored_string=" ")
    on(tbOutages.stored_string) do outages
        _update_sa(sk_widget, outages)
    end

    Label(gl_outages[2, 1], "Tripping ")
    tbTripping = Textbox(gl_outages[2, 2], validator=r"^\s*(?:[^,\s-]+-[^,\s-]+)?(?:\s*,\s*[^,\s-]+-[^,\s-]+)*\s*$", stored_string=" ")
    on(tbTripping.stored_string) do s
        to_value(sk_widget.tripping)[1] = _parse_branch(s)
        notify(sk_widget.tripping)
        _update_topo(sk_widget)
    end

    _update_sa(sk_widget, "")

    Label(gl_outages[3, 1], sk_widget.sa_result; valign=:top)
end

function pf_sankey(rc::RichCase, states::Dict{VLabel,Float64}, flows::Dict{ELabel,Float64}, stack_coord::Dict{VLabel,Float64}, stack_coord_offset::Dict{VLabel,Dict{VLabel,Float64}}, storeYfn=""; outages=Set(ELabel[]), fig=nothing, is_horizontal=true, with_outages=true)
    g = rc.gc.g

    _stack_coord = Observable(stack_coord)
    _stack_coord_offset = Observable(stack_coord_offset)
    _states = Observable(states)
    _flows = Observable(flows)


    sfpd = @lift(Dict(bus => separate_flows_per_direction(g, $_flows, bus) for bus in labels(g)))
    maxpmax = @lift(_create_maxpmax($sfpd, $_flows))

    _fig = isnothing(fig) ? Figure(size=(800, 500)) : fig
    with_outages && (gl_outages = GridLayout(_fig[1:2, 1], tellheight=false, valign=:top))
    ax = Axis(_fig[1, 2])
    gl_store_stack_pos = GridLayout(_fig[1, 3])
    gl_force_layout = GridLayout(_fig[2, 2])
    gl_buttons = GridLayout(_fig[2, 3])

    mutable_outages = Observable([outages])
    mutable_tripping = Observable([EMPTYBRANCH])
    maxflows = Dict(br => g[br...].p_max for br in edge_labels(g))

    sl_stretch, sl_d_repulse, sl_d_align = force_layout_widget(gl_force_layout, true)

    draw_sankey!(ax, _flows, maxflows, _states, _stack_coord, _stack_coord_offset, maxpmax, mutable_outages, sl_stretch, is_horizontal)

    sk_widget = (fig=_fig, ax=ax, rc=rc, g=g, is_horizontal=is_horizontal,
        flows=_flows, maxflows=maxflows,
        states=_states,
        stack_coord=_stack_coord, stack_coord_offset=_stack_coord_offset,
        outages=mutable_outages, tripping=mutable_tripping,
        auto_scale=Observable{Bool}(true),
        sa_result=Observable{Makie.RichText}(rich(" ")),
        separate_flows_per_direction=sfpd, maxpmax=maxpmax,
        prev_states=copy(states), prev_flows=copy(flows),
        next_states=copy(states), next_flows=copy(flows),
        tan_strength=@lift(exp10($sl_d_align - 5)),
        d_repulse=@lift(exp10($sl_d_repulse - 5)),
        nb_transition_steps=20, step=Observable(0),
        stretch=sl_stretch,
        is_running=Observable{Bool}(true),
        loop_task=Ref{Union{Task,Nothing}}(nothing),
        storeYfn=storeYfn)

    stack_pos_widget(sk_widget, gl_store_stack_pos)
    autoscale_button(sk_widget, gl_buttons[1, 1])
    run_button(sk_widget, gl_buttons[2, 1])
    save_button(sk_widget, gl_buttons[1, 2], "tmp/sankey_export.svg")
    close_button(sk_widget, gl_buttons[2, 2])
    colsize!(gl_buttons, 1, Fixed(80))
    colsize!(gl_buttons, 2, Fixed(80))


    with_outages && outages_widget(sk_widget, gl_outages)

    isnothing(fig) && display(_fig)
    return sk_widget
end

function pf_sankey(rc::RichCase, states::Dict{VLabel,Float64}, flows::Dict{ELabel,Float64}, storeYfn=""; kwargs...)
    Y = init_stack_coord(rc.gc.g)
    sankeywidget = pf_sankey(rc, states, flows, Y.stack_coord, Y.stack_coord_offset, storeYfn; kwargs...)
    random_reset_stack_coord!(sankeywidget)
    sankeywidget
end

