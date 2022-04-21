include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs(simsdir(sn))

# Linear, no reserves, no network - simplest case
opts_vec = options_3_days(sn)
map(opts -> rm(opts["save_path"]; force=true, recursive=true), opts_vec)
opts_vec = [
    merge(
        opts,
        Dict(
            "unit_commitment_type" => "none",
            "operating_reserves_type" => "none",
            "copperplate" => true,
        ),
    ) for opts in opts_vec
]
gep_vec = run_GEPPR(opts_vec)
Plots.savefig(
    plot_dispatch(gep_vec[2], 1), simsdir(sn, "day_5_lin_no_reserve_no_net.png")
)

# Linear, no reserves, with network
opts_vec = options_3_days(sn)
map(opts -> rm(opts["save_path"]; force=true, recursive=true), opts_vec)
opts_vec = [
    merge(
        opts,
        Dict(
            "unit_commitment_type" => "none",
            "operating_reserves_type" => "none",
        ),
    ) for opts in opts_vec
]
gep_vec = run_GEPPR(opts_vec)
Plots.savefig(
    plot_dispatch(gep_vec[2], 1), simsdir(sn, "day_5_lin_no_reserve.png")
)

# Linear, no reserves, with network AND STORAGE
opts_vec = options_3_days(sn)
map(opts -> rm(opts["save_path"]; force=true, recursive=true), opts_vec)
opts_vec = [
    merge(
        opts,
        Dict(
            "unit_commitment_type" => "none",
            "operating_reserves_type" => "none",
            "include_storage" => true,
        ),
    ) for opts in opts_vec
]
gep_vec = run_GEPPR(opts_vec)
Plots.savefig(
    plot_dispatch(gep_vec[2], 1), simsdir(sn, "day_5_lin_no_reserve_w_storage.png")
)
# It seems I made a mistake when choosing days - even in this case I have load shedding...

# No network, no UC, no network redispatch - simplest case with reserves
opts_vec = options_3_days(sn)
map(opts -> rm(opts["save_path"]; force=true, recursive=true), opts_vec)
opts_vec = [
    merge(
        opts,
        Dict(
            "reserve_shedding_limit" => 0.0,
            "unit_commitment_type" => "none",
            "copperplate" => true,
        ),
    ) for opts in opts_vec
]
gep_vec = run_GEPPR(opts_vec)
plot_dispatch(gep_vec[2], 1)
Plots.savefig(plot_dispatch(gep_vec[2], 1), simsdir(sn, "day_5_lin_no_net.png"))
Plots.savefig(
    plot_reserves_simple(gep_vec[2], 1),
    simsdir(sn, "day_5_lin_no_net_reserve_provision.png"),
)
# Day 41 is still broken!!! Hmmmm...

# No UC
opts_vec = options_3_days(sn)
map(opts -> rm(opts["save_path"]; force=true, recursive=true), opts_vec)
opts_vec = [
    merge(
        opts,
        Dict("reserve_shedding_limit" => 0.0, "unit_commitment_type" => "none"),
    ) for opts in opts_vec
]
gep_vec = run_GEPPR(opts_vec)
plot_dispatch(gep_vec[2], 1)
Plots.savefig(plot_dispatch(gep_vec[2], 1), simsdir(sn, "day_5_lin.png"))
Plots.savefig(
    plot_reserves_simple(gep_vec[2], 1),
    simsdir(sn, "day_5_lin_reserve_provision.png"),
)

# Full model
opts_vec = options_3_days(sn)
map(opts -> rm(opts["save_path"]; force=true, recursive=true), opts_vec)
opts_vec = [
    merge(
        opts,
        Dict("reserve_shedding_limit" => 0.0, "unit_commitment_type" => "none"),
    ) for opts in opts_vec
]
gep_vec = run_GEPPR(opts_vec)
plot_dispatch(gep_vec[2], 1)
Plots.savefig(plot_dispatch(gep_vec[2], 1), simsdir(sn, "day_5_uc_all.png"))
Plots.savefig(
    plot_reserves_simple(gep_vec[2], 1),
    simsdir(sn, "day_5_uc_all_reserve_provision.png"),
)