include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs.(plotsdir(sn), simsdir(sn))

opts_vec = options_diff_days(sn)
opts_vec = [
    merge(
        opts,
        Dict(
            "initial_state_of_charge" => 0.5,
            "time_out" => 600,
            "absolute_limit_on_nodal_imbalance" => true,
        ),
    ),
]
gep = run_GEPPR(opts_vec)
d_vec = [save_gep_for_security_analysis(gep, opts) for opts in opts_vec]