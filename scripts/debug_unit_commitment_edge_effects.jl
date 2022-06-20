include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs(plotsdir(sn))
mkrootdirs(simsdir(sn))

opts = options_diff_days(sn)[1]
opts["initial_state_of_charge"] = 0.0
opts["operating_reserves_type"] = "none"
opts["time_out"] = 120
opts["save_path"] *= "_no_reserves"
gep = run_GEPPR(opts)

opts["operating_reserves_type"] = "probabilistic"
gep = run_GEPPR(opts)