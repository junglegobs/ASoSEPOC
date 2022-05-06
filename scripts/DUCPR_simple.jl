include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs(plotsdir(sn))

opts_vec = options_diff_days(sn)
init_soc = 0.0
opts_vec = vcat(
    [
        merge(
            opts,
            Dict(
                "time_out" => 600,
                "save_path" => joinpath(
                    opts["save_path"], "RSL=$(v)_init_SOC=$(init_soc)"
                ),
                "reserve_shedding_limit" => v,
                "initial_state_of_charge" => init_soc,
            ),
        ) for opts in opts_vec, v in [1.0, 0.0]
    ]...,
)
gep_vec = run_GEPPR(opts_vec)
GC.gc() # Who knows, maybe this will help
map(
    i -> if gep_vec[i] === nothing
        nothing
    else
        save_gep_for_security_analysis(gep_vec[i], opts_vec[i])
    end,
    eachindex(opts_vec),
)

nd = length(options_diff_days(sn))
sid_vec = [month_day(opts_vec[i]) for i in 1:length(opts_vec)]
rsl_vec = [opts_vec[i]["reserve_shedding_limit"] for i in 1:length(opts_vec)]
rsl_mat = reshape(rsl_vec, nd, 2)
ls = Dict(
    (sid_vec[i], rsl_vec[i]) => try
        sum(gep_vec[i][:loadShedding].data; dims=(1, 2, 3))[:]
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
            rsLt[(sid_vec[i], rsl_vec[i])][n, l, 1, 1, t]
            # rsLt[(sid_vec[i], rsl_vec[i])][n, l, 1, 1, t] *
            # P⁺[(sid_vec[i], rsl_vec[i])][l, 1, 1, t] 
            for n in GEPPR.get_set_of_nodes(gep_vec[i]),
            l in GEPPR.get_set_of_upward_reserve_levels(gep_vec[i]),
            t in GEPPR.get_set_of_time_indices(gep_vec[i])[3]
        )
    catch
        NaN
    end for i in 1:length(opts_vec)
)
ls_mat = reshape(
    [sum(ls[sid_vec[i], rsl_vec[i]]) for i in 1:length(opts_vec)], nd, 2
)
rs_mat = reshape(
    [rsL⁺[sid_vec[i], rsl_vec[i]] for i in 1:length(opts_vec)], nd, 2
)

Plots.plot(
    rsl_mat',
    ls_mat';
    lab=["214" "210" "136" "309"],
    xlab="Reserve shedding limit [0 - 1]",
    ylab="Day ahead load shedding [MWh]",
)

plot_dispatch(gep_vec[1], 1)
