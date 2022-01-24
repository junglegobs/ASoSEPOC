includet(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)

opts = options(
    "include_storage" => false,
    "include_operating_reserves" => false,
    "operating_reserves_sizing_type" => "given",
    "operating_reserves_type" => "none",
    "optimization_horizon" => [1,8760],
    "rolling_horizon" => true,
    "save_path" => datadir("sims", sn),
    "vars_2_save" => [:z],
)
gep = run_GEPPR(opts)
