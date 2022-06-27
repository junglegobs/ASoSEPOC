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
    sc = gep[:sc]
    sd = gep[:sd]
    if ismissing(sc) == false && ismissing(sd) == false
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
    else
        grid_store_flow = GEPPR.SVC(0.0)
    end

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
            N_HR_PER_DAY,
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
        month(DateTime(2018, 1, 1) + Day(row["days"] - 1)) for row in eachrow(df)
    ]
    df[:, "day_of_month"] = [
        day(DateTime(2018, 1, 1) + Day(row["days"] - 1)) for row in eachrow(df)
    ]
    df[:, "timesteps"] = [((i - 1) * N_HR_PER_DAY + 1):(i * N_HR_PER_DAY) for i in df[:, "days"]]
    CSV.write(datadir("pro", filename), df)
    return df[:, "days"], df[:, "timesteps"]
end

function days_to_run_models_on(opts::Dict, filename::String)
    gep = gepm(opts)
    rl = demand_net_of_total_supply(gep)
    rl = sum(collect(values(rl)))
    rl = sum(reshape(rl, 24, :), dims=1)[:]
    srt_idx = sortperm(rl)
    day_least_scarce = srt_idx[1]
    day_little_scarce = srt_idx[Int(round(quantile(1:length(srt_idx), 1/3)))]
    day_middle_scarce = srt_idx[Int(round(quantile(1:length(srt_idx), 2/3)))]
    day_scarce = srt_idx[end]
    df = DataFrame(;
        Aggregated_Residual_Load=rl[[
            day_least_scarce, day_little_scarce, day_middle_scarce, day_scarce
        ]],
        days=[
            day_least_scarce
            day_little_scarce
            day_middle_scarce
            day_scarce
        ],
    )
    df[:, "month"] = [
        month(DateTime(2018, 1, 1) + Day(row["days"] - 1)) for row in eachrow(df)
    ]
    df[:, "day_of_month"] = [
        day(DateTime(2018, 1, 1) + Day(row["days"] - 1)) for row in eachrow(df)
    ]
    df[:, "timesteps"] = [((i - 1) * N_HR_PER_DAY + 1):(i * N_HR_PER_DAY) for i in df[:, "days"]]
    CSV.write(datadir("pro", filename), df)
end

function overall_network_results(gep::GEPM)
    sc = gep[:sc]
    sd = gep[:sd]
    q = gep[:q]
    z = gep[:z]
    ls = gep[:loadShedding]
    D = GEPPR.get_demand(gep)
    N, Y, P, T = GEPPR.get_set_of_nodes_and_time_indices(gep)
    STN = GEPPR.get_set_of_nodal_storage_technologies(gep)
    GDN = GEPPR.get_set_of_nodal_dispatchable_generators(gep)
    GRN = GEPPR.get_set_of_nodal_intermittent_generators(gep)
    K = GEPPR.get_generator_installed_capacity(gep)
    AF = GEPPR.get_generator_availability_factors(gep)
    NPC = GEPPR.get_dispatchable_generator_nameplate_capacity(gep)
    MSOP = GEPPR.get_dispatchable_generator_minimum_stable_operating_point(gep)

    df = DataFrame(
        "Time" => 1:length(T),
        "Load" => [sum(D[n,y,p,t] for n in N, y in Y, p in P) for t in T] / 100,
        "RES max dispatch" => [sum(AF[gn,y,p,t] * K[gn,y] for gn in GRN, y in Y, p in P) for t in T] / 100,
        "RES curtailment" => [sum(q[gn,y,p,t] - AF[gn,y,p,t] * K[gn,y] for gn in GRN, y in Y, p in P) for t in T] / 100,
        "RES dispatch" => [sum(q[gn,y,p,t] for gn in GRN, y in Y, p in P) for t in T] / 100,
        "Thermal dispatch" => [sum(q[gn,y,p,t] for gn in GDN, y in Y, p in P) for t in T] / 100,
        "Storage dispatch (+ve = net discharge)" => [sum(sd[stn,y,p,t] - sc[stn,y,p,t] for stn in STN, y in Y, p in P) for t in T] / 100,
        "Load shedding" => [sum(ls[n,y,p,t] for n in N, y in Y, p in P) for t in T] / 100,
        "Pmin" => [sum(z[(g,n),y,p,t] * NPC[g] * MSOP[g] for (g,n) in GDN, y in Y, p in P) for t in T] / 100,
        "Pmax" => [sum(z[(g,n),y,p,t] * NPC[g] for (g,n) in GDN, y in Y, p in P) for t in T] / 100,
    )

    df[:, "Net generation (includes storage)"] = df[:, "Thermal dispatch"] .+ df[:, "Storage dispatch (+ve = net discharge)"] .+ df[:, "RES dispatch"]
    df[:, "Load - net generation - load shed"] = df[:, "Load"] .- df[:, "Net generation (includes storage)"] .- df[:, "Load shedding"]

    return df
end
