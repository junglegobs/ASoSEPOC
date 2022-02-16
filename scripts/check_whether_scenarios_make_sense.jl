include(joinpath(@__DIR__, "..", "intro.jl"))
using LinearAlgebra
sn = script_name(@__FILE__)

function check_scenarios()
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
    gen_cap = Dict(
        "solar" => sum(K[(g, n), Y[1]] for (g, n) in GN if g == "Sun"),
        "wind" => sum(K[(g, n), Y[1]] for (g, n) in GN if occursin("Wind", g)),
    )
    months = [1, 2, 7]
    months_2_rows = [2, 1, 3]
    mkrootdirs(datadir("sims", sn))
    f = open(datadir("sims", sn, "scen_errors.dat"), "w")
    for i in 1:size(df, 1)
        month = months[i]
        row_idx = months_2_rows[i]
        day = df[i, "days"]
        print(f, "-"^80 * "\n\nDay is $day\n" * "-"^80)
        for g in ["solar", "wind"]
            print(f, "\nSource is $g\n\n")
            files_dict = Dict(g => scendir("1000SC_BELDERBOS_$(g)_$(month)"))
            scen_dict = load_scenarios(Dict(), files_dict)
            t_start, t_end = parse(UnitRange{Int}, df[row_idx, "timesteps"])
            T_day = t_start:t_end
            scens = hcat(
                [
                    [v[k] for k in sort(collect(keys(v)))] for
                    (s, v) in scen_dict[g]["total"]["scenarios"]
                ]...,
            )

            # Check that forecasts agree
            fored = scen_dict[g]["total"]["forecast"]
            forecast = [fored[k] for k in sort(collect(keys(fored)))]
            fnd = norm(forecast .- gen_res_forecast[g][T_day])
            if fnd > 1
                print(
                    f,
                    "\nScenario generated forecasts and GEPPR forecasts do not agree, norm diff is $(fnd).\n\n",
                )
            end

            scenarios_max = maximum(scens; dims=2)
            scenarios_min = minimum(scens; dims=2)
            for j in 1:length(T_day)
                # Check that upwards forecast error not greater than capacity
                up_diff =
                    gen_res_forecast[g][T_day[j]] + scenarios_max[j] -
                    gen_cap[g]
                if up_diff > 0
                    print(
                        f,
                        "Upwards forecast error is greater than installed capacity by $up_diff for timestep $j.\n",
                    )
                end

                down_diff = gen_res_forecast[g][T_day[j]] + scenarios_min[j]
                if down_diff < 0
                    print(
                        f,
                        "Downwards forecast error is greater than the forecast by $down_diff for timestep $j.\n",
                    )
                end
            end
        end
    end
    close(f)
    return nothing
end

check_scenarios()
