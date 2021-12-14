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
    "optimization_horizon" => [1, 8_760],
    "save_path" => datadir("sims", "linear_w_storage"),
)
gep = run_GEPPR(opts)

# Identify 3 days to investigate - no load shedding at all, almost load shedding and load shedding
days_to_run_models_on(gep, "days_for_analysis.csv")

# Save storage dispatch as a node injection
storage_dispatch_2_node_injection(gep, grid_path, grid_wo_store_path)
