const EMPTYBRANCH = ("", "")

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

function _create_neighbor_buses(g, ϕ, maxpmax, tan_limit)
    res = Vector{Tuple{VLabel,VLabel}}()
    for i in 1:nv(g), j in i+1:nv(g)
        bus1, bus2 = label_for(g, i), label_for(g, j)
        M = max(maxpmax[bus1], maxpmax[bus2])
        M = maxpmax[bus1] + maxpmax[bus2]
        δϕ = abs((ϕ[bus1]) - (ϕ[bus2]))
        if δϕ * tan_limit ≤ M / 2
            push!(res, (bus1, bus2))
        end
    end
    res
end


function init_Y(g::MetaGraph)
    Y_center = Dict{VLabel,Float64}(bus => 0. for bus in labels(g))
    Y_offset = Dict{VLabel,Dict{VLabel,Float64}}(bus1 => Dict{VLabel,Float64}(opposite(br, bus1) => 0. for br in incident(g, bus1)) for bus1 in labels(g))
    (Y_center=Y_center, Y_offset=Y_offset)
end

function rearrange_y(ϕ, flows, Y_center, y_offset, sfpd, maxpmax)
    for bus in keys(to_value(Y_center))
        for direction in keys(to_value(sfpd)[bus])
            branches = to_value(sfpd)[bus][direction]
            isempty(branches) && continue
            sorted_buses = sort([opposite(br, bus) for br in branches], by=busop ->
                (to_value(Y_center)[busop] + to_value(y_offset)[busop][bus] - to_value(Y_center)[bus]) / max(1e-10, abs(to_value(ϕ)[bus] - to_value(ϕ)[busop])))
            y0 = -to_value(maxpmax)[bus] / 2
            for busop in sorted_buses
                fl = abs(buses_to_branch_val(to_value(flows), bus, busop))
                to_value(y_offset)[bus][busop] = y0 + fl / 2
                y0 += fl
            end
        end
    end
    notify(y_offset)
end

function rearrange_Y_center(ϕ, flows, Y_center, y, sfpd, maxpmax, tan_strength, d_repulse)
    dY_center_tan = Dict{VLabel,Float64}()
    dY_repulse = Dict{VLabel,Float64}()
    for bus in keys(to_value(Y_center))
        branches = [to_value(sfpd)[bus][:outgoing]; to_value(sfpd)[bus][:incoming]]
        dY_center_tan[bus] = sum([
            # maxpmax[opposite(br, bus)] *
            # abs(buses_to_branch_val(flows, bus, opposite(br, bus))) *
            (to_value(Y_center)[bus] - to_value(Y_center)[opposite(br, bus)])
            for br in branches])

        repulse = 0
        for bus2 in keys(to_value(Y_center))
            bus == bus2 && continue
            dϕ = abs(to_value(ϕ)[bus] - to_value(ϕ)[bus2])
            dy = to_value(Y_center)[bus] - to_value(Y_center)[bus2]
            width = (to_value(maxpmax)[bus] + to_value(maxpmax)[bus2]) / 2
            abs_dy_width = max(abs(dy) - width, 0)
            D2 = max(((abs_dy_width)^2 + 100 * dϕ^2), 5e-2)
            repulse += to_value(maxpmax)[bus2] * sign(dy) / (D2 == 0 ? 1 : D2)
        end
        dY_repulse[bus] = repulse
    end

    for bus in keys(to_value(Y_center))
        to_value(Y_center)[bus] -= dY_center_tan[bus] * to_value(tan_strength)
        to_value(Y_center)[bus] += dY_repulse[bus] * to_value(d_repulse)
    end
    notify(Y_center)
end

function _band_path(x1, x2, y1, y2, width)
    width2 = width / 2
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

