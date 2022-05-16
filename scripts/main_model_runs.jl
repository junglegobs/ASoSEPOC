include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs(plotsdir(sn))
rm(simsdir(sn); force=true, recursive=true)

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
            "save_path" =>
                joinpath(opts["save_path"], "base_UC=true_DANet=true_PSCD=true"),
        ),
    ),
]

function main_model_run(opts; make_plots=true)
    gep = run_GEPPR(opts)

    if make_plots
        # Plot dispatch
        plt = plot_dispatch(gep, 1)
        Plots.savefig(plt, joinpath(opts["save_path"], "dispatch.png"))

        # If has reserves, plot these
        if opts["operating_reserves_type"] != "none"
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
        push!(gep_vec, main_model_run(opts))
    catch
        @warn "$(opts["save_path"]) failed."
    end
end

function analyse_main_model_runs(gep_vec)
    df = DataFrame(
        "Name" => [basename(opts["save_path"]) for opts in opts_vec],
        "Reserve Shedding" =>
            sum.([
                ismissing(gep[:rsL⁺]) ? SVC(0.0) : gep[:rsL⁺] for gep in gep_vec
            ]),
        "Load shedding" => sum.([gep[:loadShedding] for gep in gep_vec]),
        "Objective" => [gep[:objective] for gep in gep_vec],
    )
    CSV.write(joinpath(opts["save_path"], "summary.csv"), df)
    return df
end

df = analyse_main_model_runs(gep_vec)
