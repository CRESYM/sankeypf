
buses_to_branch_val(val::Dict{ELabel,<:Any}, bus1, bus2) = haskey(val, (bus1, bus2)) ? val[bus1, bus2] : val[bus2, bus1]

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
        MoveTo(Point(y1 - width2, -x1)),
        CurveTo(
            Point(y1 - width2, -(2 * x1 + x2) / 3),
            Point(y2 - width2, -(x1 + 2 * x2) / 3),
            Point(y2 - width2, -x2)),
        LineTo(Point(y2 + width2, -x2)),
        CurveTo(
            Point(y2 + width2, -(x1 + 2 * x2) / 3),
            Point(y1 + width2, -(2 * x1 + x2) / 3),
            Point(y1 + width2, -x1)),
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
            MoveTo(Point(y1, -x)),
            LineTo(Point((y1 + y2) / 2, -x - width)),
            LineTo(Point(y2, -x)),
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
        path = @lift(_band_path(state_pos[][f], state_pos[][t],   # minus for flows flowing from top to bttom.
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
            lines!(ax, @lift($_stack_coord[bus] .+ maxpmax[][bus] ./ 2 .* [-1, 1]), @lift([-$state_pos[bus], -$state_pos[bus]]), linewidth=1, color=:black)
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
            text!(ax, @lift($_stack_coord[bus]), @lift(-$state_pos[bus]); text=bus)
        end
    end
end
