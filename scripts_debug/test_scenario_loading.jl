include(joinpath(@__DIR__, "..", "intro.jl"))

files_dict = Dict(
    "Load" => "1000SC_BELDERBOS_load_5_17",
    "Solar" =>"1000SC_BELDERBOS_solar_5_17",
    "Wind" => "1000SC_BELDERBOS_wind_5_17",
)
scen_dict = load_scenarios(Dict(), files_dict)
