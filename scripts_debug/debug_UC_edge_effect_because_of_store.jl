include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs.(plotsdir(sn), simsdir(sn))

opts = options_diff_days(sn, "days_for_analysis_2022_06_21.csv")[4]
opts["initial_state_of_charge"] = 0.0
opts["time_out"] = 600
opts["save_path"] *= "SOC_init=0.0"
gep = run_GEPPR(opts)
d = save_gep_for_security_analysis(gep, opts)

opts = options_diff_days(sn, "days_for_analysis_2022_06_21.csv")[4]
opts["initial_state_of_charge"] = 0.5
opts["time_out"] = 600
opts["save_path"] *= "SOC_init=0.5"
gep = run_GEPPR(opts)
d = save_gep_for_security_analysis(gep, opts)