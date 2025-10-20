using SankeyPF
using GLMakie

rc = create_case("case118", 1.5)
pf_res = dcpf(rc)

GLMakie.activate!(; focus_on_show=true, title="Sankey Power Flow Demo")
fig = Figure(size=(800, 500))

skWidget = pf_sankey(rc, pf_res.ϕ, pf_res.flows; fig=fig[1, 1])

display(fig)
