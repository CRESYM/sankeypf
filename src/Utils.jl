function create_case(case::String, ratio=nothing)::RichCase
    project_path = dirname(Base.active_project())
    buslabels = Function
    if case == "case14"
        labs = collect('A':'Z')
        buslabels = num -> "$(labs[num])"
    else
        buslabels = lab -> "$lab"
    end
    g = PGLibtograph(case, buslabels)

    drawparams = Dict{Symbol,Any}()
    coordpath = joinpath(project_path, "data", "exp_raw", "coord", "$case.csv")
    if isfile(coordpath)
        drawparams[:layout] = load_coord(coordpath, buslabels)
    end
    drawparams[:power_scale] = 100
    drawparams[:digits] = 0


    bus_confs = Int[]
    trippings = nothing
    !isnothing(ratio) && scale_branch_limits!(g, ratio)


    labs = collect(labels(g))
    balance!(g)
    bus_orig = labs[findmin(bus -> g[bus], labels(g))[2]]
    return RichCase(ElementaryCase(g), bus_orig, drawparams)
end
