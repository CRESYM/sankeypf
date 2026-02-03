using SankeyPF
using GLMakie

using PGLib
using PowerModels
using Ipopt
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

skWidget = pf_sankey(rc, pf_res.ϕ, pf_res.flows, "tmp/Y_center.csv"; fig=fig[1, 1], is_horizontal=true);

display(fig)


# function balance!(c::Dict{String,Any})
#     inj = Dict{Int,Dict{String,Float64}}()
#     for load in values(c["load"])
#         inj[load["load_bus"]] = Dict("pd" => load["pd"], "qd" => load["qd"])
#     end
#     for gen in values(c["gen"])
#         get!(inj, gen["gen_bus"], Dict{String,Float64}())
#         inj[gen["gen_bus"]]["pg"] = gen["pg"]
#         inj[gen["gen_bus"]]["qg"] = gen["qg"]
#     end

#     ref_buses = [i for (i,b) in data["bus"] if b["bus_type"] == 3]
#     ref_bus=Ref{Any}()
#     if is_empty(ref_buses)
#         @error("No reference bus found in the case.")
#     else
#         ref_bus= ref_buses[1]
#     end

#     for bus in c["buses"]


#     end

#     imbalance = 0
#     adjustable = 0
#     adjustable_gens = Int[] # to align with GraphUtils, only generators with not loads on the same bus can be adjustable
#     for (bus, injv) in inj
#         if haskey(injv, "pd")
#             imbalance += -injv["pd"] + get(injv, "pg", 0)
#         else
#             imbalance += get(injv, "pg", 0)
#             adjustable_gens = push!(adjustable_gens, bus)
#             adjustable += get(injv, "pg", 0)
#         end
#     end

#     for gen in adjustable_gens
#         inj[gen]["pg"] -= imbalance * inj[gen]["pg"] / adjustable
#     end 
# end



# c = pglib(case)
# balance!(c)
# result = PowerModels.solve_dc_pf(c, Ipopt.Optimizer)
# update_data!(c, result["solution"])
# flows = calc_branch_flow_dc(c)
# update_data!(c, flows)

# using MetaGraphsNext
# # v_dict = Dict{VLabel,Float64}()
# # for bus in labels(rc.gc.g)
# #     v_dict[bus] = result["solution"]["bus"][bus]["vm"]
# # end

# v_dict = Dict{VLabel,Float64}()
# for bus in labels(rc.gc.g)
#     v_dict[bus] = -result["solution"]["bus"][bus]["va"]
# end

# q_dict = Dict{ELabel,Float64}()
# # for br in edge_labels(rc.gc.g)
# #     q_dict[br] = rc.gc.g[br...].b * (v_dict[br[2]] - v_dict[br[1]])
# # end

# # for (kbr, vbr) in c["branch"]
# #     br_label, sign = vbr["f_bus"] ≤ vbr["t_bus"] ?
# #                      (("$(vbr["f_bus"])", "$(vbr["t_bus"])"), 1) :
# #                      (("$(vbr["t_bus"])", "$(vbr["f_bus"])"), -1)
# #     q_dict[br_label...] = flows["branch"][kbr]["qt"]
# # end

# for (kbr, vbr) in c["branch"]
#     br_label, sign = vbr["f_bus"] ≤ vbr["t_bus"] ?
#                      (("$(vbr["f_bus"])", "$(vbr["t_bus"])"), 1) :
#                      (("$(vbr["t_bus"])", "$(vbr["f_bus"])"), -1)
#     q_dict[br_label...] = flows["branch"][kbr]["pf"]
# end

# skWidget = pf_sankey(rc, v_dict, q_dict, "tmp/Y_center.csv"; fig=fig[1, 1], is_horizontal=false);
# display(fig)



