include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs(plotsdir(sn))

function res_act_net(opts)
    return (
        opts["copperplate"] == false &&
        isempty(opts["upward_reserve_levels_included_in_redispatch"]) ==
        false ||
        isempty(opts["downward_reserve_levels_included_in_redispatch"]) ==
        false
    )
end

function has_OR(gep::GEPM)
    return isnothing(gep[:I, :uncertainty]) == false
end

# Choose day 3, since this has day ahead load shedding!
opts = options_diff_days(sn, "days_for_analysis.csv")[3]
opts["initial_state_of_charge"] = 0.5
opts["time_out"] = 1800
opts_vec = [
    merge(
        opts,
        Dict(
            "operating_reserves_type" => "none",
            "unit_commitment_type" => "none",
            "copperplate" => true,
            "prevent_simultaneous_charge_and_discharge" => false,
            "save_path" => joinpath(opts["save_path"], "base"),
        ),
    ),
    merge(
        opts,
        Dict(
            "operating_reserves_type" => "none",
            "copperplate" => true,
            "prevent_simultaneous_charge_and_discharge" => false,
            "save_path" => joinpath(opts["save_path"], "base_UC=true"),
        ),
    ),
    merge(
        opts,
        Dict(
            "operating_reserves_type" => "none",
            "prevent_simultaneous_charge_and_discharge" => false,
            "save_path" =>
                joinpath(opts["save_path"], "base_UC=true_DANet=true"),
        ),
    ),
    merge(
        opts,
        Dict(
            "operating_reserves_type" => "none",
            "save_path" => joinpath(
                opts["save_path"], "base_UC=true_DANet=true_PSCD=true"
            ),
        ),
    ),
]
opts_vec = vcat(
    opts_vec...,
    [
        merge(
            opts,
            Dict(
                "operating_reserves_type" => "probabilistic",
                "reserve_shedding_limit" => v,
                "save_path" => "$(opts["save_path"])_RSV=$(v)",
            ),
        ) for opts in opts_vec, v in [0.0, 0.5, 1.0]
    ]...,
)
opts_vec = vcat(
    opts_vec...,
    [
        merge(
            opts,
            Dict(
                "upward_reserve_levels_included_in_redispatch" => 1:10,
                "downward_reserve_levels_included_in_redispatch" => 1:10,
                "save_path" => "$(opts["save_path"])_L⁺=1:10_L⁻=1:10",
            ),
        ) for opts in opts_vec if opts["reserve_shedding_limit"] <= 1.0
    ]...,
)
opts_vec = vcat(
    opts_vec...,
    [
        merge(
            opts,
            Dict(
                "absolute_limit_on_nodal_imbalance" => true,
                "save_path" => "$(opts["save_path"])_AbsIm=true",
            ),
        ) for opts in opts_vec if res_act_net(opts)
    ],
)
opts_vec = vcat(
    opts_vec...,
    [
        merge(
            opts,
            Dict(
                "load_multiplier" => 1.5,
                "save_path" => "$(opts["save_path"])_LoadMult=1.5",
            ),
        ) for opts in opts_vec if res_act_net(opts)
    ],
)

function main_model_run(opts; make_plots=false)
    gep = run_GEPPR(opts)

    dis_file = joinpath(opts["save_path"], "dispatch.png")
    res_file = joinpath(opts["save_path"], "ls_and_rs.png")
    comm_file = joinpath(opts["save_path"], "commitment.png")

    if make_plots && (any(isfile.([dis_file,res_file, comm_file]) .== false))
        # Plot dispatch
        plt = plot_dispatch(gep, 1)
        Plots.savefig(plt, dis_file)

        # If has reserves, plot these
        if opts["operating_reserves_type"] != "none"
            has_OR(gep) == false && apply_operating_reserves!(gep, opts)
            plt = plot_reserves_simple(gep, 1)
            Plots.savefig(plt, res_file)
        end

        # If has commitment variables, also plot the commitment heatmap
        if opts["unit_commitment_type"] != "none"
            plt = plot_commitment(gep, 1)
            Plots.savefig(plt, comm_file)
        end

        # Plot the reserve shedding and load shedding time series
        ls = sum(gep[:loadShedding].data; dims=(1, 2, 3))[:]
        rs = gep[:rsL⁺]
        rs = (
            if ismissing(rs)
                fill(0.0, length(ls))
            else
                sum(rs.data; dims=(1, 2, 3, 4))[:]
            end
        )
        plt = Plots.plot(
            [ls rs];
            lab=["Load shedding" "Reserve shedding"],
            ylabel="Power",
            ylims=(0, max(100, maximum(ls), maximum(rs))),
        )
        Plots.savefig(plt, res_file)
    end

    return gep
