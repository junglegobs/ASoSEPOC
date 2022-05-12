
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
        "optimization_horizon" => [1, 48],
        "rolling_horizon" => false,
        "upward_reserve_levels" => 10,
        "upward_reserve_levels_included_in_redispatch" => [],
        "downward_reserve_levels" => 10,
        "downward_reserve_levels_included_in_redispatch" => [],
        "include_downward_reserves" => true,
        "reserve_shedding_limit" => 1.0,
        "copperplate" => false,
        "vars_2_save" => Symbol[],
        "exprs_2_save" => Symbol[],
        "initial_state_of_charge" => missing,
        "replace_storage_dispatch_with_node_injection" => false,
        "reserve_provision_cost" => 0.0,
        "absolute_limit_on_nodal_imbalance_" => false,
        "convex_hull_limit__on_nodal_imbalance" => false,
    )
    for (k, v) in pairs
        opts[k] = v
    end
    return opts
end

function options_diff_days(sn)
    df = CSV.read(datadir("pro", "days_for_analysis.csv"), DataFrame)
    opts = options(
        "include_storage" => true,
        "operating_reserves_sizing_type" => "given",
        "operating_reserves_type" => "none",
        # "initial_commitment_data_path" => datadir("sims", "rolling_UC_full_year"),
        "operating_reserves_type" => "probabilistic",
        "operating_reserves_sizing_type" => "given",
        "vars_2_save" => [:z, :q, :ls, :rL⁺, :rL⁻, :rsL⁺, :rsL⁻, :e, :sc, :sd],
        "exprs_2_save" => [:loadShedding],
        "time_out" => 60*10
    )
    opts_vec = [
        merge(
            opts,
            Dict(
                "optimization_horizon" =>
                    parse(UnitRange{Int}, df[i, "timesteps"]),
                "save_path" => datadir("sims", "$(sn)", "$(df[i,"days"])"),
                "load_scenario_data_paths" => "1000SC_BELDERBOS_load_$(df[i,"month"])_$(df[i,"day_of_month"])",
                "solar_scenario_data_paths" => "1000SC_BELDERBOS_solar_$(df[i,"month"])_$(df[i,"day_of_month"])",
                "wind_scenario_data_paths" => "1000SC_BELDERBOS_wind_$(df[i,"month"])_$(df[i,"day_of_month"])",
            ),
        ) for i in 1:size(df, 1)
    ]
    return opts_vec
end
