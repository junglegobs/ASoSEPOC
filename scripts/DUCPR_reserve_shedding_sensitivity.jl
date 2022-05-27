include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs(plotsdir(sn))

opts = options_diff_days(sn)[4]
opts = merge(
    opts,
    Dict(
        "time_out" => 600,
        "upward_reserve_levels_included_in_redispatch" => 1:10,
        "downward_reserve_levels_included_in_redispatch" => 1:10,
        "initial_state_of_charge" => 0.5,
        "load_multiplier" => 1.5,
        "absolute_limit_on_nodal_imbalance" => true,
    ),
)
opts_vec = vcat([
    merge(
        opts,
        Dict(
            "reserve_shedding_limit" => v,
            "save_path" => joinpath(opts["save_path"], "RSL=$(v)_L=$L"),
        ),
    ) for v in 1.0:-0.1:0
])
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

rsl_vec = [opts_vec[i]["reserve_shedding_limit"] for i in 1:length(opts_vec)]

function plot_DUCPR_reserve_shedding_sensitivity(gep_vec, opts_vec, rsl_vec)
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
    nd = length(options_diff_days(sn))
    ls_mat = reshape(
        [sum(ls[sid_vec[i], rsl_vec[i]]) for i in 1:length(opts_vec)], nd, 2, :
    )
    rs_mat = reshape(
        [rsL⁺[sid_vec[i], rsl_vec[i]] for i in 1:length(opts_vec)], nd, 2, :
    )
    Plots.plot(
        ls_mat[:, 1, :]',
        rs_mat[:, 1, :]';
        lw=2,
        markerzise=20,
        markershape=:star5,
        xlab="Day ahead load shedding [MWh]",
        ylab="Reserve shedding [MWh]",
        lab=["214" "210" "136" "309"],
    )
    Plots.savefig(plotsdir(sn, "load_shedding_vs_reserve_shedding.png"))

    rsl_mat = reshape(rsl_vec, nd, 2, :)
    Plots.plot(
        rsl_mat[:, 1, :]',
        ls_mat[:, 1, :]';
        lw=2,
        markersize=10,
        markerwidth=0,
        markershape=:star5,
        xlab="Reserve shedding limit [0-1]",
        ylab="Load shedding [MWh]",
        lab=["214" "210" "136" "309"],
    )
    Plots.savefig(plotsdir(sn, "load_shedding_vs_reserve_shedding_limit.png"))

    Plots.plot(
        rsl_mat[:, 1, :]',
        rs_mat[:, 1, :]';
        lw=2,
        markersize=10,
        markerwidth=0,
        markershape=:star5,
        xlab="Reserve shedding limit [0-1]",
        ylab="Reserve shedding [MWh]",
        lab=["214" "210" "136" "309"],
    )
    return Plots.savefig(
        plotsdir(sn, "reserve_shedding_vs_reserve_shedding_limit.png")
    )
end

plot_DUCPR_reserve_shedding_sensitivity(gep_vec, opts_vec, rsl_vec)
