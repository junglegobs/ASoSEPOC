include(joinpath(@__DIR__, "..", "intro.jl"))
using LinearAlgebra

gep = gepm(options())
df = CSV.read(datadir("pro", "days_for_analysis.csv"), DataFrame)
GN = GEPPR.get_set_of_nodal_intermittent_generators(gep)
AF = GEPPR.get_generator_availability_factors(gep)
N, Y, P, T = GEPPR.get_set_of_nodes_and_time_indices(gep)
T = 1:8_760
K = GEPPR.get_generator_installed_capacity(gep)
gen_res_forecast = Dict(
    "solar" => [
        sum(
            AF[(g, n), Y[1], P[1], t] * K[(g, n), Y[1]] for
            (g, n) in GN if g == "Sun"
        ) for t in T
    ],
    "wind" => [
        sum(
            AF[(g, n), Y[1], P[1], t] * K[(g, n), Y[1]] for
            (g, n) in GN if occursin("Wind", g)
        ) for t in T
    ],
)
months = [1, 2, 7]
months_2_rows = [2, 1, 3]
for i in 1:size(df, 1)
    month = months[i]
    row_idx = months_2_rows[i]
    for g in ["solar", "wind"]
        files_dict = Dict(
            g => datadir(
                "raw",
                "Forecast_Error_Scenarios",
                "1000SC_BELDERBOS_$(g)_$(month)_01-20-2022",
            ),
        )
        scen_dict = load_scenarios(Dict(), files_dict)
        t_start, t_end = parse(UnitRange{Int}, df[row_idx, "timesteps"])
        T_day = t_start:t_end
        scens = hcat(
            [
                [
                    v[k] for k in sort(collect(keys(v)))
                ]
                for (s, v) in scen_dict[g]["total"]["scenarios"]
            ]...
        )
        fored = scen_dict[g]["total"]["forecast"]
        forecast = [fored[k] for k in sort(collect(keys(fored)))]
        fnd = norm(forecast, gen_res_forecast[g][T_day])
        if fnd > 1
            @warn "Scenario generated forecasts and GEPPR forecasts do not agree, norm diff is $(fnd)."
        end
        for i in 1:length(T_day)
            # TODO: check maximum downwards reserves requested over all of Belgium
            # scenarios_max = maximum(scens)
            # min_scenario = Inf
            # min_scenario_GEPPR = Inf
            # for (k, v) in scen_dict[g]
            # end
        end
    end
end
