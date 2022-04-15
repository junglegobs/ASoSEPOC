include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)

opts_vec = options_3_days(sn)
opts_vec = map(
    opts -> (opts["vars_2_save"] = [:z, :q, :ls, :rsL⁺]; opts), opts_vec
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
sid_vec = [scenario_id(opts_vec[i]) for i in 1:length(opts_vec)]
rsl_vec = [opts_vec[i]["reserve_shedding_limit"] for i in 1:length(opts_vec)]
ls = Dict(
    (sid_vec[i], rsl_vec[i]) => sum(gep_vec[i][:ls].data; dims=(1, 2, 3))[:] for
    i in 1:length(opts_vec)
)
P⁺ = Dict(
    (sid_vec[i], rsl_vec[i]) => gep_vec[i][:I, :uncertainty, :P⁺] for
    i in 1:length(opts_vec)
)
rsLt = Dict(
    (sid_vec[i], rsl_vec[i]) => gep_vec[i][:rsL⁺] for i in 1:length(opts_vec)
)
rsL⁺ = Dict(
    (sid_vec[i], rsl_vec[i]) => sum(
        rsLt[(sid_vec[i], rsl_vec[i])][n, l, 1, 1, t] *
        P⁺[(sid_vec[i], rsl_vec[i])][l, 1, 1, t] for
        n in GEPPR.get_set_of_nodes(gep_vec[i]),
        l in GEPPR.get_set_of_upward_reserve_levels(gep_vec[i]),
        t in GEPPR.get_set_of_time_indices(gep_vec[i])[3]
    ) for i in 1:length(opts_vec)
)
x = reshape([sum(ls[sid_vec[i],rsl_vec[i]]) for i in 1:length(opts_vec)], 6, 3)
y = reshape([rsL⁺[sid_vec[i],rsl_vec[i]] for i in 1:length(opts_vec)], 6, 3)
Plots.plot(
    x,
    y;
    xlab="Day ahead load shedding [MWh]",
    ylab="Reserve shedding [MWh]",
    lab=["208" "5" "41"],
)
