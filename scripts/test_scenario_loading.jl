include(joinpath(@__DIR__, "..", "intro.jl"))

files_dict = Dict(
    "Load" => scendir("1000SC_BELDERBOS_load_1"),
    "Solar" => scendir("1000SC_BELDERBOS_solar_1"),
    "Wind" => scendir("1000SC_BELDERBOS_wind_1"),
)
scen_dict = load_scenarios(Dict(), files_dict)
