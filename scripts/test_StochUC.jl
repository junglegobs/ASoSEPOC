include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)

df = CSV.read(datadir("pro", "days_for_analysis.csv"), DataFrame)
opts = options(
    "include_storage" => false,
    "include_operating_reserves" => false,
    "operating_reserves_sizing_type" => "given",
    "operating_reserves_type" => "none",
    "initial_commitment_data_path" => datadir("sims", "rolling_UC_full_year"),
    "optimization_horizon" => [
        parse(UnitRange{Int}, df[i,"timesteps"]) for i in size(df,1)
    ]
)
opts_vec = dict_list(opts)
gep = run_GEPPR(opts_vec[1])
