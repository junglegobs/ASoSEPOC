include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs(plotsdir(sn))
rm(simsdir(sn); force=true, recursive=true)

opts = options_diff_days(sn)[3]
opts["initial_state_of_charge"] = 0.0
# opts["reserve_shedding_limit"] => 0.05
opts["unit_commitment_type"] = "none"
opts["upward_reserve_levels_included_in_redispatch"] = 1:10
opts["downward_reserve_levels_included_in_redispatch"] = 1:10
opts["absolute_limit_on_nodal_imbalance"] = true
opts["time_out"] = 120
gep_abs_lim = run_GEPPR(opts)

opts["absolute_limit_on_nodal_imbalance"] = false
opts["save_path"] *= "_n"
gep_no_lim = run_GEPPR(opts)

gep_vec = [gep_no_lim, gep_abs_lim]
df = DataFrame(
    "Limits" => ["Absolute", "None"],
    "Reserve Shedding" => sum.([gep[:rsL⁺] for gep in gep_vec]),
    "Load shedding" => sum.([gep[:loadShedding] for gep in gep_vec]),
)
