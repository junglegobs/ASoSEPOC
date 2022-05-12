include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs(plotsdir(sn))
rm(simsdir(sn); force=true, recursive=true)

opts = options_diff_days(sn)[4]
rm(opts["save_path"]; force=true, recursive=true)
# opts["unit_commitment_type"] = "none"
opts["initial_state_of_charge"] = 0.0
opts["absolute_limits_on_nodal_imbalance"] = true
# opts["prevent_simultaneous_charge_and_discharge"] = false
opts["upward_reserve_levels_included_in_redispatch"] = 1:10
opts["downward_reserve_levels_included_in_redispatch"] = 1:10

RSL_vec = [1.0, 0.5, 0.0]
opts_vec = [
    merge(
        opts,
        Dict(
            "reserve_shedding_limit" => v,
            "save_path" => opts["save_path"] * "_RSL=_$v",
        ),
    ) for v in RSL_vec
]

gep = run_GEPPR(opts_vec[1])

gep_vec = run_GEPPR(opts_vec)

df = DataFrame(
    "Reserve shedding limit" => RSL_vec,
    "Reserve Shedding" => sum.([gep[:rsL⁺] for gep in gep_vec]),
    "Load shedding" => sum.([gep[:loadShedding] for gep in gep_vec]),
)
