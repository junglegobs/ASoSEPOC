include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs.(plotsdir(sn), simsdir(sn))

opts_vec = options_diff_days(sn)
opts_vec = [
    merge(
        opts,
        Dict(
            "time_out" => 1200,
            "initial_state_of_charge" => 0.5,
            "upward_reserve_levels_included_in_redispatch" => 1:10,
            "downward_reserve_levels_included_in_redispatch" => 1:10,
        ),
    ) for opts in opts_vec
]
opts_vec = [
    merge(
        opts,
        Dict(
            "absolute_limit_on_nodal_imbalance" => false,
            "save_path" => opts["save_path"] * "_AbsIm=false",
        ),
    ),
    merge(
        opts,
        Dict(
            "absolute_limit_on_nodal_imbalance" => true,
            "save_path" => opts["save_path"] * "_AbsIm=true",
        ),
    ) for opts in opts_vec
]
gep = run_GEPPR(opts_vec)
d_vec = [save_gep_for_security_analysis(gep, opts) for opts in opts_vec]