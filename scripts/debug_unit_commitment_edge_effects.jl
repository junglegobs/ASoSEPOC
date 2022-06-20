include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs(plotsdir(sn))
mkrootdirs(simsdir(sn))

opts = options_diff_days(sn)[1]
opts["initial_state_of_charge"] = 0.0
opts["operating_reserves_type"] = "none"
opts["time_out"] = 120
gep = run_GEPPR(opts)

z = gep[:z]