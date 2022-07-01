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
            "absolute_limit_on_nodal_imbalance" => false,
            "save_path" => opts["save_path"] * "_AbsIm=false"
        ),
    ),
    merge(
        opts,
        Dict(
            "initial_state_of_charge" => 0.5,
            "time_out" => 600,
            "absolute_limit_on_nodal_imbalance" => true,
            "save_path" => opts["save_path"] * "_AbsIm=true"
        ),
    )
    for opts in opts_vec
]
gep = run_GEPPR(opts_vec)
d_vec = [save_gep_for_security_analysis(gep, opts) for opts in opts_vec]