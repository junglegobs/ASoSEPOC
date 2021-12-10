using DrWatson
@quickactivate
includet(srcdir("process_input.jl"))
includet(srcdir("opts.jl"))
includet(srcdir("GEPPR.jl"))

process_belderbos_data()
powermodels_2_GEPPR(grid_path, grid_red_path)
opts = options(
    "include_storage" => true,
    "include_operating_reserves" => false,
    "operating_reserves_sizing_type" => "given",
    "operating_reserves_type" => "none",
)
gep = run_GEPPR(opts)

# TODO
storage_dispatch_2_node_injection(grid_path, grid_wo_store_path)
powermodels_2_GEPPR(grid_wo_store_path, grid_wo_store_red_path)
