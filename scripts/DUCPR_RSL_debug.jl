include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs(plotsdir(sn))

opts = options_diff_days(sn)[4]
rm(opts["save_path"]; force=true, recursive=true)
opts["initial_state_of_charge"] = 0.0
opts["absolute_limits_on_nodal_imbalance"] = true
# opts["upward_reserve_levels_included_in_redispatch"] = 1:10
# opts["downward_reserve_levels_included_in_redispatch"] = 1:10

opts_vec = [
    merge(
        opts,
        Dict(
            "reserve_shedding_limit" => v,
            "save_path" => opts["save_path"] * "_RSL=_$v",
        ),
    ) for v in [1.0, 0.5, 0.0]
]

gep = run_GEPPR(opts_vec)

df = DataFrame(
    "Limits" => ["Absolute", "None"],
    "Reserve Shedding" => sum.([gep[:rsL⁺] for gep in gep_vec]),
    "Load shedding" => sum.([gep[:loadShedding] for gep in gep_vec]),
)
