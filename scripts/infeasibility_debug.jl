include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs(simsdir(sn))

# Linear, no reserves, no network - simplest case
opts_vec = options_diff_days(sn)
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
gep = run_GEPPR(opts_vec[1])
plot_dispatch(gep, 1)
gep_vec = run_GEPPR(opts_vec)
plot_dispatch(gep_vec[4], 1)
Plots.savefig(
    plot_dispatch(gep_vec[4], 1),
    simsdir(sn, "day_309_lin_no_reserve_no_net.png"),
)

# Linear, no reserves, with network
opts_vec = options_diff_days(sn)
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
gep = run_GEPPR(opts_vec[1])
plot_dispatch(gep, 1)
gep_vec = run_GEPPR(opts_vec)
Plots.savefig(
    plot_dispatch(gep_vec[4], 1), simsdir(sn, "day_309_lin_no_reserve.png")
)

# No network, no UC, no network redispatch - simplest case with reserves
opts_vec = options_diff_days(sn)
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
plot_dispatch(gep_vec[4], 1)
Plots.savefig(
    plot_dispatch(gep_vec[4], 1), simsdir(sn, "day_309_lin_no_net.png")
)
Plots.savefig(
    plot_reserves_simple(gep_vec[4], 1),
    simsdir(sn, "day_309_lin_no_net_reserve_provision.png"),
)

# No UC
opts_vec = options_diff_days(sn)
map(opts -> rm(opts["save_path"]; force=true, recursive=true), opts_vec)
opts_vec = [
    merge(
        opts,
        Dict("reserve_shedding_limit" => 0.0, "unit_commitment_type" => "none"),
    ) for opts in opts_vec
]
gep_vec = run_GEPPR(opts_vec)
plot_dispatch(gep_vec[4], 1)
Plots.savefig(plot_dispatch(gep_vec[4], 1), simsdir(sn, "day_309_lin.png"))
Plots.savefig(
    plot_reserves_simple(gep_vec[4], 1),
    simsdir(sn, "day_309_lin_reserve_provision.png"),
)

# No UC, Including network redispatch
opts_vec = options_diff_days(sn)
map(opts -> rm(opts["save_path"]; force=true, recursive=true), opts_vec)
opts_vec = [
    merge(
        opts,
        Dict(
            "reserve_shedding_limit" => 0.0,
            "unit_commitment_type" => "none",
            "upward_reserve_levels_included_in_redispatch" => 1:10,
            "downward_reserve_levels_included_in_redispatch" => 1:10,
        ),
    ) for opts in opts_vec
]
gep_vec = run_GEPPR(opts_vec)
plot_dispatch(gep_vec[4], 1)
Plots.savefig(plot_dispatch(gep_vec[4], 1), simsdir(sn, "day_309_no_uc_all.png"))
Plots.savefig(
    plot_reserves_simple(gep_vec[4], 1),
    simsdir(sn, "day_309_no_uc_all_reserve_provision.png"),
)

# Full model without network redispatch
opts_vec = options_diff_days(  sn)
map(opts -> rm(opts["save_path"]; force=true, recursive=true), opts_vec)
opts_vec = [
    merge(
        opts,
        Dict(
            "reserve_shedding_limit" => 0.0,
        ),
    ) for opts in opts_vec
]
gep = run_GEPPR(opts_vec[1])
gep_vec = run_GEPPR(opts_vec)
plot_dispatch(gep_vec[4], 1)
Plots.savefig(plot_dispatch(gep_vec[4], 1), simsdir(sn, "day_309_uc_all.png"))
Plots.savefig(
    plot_reserves_simple(gep_vec[4], 1),
    simsdir(sn, "day_309_uc_all_reserve_provision.png"),
)

# Full model
opts_vec = options_diff_days(sn)
map(opts -> rm(opts["save_path"]; force=true, recursive=true), opts_vec)
opts_vec = [
    merge(
        opts,
        Dict(
            "reserve_shedding_limit" => 0.1,
            "upward_reserve_levels_included_in_redispatch" => [10],
            # "upward_reserve_levels_included_in_redispatch" => 1:10,
            "downward_reserve_levels_included_in_redispatch" => [10],
            # "downward_reserve_levels_included_in_redispatch" => 1:10,
        ),
    ) for opts in opts_vec
]
gep = run_GEPPR(opts_vec[1])
plot_dispatch(gep, 1)
gep_vec = run_GEPPR(opts_vec)
plot_dispatch(gep_vec[4], 1)
Plots.savefig(plot_dispatch(gep_vec[4], 1), simsdir(sn, "day_309_uc_all.png"))
Plots.savefig(
    plot_reserves_simple(gep_vec[4], 1),
    simsdir(sn, "day_309_uc_all_reserve_provision.png"),
)

map(opts -> rm(opts["save_path"]; force=true, recursive=true), opts_vec)
