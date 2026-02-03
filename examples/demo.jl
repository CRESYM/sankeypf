using SankeyPF
using GLMakie
using MetaGraphsNext

case = "case14"

rc = create_case(case, 1.)
g = rc.gc.g

if case == "case14"
    foreach(e -> g[e...].p_max = 1.1, edge_labels(g))
    g["A"] = -2.34
    g["B"] = -0.18300000000000002
    g["N"] = 1.
    g["H"] = 0.5
    g["A", "B"].p_max = 3
    g["B", "D"].p_max = 3
    g["A", "E"].p_max = 3
    g["D", "E"].p_max = 1.7
    g["B", "E"].p_max = 0.9
    g["D", "I"].p_max = 0.33
    balance!(g, all_non_zero_uniform)
end

pf_res = dcpf(rc)

GLMakie.activate!(; focus_on_show=true, title="Sankey Power Flow Demo")
fig = Figure(size=(800, 500))

skWidget = pf_sankey(rc, pf_res.ϕ, pf_res.flows, "tmp/Y_center_$case.csv"; fig=fig[1, 1], is_horizontal=true);

display(fig)