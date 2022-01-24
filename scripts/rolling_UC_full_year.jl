include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)

df = CSV.read(datadir("pro", "days_for_analysis.csv"), DataFrame)
opts = options(
    "include_storage" => false,
    "include_operating_reserves" => false,
    "operating_reserves_sizing_type" => "given",
    "operating_reserves_type" => "none",
    "optimization_horizon" => 1:8760,
    "save_path" => datadir("sims", sn),
)
gep = run_GEPPR(opts)
