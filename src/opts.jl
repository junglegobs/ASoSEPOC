
"""
    options(pairs)

Create a dictionary which specifies simulation parameters.
"""
function options(pairs...)
    opts = Dict(
        "include_storage" => false,
        "unit_commitment_type" => "binary",
        "operating_reserves_sizing_type" => "given",
        "operating_reserves_type" => "none",
        "initial_commitment_data_path" => "",
        "optimization_horizon" => [1,48],
        "rolling_horizon" => false,
        "upward_reserve_levels" => 10,
        "downward_reserve_levels" => 10,
        "include_downward_reserves" => true
    )
    for (k,v) in pairs
        opts[k] = v
    end
    return opts
end

function options_3_days(sn)
    df = CSV.read(datadir("pro", "days_for_analysis.csv"), DataFrame)
    opts = options(
    "include_storage" => false,
    "include_operating_reserves" => false,
    "operating_reserves_sizing_type" => "given",
    "operating_reserves_type" => "none",
    "initial_commitment_data_path" => datadir("sims", "rolling_UC_full_year"),
    "operating_reserves_type" => "probabilistic",
    "operating_reserves_sizing_type" => "given",
    "vars_2_save" => [:z, :q],
    )
    scen_ids = [7,1,2]
    opts_vec = [
        merge(
            opts,
            Dict(
                "optimization_horizon" => parse(UnitRange{Int}, df[i, "timesteps"]),
                "save_path" => datadir("sims", "$(sn)_$(df[i,"days"])"),
                "load_scenario_data_paths" =>
                    scendir.("1000SC_BELDERBOS_load_$(scen_ids[i])_01-20-2022",),
                "solar_scenario_data_paths" =>
                    scendir.("1000SC_BELDERBOS_solar_$(scen_ids[i])_01-20-2022"),
                "wind_scenario_data_paths" =>
                    scendir.("1000SC_BELDERBOS_wind_$(scen_ids[i])_01-20-2022"),
            ),
        ) for i in 1:size(df, 1)
    ]
    return opts_vec
end
