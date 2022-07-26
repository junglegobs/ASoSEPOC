include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs(plotsdir(sn))

function compare_reliability_DUCPR_and_PF()
    function plot_vecs(x1, x2; kwargs...)
        return Plots.plot(
            0.5:23.5,
            hcat(x1, x2);
            lab=["Unit commitment" "Security analysis"],
            # bar_position=:mid,
            # bar_width=1.0,
            # linewidth=0.0,
            # alpha=0.5,
            line=:stepmid,
            # linestyle=:auto,
            linewidth=3.0,
            xlims=(0, 24),
            kwargs...
        )
    end

    df_pf = CSV.read(
        datadir(
            "raw", "SoS_results_2022_07_22", "corrective_load_shedding_all.csv"
        ),
        DataFrame,
    )

    d_uc = JSON.parsefile(
        simsdir(
            "interaction_check", "309", "security_analysis_2022_6_26_15:58.json"
        ),
    )
    gep = load_GEP(simsdir("interaction_check", "309"))
    N, Y, P, T = GEPPR.get_set_of_nodes_and_time_indices(gep)
    rsL⁺ = gep[:rsL⁺]

    # Forecast
    ls_pf_fc =
        [
            sum(row[4:(46 + 3)]) for
            row in eachrow(df_pf) if occursin("FC", row["Scenario"])
        ] * 100
    ls_uc_fc = [
        sum(vals["value"] for (n, vals) in v["load_shed"]) for
        (k, v) in collect(sort(d_uc))
    ]
    p1 = plot_vecs(
        ls_uc_fc,
        ls_pf_fc,
        ;
        title="Forecasted load shedding",
        ylab="Load shedding [MWh]",
        xlab="Time [h]",
    )

    # Aggregated
    ls_pf_scen = reshape(
        [
            sum(row[4:(46 + 3)]) for
            row in eachrow(df_pf) if occursin("FC", row["Scenario"]) == false
        ],
        24,
        :,
    )
    ls_pf_scen = sum(ls_pf_scen; dims=2)[:] / size(ls_pf_scen, 2) * 100 # base unit is 100 MVA
    ls_uc_scen = ls_uc_fc .+ sum(rsL⁺.data; dims=(1, 2, 3, 4))[:]
    
    p2 = plot_vecs(
        ls_uc_scen,
        ls_pf_scen;
        title="Scenario based load shedding",
        ylab="Expected shedding [MWh]",
        xlab="Time [h]",
    )

    return p1, p2
end

p1, p2 = compare_reliability_DUCPR_and_PF()