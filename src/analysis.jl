using GEPPR, CSV

function demand_net_of_total_supply(gep::GEPM)
    N, Y, P, T = GEPPR.get_set_of_nodes_and_time_indices(gep)

    # Generation
    GN = GEPPR.get_set_of_nodal_generators(gep)
    AF = GEPPR.get_generator_availability_factors(gep)
    K = GEPPR.get_generator_installed_capacity(gep)
    gen_flow = Dict(
        n1 => [
            reduce(
                +,
                AF[(g, n1), Y[1], P[1], t] * K[(g, n1), Y[1]] for
                (g, n2) in GN if n2 == n1;
                init=0.0,
            ) for t in T
        ] for n1 in N
    )

    # Store flows
    STN = GEPPR.get_set_of_nodal_storage_technologies(gep)
    ST = GEPPR.get_set_of_storage_technologies(gep)
    sc = gep[:sc]
    sd = gep[:sd]
    grid_store_flow = Dict(
        n1 => [
            reduce(
                +,
                sd[(st, n2), Y[1], P[1], t] - sc[(st, n2), Y[1], P[1], t]
                for (st, n2) in STN if n2 == n1;
                init=0.0,
            ) for t in T
        ] for n1 in N
    )

    # Demand
    D = GEPPR.get_demand(gep)
    dem_flow = Dict(n => [D[n, Y[1], P[1], t] for t in T] for n in N)

    # Net
    return Dict(
        n => dem_flow[n] .- grid_store_flow[n] .- gen_flow[n] for n in N
    )
end

function days_to_run_models_on(gep::GEPM, filename::String)
    dem_net = demand_net_of_total_supply(gep)
    dem_net_sum = [sum(v[i] for (k, v) in dem_net) for i in 1:8_760]
    dem_net_day = reshape(dem_net_sum, 24, :)
    dem_net_max_day = maximum(dem_net_day; dims=1)
    day_no_scarce = findmin(dem_net_max_day)[2][2]
    day_some_scarce = findfirst(dem_net_max_day .> -1000)[2]
    day_scarce = findmax(dem_net_max_day)[2][2]
    df = DataFrame(;
        type=["No scarcity", "Scarcity in redispatch", "Scarcity in day ahead"],
        days=[
            day_no_scarce
            day_some_scarce
            day_scarce
        ]
    )
    df[:,"timesteps"] = [
        (i - 1) * 24 + 1:i * 24 for i in df[:,"days"]
    ]
    CSV.write(datadir("pro", filename), df)
    return day_no_scarce, day_some_scarce, day_scarce
end
