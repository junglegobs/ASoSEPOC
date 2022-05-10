include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs(plotsdir(sn))
mkrootdirs(simsdir(sn))

opts = options_diff_days(sn)[1]
opts["initial_state_of_charge"] = 0.0
# opts["operating_reserves_type"] = "none"
opts["time_out"] = 120
gep = run_GEPPR(opts)
d = save_gep_for_security_analysis(gep, opts)

df = overall_network_results(gep)
df[:,"Load - net generation - load shed"]
CSV.write(joinpath(opts["save_path"], "aggregate_results.csv"), df)
