const BUTTONWIDTH = 90
const EMPTYBRANCH = ("", "")
const NB_TRANSITION_STEPS = 20

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

function outages_widget(sk_widget, gl_outages)

    function _parse_branch(s::AbstractString)::ELabel
        part = strip(s)
        fields = split(part, '-', limit=2)
        if length(fields) == 2
            f, t = strip(fields[1]), strip(fields[2])
            f = string(isnothing(tryparse(Int, f)) ? f : tryparse(Int, f))
            t = string(isnothing(tryparse(Int, t)) ? t : tryparse(Int, t))
            @info f, t
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

    _fig = isnothing(fig) ? Figure(size=(800, 500)) : fig

    g = rc.gc.g
    with_outages && (gl_outages = GridLayout(_fig[1:2, 1], tellheight=false, valign=:top))
    gl_store_stack_pos = GridLayout(_fig[1, 3])
    gl_force_layout = GridLayout(_fig[2, 2])
    gl_buttons = GridLayout(_fig[2, 3])

    sl_stretch, sl_d_repulse, sl_d_align = force_layout_widget(gl_force_layout, true)

    sk_widget = pf_sanky_widget(_fig[1,2], rc, states, flows, stack_coord, stack_coord_offset, sl_stretch, sl_d_repulse, sl_d_align, storeYfn; outages=outages, is_horizontal=is_horizontal)

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