function draw_sankey(g, ϕ, flows, Y_center, y_offset, outages, stretch, ax)
    hidedecorations!(ax)

    _Y_center = lift(stretch, Y_center) do stretch, Y_C
        Dict(bus => val * stretch for (bus, val) in Y_C)
    end

    for br in edge_labels(g)
        f, t = from(br), to(br)
        p = lift(fl -> abs(fl[br...]), flows)
        loadratio = lift(p -> p / g[br...].p_max, p)
        col = lift(loadratio) do loadratio
            to_value(loadratio) ≤ 0.8 ? :green : to_value(loadratio) ≤ 1. ? :orange : :red
        end
        strokecol = lift(outages) do outages
            br in to_value(outages)[1] ? :black : :transparent
        end
        path = lift(_Y_center, y_offset, ϕ, p) do Y_center, Y_offset, ϕ, p
            _band_path(ϕ[f], ϕ[t], Y_center[f] + Y_offset[f][t], Y_center[t] + Y_offset[t][f], p)
        end
        poly!(ax, path, color=col, alpha=0.5, strokewidth=2, strokecolor=strokecol)

        alpha = lift(loadratio) do loadratio
            to_value(loadratio) ≤ 1 ? 0. : 0.5
        end
        path = lift(_Y_center, y_offset, ϕ, p) do Y_C, Y_offset, ϕ, p
            p_overload = (1 - 1 / to_value(loadratio)) * to_value(p)
            _band_path(ϕ[f], ϕ[t],
                Y_C[f] + Y_offset[f][t] + (to_value(p) - p_overload) / 2,
                Y_C[t] + Y_offset[t][f] + (to_value(p) - p_overload) / 2, p_overload)
        end
        poly!(ax, path, color=:red, alpha=alpha)
    end

    for bus in labels(g)
        for (busto, val_y) in to_value(y_offset)[bus]
            flow2 = lift(flows) do flows
                abs(buses_to_branch_val(flows, bus, busto)) / 2
            end
            OY = lift(_Y_center, y_offset, flow2) do Y_center, y, flow2
                y0 = Y_center[bus] + y[bus][busto]
                y1 = y0 .- flow2
                y2 = y0 .+ flow2
                [y1[], y1[], y2[], y2[]]
            end

            Oϕ = lift(ϕ) do ϕ
                dir = (ϕ[busto] ≤ ϕ[bus] ? -1 : 1) * 5e-4
                x = ϕ[bus] + dir
                [x, x, x, x]
            end
            lines!(ax, Oϕ, OY, linewidth=1, color=:black)
        end

        yc = lift(_Y_center) do Y_center
            Y_center[bus]
        end
        ϕ_bus = lift(ϕ) do ϕ
            ϕ[bus]
        end
        text!(ax, ϕ_bus, yc; text=bus)
    end
end

function random_reset_Y_center(sk_widget)
    for bus in keys(to_value(sk_widget.Y_center))
        to_value(sk_widget.Y_center)[bus] = rand() - 0.5
    end
    notify(sk_widget.Y_center)
end

function transit_flows_state!(sk_widget)
    to_value(sk_widget.step) == sk_widget.nb_transition_steps && return
    sk_widget.step[] = to_value(sk_widget.step) + 1
    step = to_value(sk_widget.step)
    foreach(bus ->
            to_value(sk_widget.ϕ)[bus] =
                (sk_widget.next_ϕ[bus] * step +
                 sk_widget.prev_ϕ[bus] * (sk_widget.nb_transition_steps - step)) /
                sk_widget.nb_transition_steps,
        labels(sk_widget.g))
    foreach(br ->
            to_value(sk_widget.flows)[br...] =
                (sk_widget.next_flows[br...] * step +
                 sk_widget.prev_flows[br...] * (sk_widget.nb_transition_steps - step)) /
                sk_widget.nb_transition_steps,
        edge_labels(sk_widget.g))
    notify(sk_widget.ϕ)
    notify(sk_widget.flows)
end

function update_loop(sk_widget, tan_strength, d_repulse)
    transit_flows_state!(sk_widget)
    rearrange_Y_center(sk_widget.ϕ, sk_widget.flows, sk_widget.Y_center, sk_widget.Y_offset, sk_widget.separate_flows_per_direction, sk_widget.maxpmax, tan_strength, d_repulse)
    rearrange_y(sk_widget.ϕ, sk_widget.flows, sk_widget.Y_center, sk_widget.Y_offset, sk_widget.separate_flows_per_direction, sk_widget.maxpmax)
    to_value(sk_widget.auto_scale)[1] && autolimits!(sk_widget.ax)