end

gep_vec = GEPM[]
idx_to_remove = Int[]
for i in eachindex(opts_vec)
    opts = opts_vec[i]
    try
        push!(gep_vec, main_model_run(opts; make_plots=true))
    catch e
        @warn "$(opts["save_path"]) failed."
        push!(idx_to_remove, i)
        println(string(e))
    end
end
opts_vec = opts_vec[setdiff(eachindex(opts_vec), idx_to_remove)]

function analyse_main_model_runs(gep_vec, opts_vec)
    df = DataFrame(
        "Name" => [basename(opts["save_path"]) for opts in opts_vec],
        "UC" => [opts["unit_commitment_type"] == "binary" for opts in opts_vec],
        "DANet" => [opts["copperplate"] == false for opts in opts_vec],
        "PSCD" => [
            opts["prevent_simultaneous_charge_and_discharge"] == true for
            opts in opts_vec
        ],
        "OR" =>
            [opts["operating_reserves_type"] != "none" for opts in opts_vec],
        "RSV" => [opts["reserve_shedding_limit"] for opts in opts_vec],
        "RANet" => [res_act_net(opts) for opts in opts_vec],
        "AbsImb" => [
            opts["absolute_limit_on_nodal_imbalance"] == true for
            opts in opts_vec
        ],
        "LM" => [opts["load_multiplier"] for opts in opts_vec],
        "Reserve Shedding" =>
            sum.([
                ismissing(gep[:rsL⁺]) ? SVC(0.0) : gep[:rsL⁺] for gep in gep_vec
            ]),
        "Load shedding" => sum.([gep[:loadShedding] for gep in gep_vec]),
        "Objective" => [gep[:objective] for gep in gep_vec],
    )
    CSV.write(joinpath(opts["save_path"], "summary.csv"), df)

    function analyse_effect_of_constraints(df, path)
        mkrootdirs(path)

        df_no_OR = filter(row -> row["OR"] == false, df)
        CSV.write(joinpath(path, "no_OR.csv"), df_no_OR)

        df_no_RANet = filter(
            row ->
                row["OR"] == true &&
                    row["RANet"] == false &&
                    row["AbsImb"] == false,
            df,
        )
        DataFrames.sort!(df_no_RANet, ["UC", "DANet", "PSCD", "RSV"])
        CSV.write(joinpath(path, "no_RANet.csv"), df_no_RANet)

        df_no_AbsImb = filter(
            row ->
                row["OR"] == true &&
                    row["RANet"] == true &&
                    row["AbsImb"] == false,
            df,
        )
        DataFrames.sort!(df_no_AbsImb, ["UC", "DANet", "PSCD", "RSV"])
        CSV.write(joinpath(path, "no_AbsImb.csv"), df_no_AbsImb)

        df_no_ConvImb = filter(
            row ->
                row["OR"] == true &&
                    row["RANet"] == true &&
                    row["AbsImb"] == true,
            df,
        )
        DataFrames.sort!(df_no_ConvImb, ["UC", "DANet", "PSCD", "RSV"])
        CSV.write(joinpath(path, "no_ConvImb.csv"), df_no_ConvImb)

        return nothing
    end

    analyse_effect_of_constraints(
        filter(row -> ismissing(row["LM"]), df),
        joinpath(opts["save_path"], "LM=1.0"),
    )
    analyse_effect_of_constraints(
        filter(row -> ismissing(row["LM"]) == false && row["LM"] == 1.5, df),
        joinpath(opts["save_path"], "LM=1.5"),
    )

    return df
end

df = analyse_main_model_runs(gep_vec, opts_vec)

