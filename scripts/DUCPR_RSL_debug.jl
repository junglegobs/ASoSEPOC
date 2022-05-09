include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs(plotsdir(sn))

opts = options_diff_days(sn)[4]
opts["initial_state_of_charge"] = 0.0
opts_vec = [
    merge(
        opts,
        Dict(
            "unit_commitment_type" => "none",
            "include_storage" => false,
            "save_path" => joinpath(opts["save_path"], "simplest"),
        ),
    )
    merge(
        opts,
        Dict(
            "unit_commitment_type" => "none",
            "save_path" => joinpath(opts["save_path"], "simpler"),
        ),
    )
    merge(
        opts,
        Dict(
            "unit_commitment_type" => "none",
            "save_path" => joinpath(opts["save_path"], "full"),
        ),
    )
]
gep_vec = run_GEPPR(opts_vec[1:2])
