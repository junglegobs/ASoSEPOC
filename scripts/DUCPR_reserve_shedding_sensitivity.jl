include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)

opts_vec = options_3_days(sn)
opts_vec = map(
    opts -> (opts["vars_2_save"] = [:z, :q, :ls, :rsl⁺]; opts), opts_vec
)
opts_vec = vcat(
    [
        merge(
            opts,
            Dict(
                "reserve_shedding_limit" => v,
                "save_path" => opts["save_path"] * "_RSL=$v",
                "time_out" => 600,
            ),
        ) for v in 1:-0.2:0, opts in opts_vec
    ]...,
)
gep_vec = run_GEPPR(opts_vec)
kpi_vec = key_performance_indicators.(gep_vec)
x = [kpi[:loadShedding] for kpi in kpi_vec]
y = [kpi[:reserveShedding] for kpi in kpi_vec]
