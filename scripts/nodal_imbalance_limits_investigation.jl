include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs(plotsdir(sn))
rm(simsdir(sn); force=true, recursive=true)

opts = options_diff_days(sn)[4]
opts["initial_state_of_charge"] = 0.5
# opts["optimization_horizon"] = (7393, 7394)
opts["load_multiplier"] = 1.5
opts["initial_state_of_charge"] = 0.0
opts["unit_commitment_type"] = "none"
opts["time_out"] = 120

opts["absolute_limit_on_nodal_imbalance"] = false
gep_no_lim = run_GEPPR(opts)

opts["upward_reserve_levels_included_in_redispatch"] = 1:10
opts["downward_reserve_levels_included_in_redispatch"] = 1:10
opts["absolute_limit_on_nodal_imbalance"] = true
opts["save_path"] *= "_abs"
gep_abs_lim = run_GEPPR(opts)

opts["convex_hull_limits_on_nodal_imbalance"] = true
opts["save_path"] *= "_conv"
gep_conv_lim = run_GEPPR(opts)

gep_vec = [gep_no_lim, gep_abs_lim, gep_conv_lim]
df = DataFrame(
    "Limits" => ["None", "Absolute", "Convex"],
    "Reserve Shedding" => sum.([gep[:rsL⁺] for gep in gep_vec]),
    "Load shedding" => sum.([gep[:loadShedding] for gep in gep_vec]),
    "Objective" => [gep[:objective] for gep in gep_vec],
)
