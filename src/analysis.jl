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
    ls = sum(
        reshape(
            dropdims(
                sum(gep[:loadShedding].data; dims=(1, 2, 3)); dims=(1, 2, 3)
            ),
            24,
            :,
        );
        dims=1,
    )[:]
    srt_idx = sortperm(ls)
    day_no_scarce = srt_idx[1]
    day_little_scarce = srt_idx[findfirst(ls[srt_idx] .> 1e-3)]
    day_middle_scarce = srt_idx[findfirst(ls[srt_idx] .> 1_000)]
    day_scarce = srt_idx[findfirst(ls[srt_idx] .> 10_000)]
    df = DataFrame(;
        DA_load_shedding=ls[[
            day_no_scarce, day_little_scarce, day_middle_scarce, day_scarce
        ]],
        days=[
            day_no_scarce
            day_little_scarce
            day_middle_scarce
            day_scarce
        ],
    )
    df[:, "month"] = [
        month(DateTime(2018, 1, 1) + Day(row["days"])) for row in eachrow(df)
    ]
    df[:, "day_of_month"] = [
        day(DateTime(2018, 1, 1) + Day(row["days"])) for row in eachrow(df)
    ]
    df[:, "timesteps"] = [((i - 1) * 24 + 1):(i * 24) for i in df[:, "days"]]
    CSV.write(datadir("pro", filename), df)
    return df[:, "days"], df[:, "timesteps"]
end