end

function autoscale_button(sk_widget, subfig)
    autoscale = Button(subfig, label="autoscale", tellwidth=false)
    on(autoscale.clicks) do n
        to_value(sk_widget.auto_scale)[1] = !to_value(sk_widget.auto_scale)[1]
    end
end

function run_button(sk_widget, subfig)
    run = Button(subfig, label="stop", tellwidth=false)
    isrunning = Observable(true)
    on(run.clicks) do n
        isrunning[] = !isrunning[]
        @info "isrunning: $(isrunning[])"
    end

    on(run.clicks) do clicks
        @async while isrunning[]
            # isopen(fig.scene) || break # ensures computations stop if closed window
            update_loop(sk_widget, sk_widget.tan_strength, sk_widget.d_repulse)
            yield()
        end
    end
    @async while isrunning[]
        # isopen(fig.scene) || break # ensures computations stop if closed window
        update_loop(sk_widget, sk_widget.tan_strength, sk_widget.d_repulse)
        yield()
    end

    return isrunning
end

function close_button(subfig)
    close = Button(subfig, label="close", tellwidth=false)
    on(close.clicks) do n
        GLMakie.closeall()
    end
end

function change_flows_state!(sankeywidget, ϕ::Dict{VLabel,Float64}, flows::Dict{ELabel,Float64})
    for bus in labels(sankeywidget.g)
        sankeywidget.prev_ϕ[bus] = to_value(sankeywidget.ϕ)[bus]
        sankeywidget.next_ϕ[bus] = ϕ[bus]
    end
    for br in edge_labels(sankeywidget.g)
        sankeywidget.prev_flows[br...] = to_value(sankeywidget.flows)[br...]
        sankeywidget.next_flows[br...] = flows[br]
    end
    sankeywidget.step[] = 0
end

function outages_widget(sk_widget, gl_outages)
    function _parse_outages(s::AbstractString)::Set{ELabel}
        result = Set{ELabel}()
        for part in split(s, ',')
            part = strip(part)
            fields = split(part, '-', limit=2)
            if length(fields) == 2
                f, t = strip(fields[1]), strip(fields[2])
                push!(result, parse(Int, f) ≤ parse(Int, t) ? (f, t) : (t, f))
            end
        end
        return result
    end

    function _parse_tripping(s::AbstractString)
        part = strip(s)
        fields = split(part, '-', limit=2)
        if length(fields) == 2
            f, t = strip(fields[1]), strip(fields[2])
            return parse(Int, f) ≤ parse(Int, t) ? (f, t) : (t, f)
        end
        return EMPTYBRANCH
    end

    function _update_topo(sk_widget)
        tripping = to_value(sk_widget.tripping)[1] == EMPTYBRANCH ? nothing : to_value(sk_widget.tripping)[1]
        outages = to_value(sk_widget.outages)[1]
        pf_res = dcpf(sk_widget.rc; outages=outages, tripping=tripping)
        change_flows_state!(sk_widget, pf_res.ϕ, pf_res.flows)
    end

    Label(gl_outages[1, 1], "Outages")
    tbOutages = Textbox(gl_outages[1, 2], validator=r"^\s*(?:[^,\s-]+-[^,\s-]+)?(?:\s*,\s*[^,\s-]+-[^,\s-]+)*\s*$", stored_string=" ")
    on(tbOutages.stored_string) do s
        to_value(sk_widget.outages)[1] = _parse_outages(s)
        notify(sk_widget.outages)
        _update_topo(sk_widget)
        sa_res = secured_dcpf(sk_widget.rc.gc, sk_widget.rc.bus_orig, to_value(sk_widget.outages)[1])
        vbs = violated_branches(sa_res, sk_widget.rc.gc.g)
        to_value(sk_widget.sa_result)[1] = join(["$ctg $(join([vb[1] * "-" * vb[2] for vb in vbs],", "))" for (ctg, vbs) in vbs], "\n")
        notify(sk_widget.sa_result)
    end

    Label(gl_outages[1, 3], "Tripping ")
    tbTripping = Textbox(gl_outages[1, 4], validator=r"^\s*(?:[^,\s-]+-[^,\s-]+)?(?:\s*,\s*[^,\s-]+-[^,\s-]+)*\s*$", stored_string=" ")
    on(tbTripping.stored_string) do s
        to_value(sk_widget.tripping)[1] = _parse_tripping(s)
        notify(sk_widget.tripping)
        _update_topo(sk_widget)
    end

    sa_txt = lift(sk_widget.sa_result) do v
        isempty(v) || v[1] == "" ? " " : string(v[1])
    end
    Label(gl_outages[1, 5], sa_txt)
