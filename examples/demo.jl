using SankeyPF
using GLMakie

rc = create_case("case118", 1.)
outages = Set([("54", "59"), ("54", "56"), ("106", "107"), ("42", "49"), ("92", "100"), ("88", "89"), ("77", "80"), ("24", "70"), ("49", "69"), ("59", "60"), ("5", "11"), ("17", "30"), ("37", "40"), ("47", "49"), ("84", "85"), ("80", "81"), ("96", "97"), ("64", "65"), ("19", "34"), ("15", "33"), ("61", "62"), ("100", "106"), ("45", "49"), ("48", "49"), ("30", "38")])
# outages = Set{ELabel}()
pf_res = dcpf(rc; outages=outages)#, [("49","66")])

GLMakie.activate!(; focus_on_show=true, title="Sankey Power Flow Demo")
fig = Figure(size=(800, 500))

skWidget = pf_sankey(rc.gc.g, pf_res.ϕ, pf_res.flows; outages=outages, fig=fig[1, 1])#MIPGap=0.5, tan_limit=50, big_M=100, fig=fig[1, 1])#, fig=fig[1, 1])


skWidget.tan_strength[] = 2e-2
# skWidget.d_repulse[] = 3e-3

# change_flows_state!(skWidget, m_res, "49-66")
# change_flows_state!(skWidget, m_res, "-")
# random_reset_Y_center(skWidget)
display(fig)
