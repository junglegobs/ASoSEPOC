include(joinpath(@__DIR__, "..", "intro.jl"))

files_dict = Dict(
    "Load" => datadir(
        "raw",
        "Forecast_Error_Scenarios",
        "1000SC_BELDERBOS_load_1_01-20-2022",
    ),
    "Solar" => datadir(
        "raw",
        "Forecast_Error_Scenarios",
        "1000SC_BELDERBOS_solar_1_01-20-2022",
    ),
    "Wind" => datadir(
        "raw",
        "Forecast_Error_Scenarios",
        "1000SC_BELDERBOS_wind_1_01-20-2022",
    ),
)
scen_dict = load_scenarios(Dict(), files_dict)
