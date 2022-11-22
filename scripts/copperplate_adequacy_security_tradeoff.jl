include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs(plotsdir(sn))

opts = options_diff_days(sn, "days_for_analysis.csv")[2]
opts = merge(
    opts,
    Dict(
        "copperplate" => true,
        "unit_commitment" => false,
        # "downward_reserve_levels_included_in_redispatch" => 1:10,
        # "upward_reserve_levels_included_in_redispatch" => 1:10,
        "include_storage" => false,
        "vars_2_save" => [:z, :q, :ls, :rL⁺, :rL⁻, :rsL⁺, :rsL⁻],
    ),
)
opts_vec = [
    merge(
        opts,
        Dict(
            "reserve_shedding_limit" => rsl,
            "save_path" => opts["save_path"] * "_RSL=$rsl",
        ),
    ) for rsl in 1.0:-0.5:0.0
]
gep_vec = run_GEPPR(opts_vec)
rsl_vec = [opts_vec[i]["reserve_shedding_limit"] for i in 1:length(opts_vec)]

function plot_DUCPR_reserve_shedding_sensitivity(
    gep_vec, opts_vec, rsl_vec, days=["161"]
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
    Plots.savefig(
        plotsdir(sn, "reserve_shedding_vs_reserve_shedding_limit.png")
    )

    return nothing
end
