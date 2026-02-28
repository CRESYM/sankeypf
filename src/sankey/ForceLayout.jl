function init_stack_coord(g::MetaGraph)
    stack_coord = Dict{VLabel,Float64}(bus => 0. for bus in labels(g))
    stack_coord_offset = Dict{VLabel,Dict{VLabel,Float64}}(bus1 => Dict{VLabel,Float64}(opposite(br, bus1) => 0. for br in incident(g, bus1)) for bus1 in labels(g))
    (stack_coord=stack_coord, stack_coord_offset=stack_coord_offset)
end

function random_reset_stack_coord!(sk_widget)
    for bus in keys(to_value(sk_widget.stack_coord))
        to_value(sk_widget.stack_coord)[bus] = rand() - 0.5
    end
    notify(sk_widget.stack_coord)
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
