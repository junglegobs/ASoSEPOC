include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs(plotsdir(sn))

function res_act_net(opts)
    return opts["reserve_shedding_limit"] <= 1.0 && (
        isempty(opts["upward_reserve_levels_included_in_redispatch"]) ==
        false ||
        isempty(opts["downward_reserve_levels_included_in_redispatch"]) ==
        false
    )
end

opts = options_diff_days(sn)[4]
opts["initial_state_of_charge"] = 0.0
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
        ) for opts in opts_vec if opts["reserve_shedding_limit"] < 1.0
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

function main_model_run(opts; make_plots=true)
    gep = run_GEPPR(opts)

    if make_plots
        # Plot dispatch
        plt = plot_dispatch(gep, 1)
        Plots.savefig(plt, joinpath(opts["save_path"], "dispatch.png"))

        # If has reserves, plot these
        if opts["operating_reserves_type"] != "none"
            apply_operating_reserves!(gep, opts)
            plt = plot_reserves_simple(gep, 1)
            Plots.savefig(plt, joinpath(opts["save_path"], "reserves.png"))
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
            ylims=(0, max(100, maximum(ls))),
        )
        Plots.savefig(plt, joinpath(opts["save_path"], "ls_and_rs.png"))
    end

    return gep
end

gep_vec = GEPM[]
for opts in opts_vec
    try
        push!(gep_vec, main_model_run(opts; make_plots=false))
    catch e
        @warn "$(opts["save_path"]) failed."
        println(string(e))
    end
end

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

        df_no_RANet = filter(row -> row["OR"] == true && row["RANet"] == false && row["AbsImb"] == false, df)
        DataFrames.sort!(df_no_RANet, ["UC", "DANet", "PSCD"])
        CSV.write(joinpath(path, "no_RANet.csv"), df_no_RANet)

        df_no_AbsImb = filter(row -> row["OR"] == true && row["RANet"] == true && row["AbsImb"] == false, df)
        DataFrames.sort!(df_no_AbsImb, ["UC", "DANet", "PSCD"])
        CSV.write(joinpath(path, "no_AbsImb.csv"), df_no_AbsImb)

        df_no_ConvImb = filter(row -> row["OR"] == true && row["RANet"] == true && row["AbsImb"] == true, df)
        DataFrames.sort!(df_no_AbsImb, ["UC", "DANet", "PSCD"])
        CSV.write(joinpath(path, "no_ConvImb.csv"), df_no_ConvImb)

        return nothing
    end

    analyse_effect_of_constraints(filter(row -> ismissing(row["LM"]), df), joinpath(opts["save_path"], "LM=1.0"))
    analyse_effect_of_constraints(filter(row -> ismissing(row["LM"]) == 1.5, df), joinpath(opts["save_path"], "LM=1.5"))

    return df
end

df = analyse_main_model_runs(gep_vec, opts_vec)
