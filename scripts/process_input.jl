using DrWatson, Revise
@quickactivate
includet(srcdir("process_input.jl"))
includet(srcdir("opts.jl"))
includet(srcdir("GEPPR.jl"))
includet(srcdir("analysis.jl"))

# Process Excel sheets into a PowerModels.json format
process_belderbos_data(grid_path)

# Process PowerModels into GEPPR format
powermodels_2_GEPPR(grid_path, grid_red_path)

# Run a linear operational model
opts = options(
    "include_storage" => true,
    "include_operating_reserves" => false,
    "unit_commitment_type" => "none",
    "operating_reserves_sizing_type" => "given",
    "operating_reserves_type" => "none",
    "optimization_horizon" => [1, 8_760]
)
gep = run_GEPPR(opts)
save_optimisation_values!(gep) # In case not saved due to TimeOut limit
save(gep, datadir("sims", "linear_w_storage"))

# Identify 3 days to investigate - no load shedding at all, almost load shedding and load shedding
day_no_scarce, day_some_scarce, day_scarce = days_to_run_models_on(gep)

# Save storage dispatch as a node injection
storage_dispatch_2_node_injection(gep, grid_path, grid_wo_store_path)

# Re_process data to be used with GEPPR
powermodels_2_GEPPR(grid_wo_store_path, grid_wo_store_red_path)