end

function pf_sankey(rc::RichCase, ϕ::Dict{VLabel,Float64}, flows::Dict{ELabel,Float64}, Y_center::Dict{VLabel,Float64}, Y_offset::Dict{VLabel,Dict{VLabel,Float64}}; outages=Set(ELabel[]), fig=nothing, stretch=1.)
    g = rc.gc.g

    _Y_center = Observable(Y_center)
    _Y_offset = Observable(Y_offset)
    _ϕ = Observable(ϕ)
    _flows = Observable(flows)


    sfpd = lift(_flows) do flows
        Dict(bus => separate_flows_per_direction(g, flows, bus) for bus in labels(g))
    end
    maxpmax = lift(_flows, sfpd) do flows, sfpd
        _create_maxpmax(sfpd, flows)
    end

    _fig = isnothing(fig) ? Figure(size=(800, 500)) : fig
    ax = Axis(_fig[1, 1:2])
    gl_sliders = GridLayout(_fig[1, 3])
    gl_buttons = GridLayout(_fig[2, 3])
    gl_outages = GridLayout(_fig[2, 1])

    function _create_slider(glpos, title, range, startval)
        Label(gl_sliders[1, glpos], title)
        sl = Slider(gl_sliders[2, glpos], range=range, horizontal=false, startvalue=startval)
        Label(gl_sliders[3, glpos], @lift(string($(sl.value))))
        sl.value
    end
    sl_stretch = _create_slider(1, "Stretch", 0:0.01:10, stretch)
    sl_d_repulse = _create_slider(2, "Repulse", 0:0.01:5, 2)
    sl_d_align = _create_slider(3, "Align", 0:0.01:5, 3)

    mutable_outages = Observable([outages])
    mutable_tripping = Observable([EMPTYBRANCH])

    draw_sankey(g, _ϕ, _flows, _Y_center, _Y_offset, mutable_outages, sl_stretch, ax)

    sk_widget = (fig=_fig, ax=ax, rc=rc, g=g, ϕ=_ϕ, flows=_flows,
        outages=mutable_outages, tripping=mutable_tripping,
        auto_scale=Observable([true]),
        sa_result=Observable([""]),
        separate_flows_per_direction=sfpd, maxpmax=maxpmax, Y_center=_Y_center, Y_offset=_Y_offset,
        prev_ϕ=copy(ϕ), prev_flows=copy(flows),
        next_ϕ=copy(ϕ), next_flows=copy(flows),
        tan_strength=@lift(exp10($sl_d_align - 5)),
        d_repulse=@lift(exp10($sl_d_repulse - 5)),
        nb_transition_steps=20, step=Observable(0), stretch=stretch)

    autoscale_button(sk_widget, gl_buttons[1, 1])
    run_button(sk_widget, gl_buttons[1, 2])
    close_button(gl_buttons[1, 3])

    outages_widget(sk_widget, gl_outages)

    isnothing(fig) && display(_fig)
    return sk_widget
end

function pf_sankey(rc::RichCase, ϕ::Dict{VLabel,Float64}, flows::Dict{ELabel,Float64}; kwargs...)
    Y = init_Y(rc.gc.g)
    sankeywidget = pf_sankey(rc, ϕ, flows, Y.Y_center, Y.Y_offset; kwargs...)
    random_reset_Y_center(sankeywidget)
    sankeywidget
end

