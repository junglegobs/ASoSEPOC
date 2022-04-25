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
    mkrootdirs(datadir("sims", sn))
    f = open(datadir("sims", sn, "scen_errors_$(round(now(), Dates.Minute)).dat"), "w")
    for i in 1:size(df, 1)
        mth = df[i, "month"]
        dy = df[i, "day_of_month"]
        d = df[i, "days"]
        print(f, "-"^80 * "\n\nDay is $d\n" * "-"^80)
        for g in ["solar", "wind"]
            print(f, "\nSource is $g\n\n")
            files_dict = Dict(g => "$(g)_$(mth)_$(dy)")
            scen_dict = load_scenarios(Dict(), files_dict)
            t_start, t_end = parse(UnitRange{Int}, df[i, "timesteps"])
            T_day = t_start:t_end
            scens = hcat(
                [
                    [v[k] for k in sort(collect(keys(v)))] for
                    (s, v) in scen_dict[g]["total"]["scenarios"]
                ]...,
            )
            scens_summed = Dict(
                node => scen_dict[g][node]["scenarios"] for
                node in keys(scen_dict[g]) if node ∉ ("total",)
            )
            for (node, node_vals) in scens_summed
                for (scen, scen_vals) in node_vals
                    scens_summed[node][scen] = [
                        scen_vals[i] for i in sort(collect(keys(scen_vals)))
                    ]
                end
            end
            scen_set = 1:size(scens, 2)
            scens_summed = hcat(
                [
                    sum(node_vals[i] for (node, node_vals) in scens_summed)
                    for i in scen_set
                ]...
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

                # If forecasts don't agree, find the one which does
                test_bool = false
                for T_test in [(1 + (i - 1) * 24):(i * 24) for i in 1:365]
                    fnd_test = norm(forecast .- gen_res_forecast[g][T_test])
                    if fnd_test < 1
                        print(
                            f,
                            "\nScenario generated forecasts match GEPPR forecasts for T=$(T_test).\n\n",
                        )
                        test_bool = true
                        break
                    end
                end
                if test_bool == false
                    print(
                        f,
                        "\nScenario generated forecasts do not match any of the GEPPR forecasts.\n\n",
                    )
                end
            end

            # scenarios_max = maximum(scens; dims=2)
            # scenarios_min = minimum(scens; dims=2)
            # Even though these "total forecast error" scenarios are different
            # The result is the same...
            scenarios_max = maximum(scens_summed; dims=2)
            scenarios_min = minimum(scens_summed; dims=2)
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

# NOTE: Sometimes you get Infs in the CSV files, watch out for this!    

function fix_scenarios(; verbose=false)
    gep = gepm(options())
    df = CSV.read(datadir("pro", "days_for_analysis.csv"), DataFrame)
    GN = GEPPR.get_set_of_nodal_intermittent_generators(gep)
    AF = GEPPR.get_generator_availability_factors(gep)
    N, Y, P, T = GEPPR.get_set_of_nodes_and_time_indices(gep)
    T = 1:8_760
    K = GEPPR.get_generator_installed_capacity(gep)
    gen_res_forecast = Dict(
        "solar" => Dict(
            n => [
                AF[(g, n), Y[1], P[1], t] * K[(g, n), Y[1]]
                for t in T
            ]
            for (g, n) in GN if g == "Sun"
        ),
        "wind" => Dict(
            n => [
                AF[(g, n), Y[1], P[1], t] * K[(g, n), Y[1]]
                for t in T
            ]
            for (g, n) in GN if occursin("Wind", g)
        ),
    )
    gen_cap = merge(
        Dict(("solar", n) => K[(g, n), Y[1]] for (g, n) in GN if g == "Sun"),
        Dict(("wind", n) => K[(g, n), Y[1]] for (g, n) in GN if occursin("Wind", g))
    )
    f_list = readdir(scendir())

    for i in 1:size(df, 1) # Days
        mth = df[i, "month"]
        dy = df[i, "day_of_month"]
        d = df[i, "days"]
        t_start, t_end = parse(UnitRange{Int}, df[i, "timesteps"])
        T_day = t_start:t_end
        for g in ["solar", "wind"]
            file_prefix = "1000SC_BELDERBOS_$(g)_$(mth)_$(dy)"
            idx = findfirst(f -> occursin(file_prefix, f), f_list)
            file_scen = joinpath(scendir(), f_list[idx])
            df_scen = CSV.read(file_scen, DataFrame; skipto=4, header=2)
            for name in N
                if name ∉ names(df_scen)
                    # @info "Skipping $(name) for source $g"
                    continue
                end
                for s in 1:1000 # Hardcoded!
                    Ts = (s-1)*24+1:s*24
                    scen_vals = df_scen[Ts,name]
                    for j in eachindex(scen_vals)
                        up_diff =
                        gen_res_forecast[g][name][T_day[j]] + scen_vals[j] -
                        gen_cap[g,name]
                        if up_diff > 0
                            verbose && @info "Updiff error for source $g, node $name, scenario $s, timestep $j."
                            scen_vals[j] = 
                            gen_cap[g,name] - gen_res_forecast[g][name][T_day[j]]
                        end
                        down_diff = gen_res_forecast[g][name][T_day[j]] + scen_vals[j]
                        if down_diff < 0
                            verbose && @info "Downdiff error for source $g, node $name, scenario $s, timestep $j."
                            scen_vals[j] = -gen_res_forecast[g][name][T_day[j]]
                        end

                        if isnan(scen_vals[j]) || isinf(scen_vals[j])
                            scen_vals[j] = 0.0
                        end
                    end
                    df_scen[Ts,name] = scen_vals
                end
            end

            # Write the changes to the file
            @info "Overwriting $file_scen..."
            df_scen_all = CSV.read(file_scen, DataFrame; stringtype=String)
            df_scen_all[3:end,4:end] = string.(Matrix(df_scen[:,4:end]))
            CSV.write(file_scen, df_scen_all)
        end
    end
end

fix_scenarios()

# Unsure why some scenarios still lead to impossible RES generation...

check_scenarios()
