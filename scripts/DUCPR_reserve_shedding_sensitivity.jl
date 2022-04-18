include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)

opts_vec = options_3_days(sn)
opts_vec = map(opts -> (opts["vars_2_save"] = [:z, :q, :ls, :rsL⁺];
opts["exprs_2_save"] = [:loadShedding];
opts), opts_vec)
opts_vec = vcat(
    [
        merge(
            opts,
            Dict(
                "reserve_shedding_limit" => v,
                "save_path" => opts["save_path"] * "_RSL=$v",
                "time_out" => 600,
            ),
        ) for v in 1:-0.1:0, opts in opts_vec
    ]...,
)
gep_vec = run_GEPPR(opts_vec)
GC.gc() # Who knows, maybe this will help
map(
    i ->
        if gep_vec[i] === nothing
            nothing
        else
            save_gep_for_security_analysis(gep_vec[i], opts_vec[i])
        end,
    eachindex(opts_vec),
)

# Plot
for i in 1:length(opts_vec)
    gep_vec[i] == nothing && continue
    apply_operating_reserves!(gep_vec[i], opts_vec[i])
end
sid_vec = [scenario_id(opts_vec[i]) for i in 1:length(opts_vec)]
rsl_vec = [opts_vec[i]["reserve_shedding_limit"] for i in 1:length(opts_vec)]
ls = Dict(
    (sid_vec[i], rsl_vec[i]) => try
        sum(gep_vec[i][:loadShedding].data; dims=(1, 2, 3))[:]
    catch
        GEPPR.SVC(NaN)
    end for i in 1:length(opts_vec)
)
P⁺ = Dict(
    (sid_vec[i], rsl_vec[i]) => try
        gep_vec[i][:I, :uncertainty, :P⁺]
    catch
        GEPPR.SVC(NaN)
    end for i in 1:length(opts_vec)
)
rsLt = Dict(
    (sid_vec[i], rsl_vec[i]) => try
        gep_vec[i][:rsL⁺]
    catch
        GEPPR.SVC(NaN)
    end for i in 1:length(opts_vec)
)
rsL⁺ = Dict(
    (sid_vec[i], rsl_vec[i]) => try
        sum(
            rsLt[(sid_vec[i], rsl_vec[i])][n, l, 1, 1, t] *
            P⁺[(sid_vec[i], rsl_vec[i])][l, 1, 1, t] for
            n in GEPPR.get_set_of_nodes(gep_vec[i]),
            l in GEPPR.get_set_of_upward_reserve_levels(gep_vec[i]),
            t in GEPPR.get_set_of_time_indices(gep_vec[i])[3]
        )
    catch
        NaN
    end for i in 1:length(opts_vec)
)
x = reshape([sum(ls[sid_vec[i], rsl_vec[i]]) for i in 1:length(opts_vec)], :, 3)
y = reshape([rsL⁺[sid_vec[i], rsl_vec[i]] for i in 1:length(opts_vec)], :, 3)
Plots.plot(
    x,
    y;
    lw=2,
    markershape=:star5,
    xlab="Day ahead load shedding [MWh]",
    ylab="Reserve shedding [MWh]",
    lab=["208" "5" "41"],
)
