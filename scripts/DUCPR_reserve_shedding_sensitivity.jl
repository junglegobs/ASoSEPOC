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
            "save_path" => joinpath(opts["save_path"], "RSL=$(v)"),
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

function plot_DUCPR_reserve_shedding_sensitivity(
    gep_vec, opts_vec, rsl_vec, days=["309"]
)
    ls = Dict(
        rsl_vec[i] => try
            sum(gep_vec[i][:loadShedding].data; dims=(1, 2, 3))[:]
        catch
            GEPPR.SVC(NaN)
        end for i in 1:length(opts_vec)
    )
    rsLt = Dict(rsl_vec[i] => try
        gep_vec[i][:rsL⁺]
    catch
        GEPPR.SVC(NaN)
    end for i in 1:length(opts_vec))
    rsL⁺ = Dict(
        rsl_vec[i] => try
            sum(
                rsLt[(rsl_vec[i])][n, l, 1, 1, t]
                # rsLt[(rsl_vec[i])][n, l, 1, 1, t] *
                # P⁺[(rsl_vec[i])][l, 1, 1, t] 
                for n in GEPPR.get_set_of_nodes(gep_vec[i]),
                l in GEPPR.get_set_of_upward_reserve_levels(gep_vec[i]),
                t in GEPPR.get_set_of_time_indices(gep_vec[i])[3]
            )
        catch
            NaN
        end for i in 1:length(opts_vec)
    )
    nd = length(days)
    ls_mat = Matrix(
        transpose(
            reshape([sum(ls[rsl_vec[i]]) for i in 1:length(opts_vec)], nd, :)
        ),
    )
    rs_mat = Matrix(
        transpose(
            reshape([rsL⁺[rsl_vec[i]] for i in 1:length(opts_vec)], nd, :)
        ),
    )
    Plots.plot(
        ls_mat,
        rs_mat;
        lw=2,
        markerzise=16,
        markershape=:star5,
        xlab="Day ahead load shedding [MWh]",
        ylab="Reserve shedding [MWh]",
        lab=hcat(days...),
    )
    Plots.savefig(plotsdir(sn, "load_shedding_vs_reserve_shedding.png"))

    rsl_mat = Matrix(transpose(reshape(rsl_vec, nd, :)))
    Plots.plot(
        rsl_mat,
        ls_mat;
        lw=2,
        markersize=6,
        markerwidth=0,
        markershape=:star5,
        xlab="Reserve shedding limit [0-1]",
        ylab="Load shedding [MWh]",
        lab=hcat(days...),
    )
    Plots.savefig(plotsdir(sn, "load_shedding_vs_reserve_shedding_limit.png"))

    Plots.plot(
        rsl_mat,
        rs_mat;
        lw=2,
        markersize=6,
        markerwidth=0,
        markershape=:star5,
        xlab="Reserve shedding limit [0-1]",
        ylab="Reserve shedding [MWh]",
        lab=hcat(days...),
    )
    return Plots.savefig(
        plotsdir(sn, "reserve_shedding_vs_reserve_shedding_limit.png")
    )
end

plot_DUCPR_reserve_shedding_sensitivity(gep_vec, opts_vec, rsl_vec)