# Why does reserve shedding happen?
function how_is_reserve_shed_without_increasing_load_shedding(gep_vec, opts_vec)
    # When is load and reserve shed?
    i = 7
    ls_0_5 = dropdims(
        sum(gep_vec[i + 4][:loadShedding].data; dims=(2, 3)); dims=(2, 3)
    )
    rs_0_5 = dropdims(
        sum(gep_vec[i + 4][:rsL⁺].data; dims=(2, 3, 4)); dims=(2, 3, 4)
    )
    ls_0_5_idx = findall(ls_0_5 .> 1e-3)
    rs_0_5_idx = findall(rs_0_5 .> 1e-6)

    # Load shedding occurs same time when RSL = 0 and RSL = 0.5
    ls_0 = dropdims(
        sum(gep_vec[i][:loadShedding].data; dims=(2, 3)); dims=(2, 3)
    )
    ls_0_idx = findall(ls_0_5 .> 1e-3)
    @show ls_0_idx == ls_0_5_idx

    # Plot load shedding, which occurs at hour 8
    N = GEPPR.get_set_of_nodes(gep_vec[i])
    x = eachindex(N)
    display(
        Plots.bar(
            hcat(x...),
            ls_0_5[:, 10]';
            lab="",
            ylabel="Load shedding [MWh]",
            xticks=(x, N),
            tickfontrotation=90,
            margin=10mm,
            size=(1200, 800),
        ),
    )

    # When is commitment different in both cases?
    z_0_5 = dropdims(gep_vec[i + 4][:z].data; dims=(2, 3))
    z_0 = dropdims(gep_vec[i][:z].data; dims=(2, 3))
    @show findall(z_0_5 .- z_0 .!= 0)

    # When is generation different in both cases?
    q_0_5 = dropdims(gep_vec[i + 4][:q].data; dims=(2, 3))
    q_0 = dropdims(gep_vec[i][:q].data; dims=(2, 3))
    @show q_idx = findall(abs.(q_0_5[:, 9] .- q_0[:, 9]) .> 1e-3)
    GN = GEPPR.get_set_of_nodal_generators(gep_vec[i])
    @show GN[q_idx]
end

how_is_reserve_shed_without_increasing_load_shedding(gep_vec, opts_vec)

function load_shedding_distribution(gep_vec, opts_vec, idx)
    pyplot()
    gep = gep_vec[idx]

    ls = dropdims(gep[:loadShedding].data; dims=(2, 3))
    plt = Plots.plot(
        sum(ls; dims=1)[:]; ylab="Load shedding [MWh]", xlab="Time [h]", lab=""
    )
    Plots.savefig(plt, plotsdir(sn, "ls_timeseries_idx=$(idx).png"))

    N = GEPPR.get_set_of_nodes(gep)
    x = eachindex(N)
    plt = Plots.bar(
        hcat(x...),
        sum(ls; dims=2)';
        ylab="Load shedding [MWh]",
        xticks=(x, N),
        lab="",
        tickfontrotation=90,
        bw=1.0,
        lw=0.0,
        c=:blue,
    )
    Plots.savefig(plt, plotsdir(sn, "ls_per_node_abs_idx=$(idx).png"))

    D = dropdims(GEPPR.get_demand(gep); dims=(2, 3))
    norm_ls = (sum(ls; dims=2) ./ sum(D; dims=2))'
    plt = Plots.bar(
        hcat(x...),
        norm_ls;
        ylab="Load shedding / Load [-]",
        xticks=(x, N),
        lab="",
        tickfontrotation=90,
        bw=1.0,
        lw=0.0,
        c=:blue,
    )
    x_inf = [i for i in eachindex(norm_ls[:]) if isinf(norm_ls[i])]
    Plots.scatter!(
        plt,
        x_inf,
        [0.0 for i in eachindex(x_inf)];
        markershape=:diamond,
        markercolor=:red,
        markersize=4,
        lab="Unphysical load shedding"
    )
    Plots.savefig(plt, plotsdir(sn, "ls_per_node_idx=$(idx).png"))

    return nothing
end

load_shedding_distribution(gep_vec, opts_vec, 56)

function re_run_but_without_SOC(opts_vec, idx)
    opts = copy(opts_vec[idx])
    opts["cyclic_state_of_charge_constraint"] = false
    opts["save_path"] *= "_wo_cyclic_SOC"

    return main_model_run(opts; make_plots=true)
end

re_run_but_without_SOC(opts_vec, 15)