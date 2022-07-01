include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs(plotsdir(sn))

function run_debug_abs_imb_infeasible(L)
    opts = options_diff_days(sn, "days_for_analysis_2022_07_01.csv")[4]
    opts["save_path"] *= "_L=$L"
    opts["initial_state_of_charge"] = 0.5
    opts["time_out"] = 1200
    opts["upward_reserve_levels_included_in_redispatch"] = L
    opts["downward_reserve_levels_included_in_redispatch"] = L
    opts["absolute_limit_on_nodal_imbalance"] = true
    opts["allow_absolute_imbalance_slacks"] = true
    opts["absolute_imbalance_slack_penalty"] = 1e2
    gep_UC = run_GEPPR(opts)

    opts = options_diff_days(sn, "days_for_analysis_2022_07_01.csv")[4]
    opts["save_path"] *= "_no_slack"
    opts["allow_absolute_imbalance_slacks"] = false
    gep_UC_no_sl = run_GEPPR(opts)

    opts["unit_commitment_type"] = "none"
    opts["save_path"] *= "_no_UC"
    gep_ED = run_GEPPR(opts)
    return gep_UC, gep_UC_no_sl, gep_ED
end

gep_UC, gep_UC_no_sl, gep_ED = run_debug_abs_imb_infeasible([10])
gep_UC, gep_UC_no_sl, gep_ED = run_debug_abs_imb_infeasible(1:10)
