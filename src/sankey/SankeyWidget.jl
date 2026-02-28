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

function pf_sanky_widget(fig, rc::RichCase, states::Dict{VLabel,Float64}, flows::Dict{ELabel,Float64}, stack_coord::Dict{VLabel,Float64}, stack_coord_offset::Dict{VLabel,Dict{VLabel,Float64}}, stretch, o_d_repulse::Observable, o_d_align::Observable, storeYfn=""; outages=Set(ELabel[]), is_horizontal=true)

    ax = Axis(fig)
    g = rc.gc.g
    maxflows = Dict(br => g[br...].p_max for br in edge_labels(g))

    _stack_coord = Observable(stack_coord)
    _stack_coord_offset = Observable(stack_coord_offset)
    _states = Observable(states)
    _flows = Observable(flows)

    sfpd = @lift(Dict(bus => separate_flows_per_direction(g, $_flows, bus) for bus in labels(g)))
    maxpmax = @lift(_create_maxpmax($sfpd, $_flows))

    mutable_outages = Observable([outages])

    draw_sankey!(ax, _flows, maxflows, _states, _stack_coord, _stack_coord_offset, maxpmax, mutable_outages, stretch, is_horizontal)

    sk_widget = (
        ax=ax,
        rc=rc,
        g=g,
        is_horizontal=is_horizontal,
        flows=_flows,
        maxflows=maxflows,
        states=_states,
        stack_coord=_stack_coord,
        stack_coord_offset=_stack_coord_offset,
        outages=mutable_outages,
        tripping=Observable([EMPTYBRANCH]),
        auto_scale=Observable{Bool}(true),
        sa_result=Observable{Makie.RichText}(rich(" ")),
        separate_flows_per_direction=sfpd,
        maxpmax=maxpmax,
        prev_states=copy(states),
        prev_flows=copy(flows),
        next_states=copy(states),
        next_flows=copy(flows),
        tan_strength=@lift(exp10($o_d_align - 5)),
        d_repulse=@lift(exp10($o_d_repulse - 5)),
        nb_transition_steps=NB_TRANSITION_STEPS,
        step=Observable(0),
        stretch=stretch,
        is_running=Observable{Bool}(true),
        loop_task=Ref{Union{Task,Nothing}}(nothing),
        storeYfn=storeYfn)

    return sk_widget
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

function update_flows!(sk_widget, states::Dict{VLabel,Float64}, flows::Dict{ELabel,Float64})
    for bus in labels(sk_widget.g)
        sk_widget.prev_states[bus] = to_value(sk_widget.states)[bus]
        sk_widget.next_states[bus] = states[bus]
    end
    for br in edge_labels(sk_widget.g)
        sk_widget.prev_flows[br...] = to_value(sk_widget.flows)[br...]
        sk_widget.next_flows[br...] = flows[br]
    end
    sk_widget.step[] = 0
end
