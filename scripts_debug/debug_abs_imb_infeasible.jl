include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs(plotsdir(sn))

opts = options_diff_days(sn, "days_for_analysis_2022_07_01.csv")[4]
opts["initial_state_of_charge"] = 0.5
opts["time_out"] = 600
opts["absolute_limit_on_nodal_imbalance"] = true
opts["allow_absolute_imbalance_slacks"] = true
opts["absolute_imbalance_slack_penalty"] = 1e2
gep_UC = run_GEPPR(opts)

opts["unit_commitment_type"] = "none"
opts["save_path"] *= "_no_UC"
gep_ED = run_GEPPR(opts)

