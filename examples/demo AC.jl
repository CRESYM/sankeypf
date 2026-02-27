# This case is just a first quick and dirty trial, and the results are NONE CONCLUSIVE.
# Consider it as a sandbox with a work in progress pipeline built that must be further improved.
# BUG: the injections are the active injections
# The idea is to represent the Reactive power flows in a sankey sorted by the Voltage Magnitude.
# As the reactive power generated or withdrawn by the branches cannot be neglected, the "KCL law" does not properly apply on buses.

using SankeyPF
using GLMakie

using PGLib
using PowerModels
using Ipopt
using MetaGraphsNext


function balance!(c::Dict{String,Any})
    inj = Dict{Int,Dict{String,Float64}}()
    for load in values(c["load"])
        inj[load["load_bus"]] = Dict("pd" => load["pd"], "qd" => load["qd"])
    end
    for gen in values(c["gen"])
        get!(inj, gen["gen_bus"], Dict{String,Float64}())
        inj[gen["gen_bus"]]["pg"] = gen["pg"]
        inj[gen["gen_bus"]]["qg"] = gen["qg"]
    end

    ref_buses = [i for (i, b) in c["bus"] if b["bus_type"] == 3]
    ref_bus = Ref{Any}()
    if isempty(ref_buses)
        @error("No reference bus found in the case.")
    else
        ref_bus = ref_buses[1]
    end

    imbalance = 0
    adjustable = 0
    adjustable_gens = Int[] # to align with GraphUtils, only generators with not loads on the same bus can be adjustable
    for (bus, injv) in inj
        if haskey(injv, "pd")
            imbalance += -injv["pd"] + get(injv, "pg", 0)
        else
            imbalance += get(injv, "pg", 0)
            adjustable_gens = push!(adjustable_gens, bus)
            adjustable += get(injv, "pg", 0)
        end
    end

    for gen in adjustable_gens
        inj[gen]["pg"] -= imbalance * inj[gen]["pg"] / adjustable
    end
end


case = "case14_" # with the '_', the name of the buses is not changed to "A", "B" in rc=create_case(...), and remains the same than for c=pglib(...) 

rc = create_case(case, 1.)
c = pglib(case)
balance!(c)
result = PowerModels.solve_ac_pf(c, Ipopt.Optimizer)
update_data!(c, result["solution"])
flows = calc_branch_flow_ac(c)
update_data!(c, flows)

v_dict = Dict{VLabel,Float64}()
for bus in labels(rc.gc.g)
    v_dict[bus] = result["solution"]["bus"][bus]["vm"]
end

@info v_dict

# v_dict = Dict{VLabel,Float64}()
# for bus in labels(rc.gc.g)
#     v_dict[bus] = -result["solution"]["bus"][bus]["va"]
# end

q_dict = Dict{ELabel,Float64}()
# for br in edge_labels(rc.gc.g)
#     q_dict[br] = rc.gc.g[br...].b * (v_dict[br[2]] - v_dict[br[1]])
# end

for (kbr, vbr) in c["branch"]
    br_label, sign = vbr["f_bus"] ≤ vbr["t_bus"] ?
                     (("$(vbr["f_bus"])", "$(vbr["t_bus"])"), 1) :
                     (("$(vbr["t_bus"])", "$(vbr["f_bus"])"), -1)
    q_dict[br_label...] = flows["branch"][kbr]["qt"]
end

# for (kbr, vbr) in c["branch"]
#     br_label, sign = vbr["f_bus"] ≤ vbr["t_bus"] ?
#                      (("$(vbr["f_bus"])", "$(vbr["t_bus"])"), 1) :
#                      (("$(vbr["t_bus"])", "$(vbr["f_bus"])"), -1)
#     q_dict[br_label...] = flows["branch"][kbr]["pf"]
# end

GLMakie.activate!(; focus_on_show=true, title="Sankey Power Flow Demo")
fig = Figure(size=(800, 500))

skWidget = pf_sankey(rc, v_dict, q_dict, "tmp/Y_center.csv"; fig=fig[1, 1], is_horizontal=false, with_outages=false);
display(fig)



