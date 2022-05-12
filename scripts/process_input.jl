include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs(datadir("sims", sn))

# Process Excel sheets into a PowerModels.json format
process_belderbos_data(grid_path)

# Process PowerModels into GEPPR format
powermodels_2_GEPPR(grid_path, grid_red_path)

# Run a linear operational model for the entire year
opts = options(
    "include_storage" => true,
    "unit_commitment_type" => "none",
    "operating_reserves_sizing_type" => "given",
    "operating_reserves_type" => "none",
    "prevent_simultaneous_charge_and_discharge" => false,
    "optimization_horizon" => [1, 8_760],
    "save_path" => datadir("sims", "linear_w_storage"),
)
gep = run_GEPPR(opts)

# Identify 4 days to investigate - no load shedding at all, almost load shedding and load shedding
# Because I realised there were mistakes in the model later on, I save this to a "days_for_analysis_new.csv" instead of "days_for_analysis.csv", so that I don't have to recreate all the scenarios.
days, TVec = days_to_run_models_on(gep, "days_for_analysis_new.csv")# Run a linear operational model for the entire year
opts = options(
    "include_storage" => true,
    "unit_commitment_type" => "none",
    "operating_reserves_sizing_type" => "given",
    "operating_reserves_type" => "none",
    "prevent_simultaneous_charge_and_discharge" => false,
    "optimization_horizon" => [1, 8_760],
    "save_path" => datadir("sims", "linear_w_storage"),
)
gep = run_GEPPR(opts)


# Check the dispatch at the network level for each case
for T in TVec
    Plots.savefig(
        plot_dispatch(gep, 1; T=T, plot_state_of_charge=false),
        simsdir(sn, "dispatch_T=$T.png"),
    )
end

# Plot daily load shedding for entire year
ls = sum(
    reshape(
        dropdims(sum(gep[:loadShedding].data; dims=(1, 2, 3)); dims=(1, 2, 3)),
        24,
        :,
    );
    dims=1,
)[:]
Plots.plot(ls; xlab="Day", ylab="Load shedding [MW]", lab="")
Plots.savefig(simsdir(sn, "load_shedding_daily_timeseries.png"))
Plots.plot(sort(ls; rev=true); xlab="Day", ylab="Load shedding [MW]", lab="")
Plots.savefig(simsdir(sn, "load_shedding_daily_timeseries_sorted.png"))

# Save storage dispatch as a node injection
storage_dispatch_2_node_injection(
    gep, grid_path, grid_w_store_ts_path, grid_wo_store_path
)

# Check that dispatches make sense
opts["save_path"] = ""
opts["optimization_horizon"] = [1, 48]
opts["include_storage"] = true
gep = run_GEPPR(opts)
plt_1 = plot_dispatch(gep, 1; T=1:48, N=["RODENHUIZE"])
Plots.savefig(plt_1, datadir("sims", sn, "dispatch_with_storage.pdf"))

opts["include_storage"] = false
gep = run_GEPPR(opts)
plt_2 = plot_dispatch(gep, 1; T=1:48, N=["RODENHUIZE"])
Plots.savefig(plt_2, datadir("sims", sn, "dispatch_without_storage.pdf"))
