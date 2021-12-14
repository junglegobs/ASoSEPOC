using XLSX, PowerModels, JSON, YAML, StatsBase, DataFrames, CSV, GEPPR
include(srcdir("util.jl"))
nT = 8_760 # Number of timesteps

function process_belderbos_data(grid_path)
    grid_data_dir = datadir("raw", "Belderbos_Belgian_Model")
    network = Dict{String,Any}(
        "name" => "Belderbos Belgium Model",
        "baseMVA" => 1,
        "source_type" => "matpower", # TODO
        "source_version" => "2", # TODO
        "bus" => Dict{String,Any}(),
        "branch" => Dict{String,Any}(),
        "load" => Dict{String,Any}(),
        "gen" => Dict{String,Any}(),
        "res" => Dict{String,Any}(),
        "storage" => Dict{String,Any}(),
        "shunt" => Dict{String,Any}(),
        "switch" => Dict{String,Any}(),
        "dcline" => Dict{String,Any}(),
        "time_elapsed" => 1.0, # hours per timestep
    )
    grid = XLSX.readxlsx(joinpath(grid_data_dir, "BE-full2015_grid.xlsx"))
    load_cols, load_labs = XLSX.readtable(
        joinpath(grid_data_dir, "BE-full2015_load.xlsx"), "load"
    )
    gen = XLSX.readxlsx(joinpath(grid_data_dir, "BE-full2015_portfolio.xlsx"))
    ts = XLSX.readxlsx(joinpath(grid_data_dir, "BE-full2015_transactions.xlsx"))
    prices = XLSX.readxlsx(joinpath(grid_data_dir, "BE-full2015_prices.xlsx"))

    # Buses
    node_sh = grid["node_information"]
    for row in XLSX.eachrow(node_sh)
        bus_id = row["A"]
        if ismissing(bus_id) == false && bus_id isa Number
            bus_type = (bus_id == 1 ? 3 : 2) # TODO
            network["bus"]["$bus_id"] = Dict(
                "index" => bus_id,
                "string" => "$bus_id",
                "number" => bus_id,
                "bus_i" => "$bus_id",
                "source_id" => ["bus", bus_id],
                "zone" => 1,
                "area" => 1,
                "bus_type" => bus_type,
                "vmin" => 0.9,
                "vmax" => 1.1,
                "va" => 0.0,
                "vm" => 0.0,
                "base_kv" => 380.0, # TODO, assumed since not given
            )
        end
    end

    # Shunts
    # TODO don't know what this is and how to do it, so making it up 
    # based on case30.m
    # network["shunt"] = Dict(
    #     "1" => Dict(
    #         "source_id" => ["bus", 1],
    #         "shunt_bus" => 10,
    #         "status"    => 1,
    #         "gs"        => 0.0,
    #         "bs"        => 0.19,
    #         "index"     => 1,
    #     )
    # )

    # Lines
    line_sh = grid["line_information"]
    for row in XLSX.eachrow(line_sh)
        line_id = row["A"]
        if ismissing(line_id) == false && line_id isa Integer
            network["branch"]["$line_id"] = Dict(
                "name" => "line_$line_id",
                "number_id" => line_id,
                "index" => line_id,
                "f_bus" => row["C"],
                "t_bus" => row["D"],
                "rate_a" => row["F"], # TODO - this is the line capacity right?
                "br_r" => 0.0,
                "br_x" => row["E"], # TODO - assumed
                "br_status" => 1, # = in service
                "angmin" => -60.0, # TODO
                "angmax" => 60.0, # TODO
                "transformer" => false,
                "tap" => 1.0,
                "shift" => 0.0,
            )
        end
    end

    # Load
    for i in 1:length(load_cols)
        load_labs[i] == Symbol("Demand  [MW]") && continue
        bus = string(load_labs[i])
        bus_id = parse(Int, split(bus, "_")[end])
        load_vec = Float64.(load_cols[i])
        network["load"]["$bus_id"] = Dict(
            "status" => 1,
            "source_id" => ["bus", bus_id],
            "load_bus" => bus_id,
            "pd" => load_vec,
            "pq" => fill(0.0, length(load_vec)),
            "index" => 1,
        )
    end

    # Generation
    pp_sh = gen["power_plant"]
    gen_catg_sh = gen["category"]
    for row in XLSX.eachrow(pp_sh)
        gen_id = row["A"]
        (ismissing(gen_id) || (gen_id isa Int) == false) && continue
        catg = row["C"]
        catg_row = gen_catg_sh["A$catg:X$catg"]
        fuel = catg_row[5]
        fuel_cost = prices["fuel_prices"][4, fuel + 1]
        cost = fuel / catg_row[3] # Euros/MWh
        network["gen"]["$gen_id"] = Dict(
            "name" => row["B"],
            "gen_bus" => row["D"],
            "source_id" => ["gen", row["D"]], # second element is bus,
            "index" => gen_id,
            "pmax" => row["E"],
            "pmin" => row["E"] * row["G"] / 100,
            "qmin" => 0.0, # TODO ???
            "qmax" => 0.0, # TODO ???
            "startup" => row["P"], # In kEur per start
            "shutdown" => 0.0,
            "gen_status" => 1,
            "cost" => cost, #  Euros / MWh
            "ncost" => 1,
            "min_up" => catg_row[12], # TODO not part of PowerModels format
            "min_down" => catg_row[11], # TODO not part of PowerModels format
            "qg" => 0.0,
            "vg" => 0.0, # TODO not sure what this is
        )
    end

    # Renewables
    res_sh_dict = Dict(
        res_name => ts[res_name] for
        res_name in ["Sun", "Wind onshore", "Wind offshore"]
    )
    n_nodes = length(network["bus"])
    id = 1
    for (res_name, res_sh) in res_sh_dict
        for col in (1:n_nodes) .+ 5
            node = res_sh[1, col]
            ismissing(node) && continue
            res_id = string(id)
            id += 1
            af = Float64[]
            for row in XLSX.eachrow(res_sh)
                ismissing(row["A"]) && continue
                push!(af, row[col])
            end
            cap = res_sh[2, col] * res_sh["D3"]
            af ./= max(cap, 1)
            @assert all(af .<= 1.0) "AF_max = $(maximum(af)) for $(col) and $(res_name)."
            network["res"][res_id] = Dict(
                "af" => af,
                "name" => res_name,
                "id" => id,
                "bus" => node,
                "cap" => cap,
            )
        end
    end

    # Storage
    stor_sh = gen["storage_unit"]
    id = 0
    for row in XLSX.eachrow(stor_sh)
        row["A"] in ("ID", "(integer)") && continue
        id += 1
        network["storage"][string(id)] = Dict(
            "index" => id,
            "storage_bus" => row["C"],
            "ps" => 0.0,
            "qs" => 0.0,
            "energy" => 0.0,
            "energy_rating" => row["F"],
            "charge_rating" => row["D"],
            "discharge_rating" => row["E"],
            "charge_efficiency" => row["H"] / 100,
            "discharge_efficiency" => row["I"] / 100,
            "qmin" => 0.0,
            "qmax" => 0.0,
            "r" => 0.0,
            "x" => 0.0,
            "p_loss" => 0.0,
            "q_loss" => 0.0,
            "status" => 1,
            "name" => row["B"] * string(id),
        )
    end

    # Power to Gas        v["af"] = 0.0

    h2_sh = gen["hydrogen_storage"]
    for row in XLSX.eachrow(h2_sh)
        row["A"] in ("ID", "(integer)") && continue
        id += 1
        network["storage"][string(id)] = Dict(
            "index" => id,
            "storage_bus" => row["C"],
            "ps" => 0.0,
            "qs" => 0.0,
            "energy" => 0.0,
            "energy_rating" => row["D"],
            "charge_rating" => row["D"] / 1000,
            "discharge_rating" => row["D"] / 1000,
            "charge_efficiency" => 0.7,
            "discharge_efficiency" => 0.7,
            "qmin" => 0.0,
            "qmax" => 0.0,
            "r" => 0.0,
            "x" => 0.0,
            "p_loss" => 0.0,
            "q_loss" => 0.0,
            "status" => 1,
            "name" => "P2G_$(id)",
        )
    end

    # Save the dictionary
    exp_pro = datadir("pro")
    open(joinpath(exp_pro, grid_path), "w") do f
        JSON.print(f, network, 4)
    end

    return network
end

function powermodels_2_GEPPR(grid_data_path, grid_red_path)
    # Make GEPPR dir
    GEPPR_dir = datadir("pro", "GEPPR")
    mkrootdirs(GEPPR_dir)

    # Parse network
    network = parse_file(grid_data_path)

    # Conventional generatios
    gen = network["gen"]
    d = Dict(
        "dispatchableGeneration" => Dict(
            v["name"] => Dict(
                "nameplateCapacity" => v["pmax"], # [MW]
                "installedCapacity" => v["pmax"], # [MW]
                "minimumStableOperatingPoint" => v["pmin"] / v["pmax"], # [-]
                "commitmentCost" => v["cost"] * v["pmin"], # [€/commit]
                # = Cost when running at MSOP
                "startUpCost" => v["startup"], # [€/startup]
                "shutDownCost" => v["shutdown"], # [€/shutdown]
                "marginalGenerationCost" => v["cost"], # [€/MWh]
                "averageGenerationCost" => v["cost"], # [€/MWh]
                "nodes" => [string(v["gen_bus"])],
                "fuelType" => "Dummy",
            ) for (k, v) in gen
        ),
    )
    YAML.write_file(joinpath(GEPPR_dir, "units.yaml"), d)

    # Renewable generation
    res = network["res"]
    res_names = unique([v["name"] for (k, v) in res])
    nodes = Dict(
        t => [string(v["bus"]) for (k, v) in res if v["name"] == t] for
        t in res_names
    )
    cap = Dict(
        t => Dict(
            string(v["bus"]) => v["cap"] for (k, v) in res if v["name"] == t
        ) for t in res_names
    )
    d = Dict(
        "intermittentGeneration" => Dict(
            t => Dict(
                "nodes" => nodes[t],
                "availabilityFactor" => t, # [-]
                "installedCapacity" =>
                    Dict(string(k) => Float64(v) for (k, v) in cap[t]), # [MW]
                "averageGenerationCost" => 0.0,
            ) for t in res_names
        ),
    )
    YAML.write_file(joinpath(GEPPR_dir, "RES.yaml"), d)

    # Storage
    if isempty(network["storage"]) == false
        d = Dict(
            "storageTechnologies" => Dict(
                v["name"] => Dict(
                    "installedEnergyCapacity" => v["energy_rating"],
                    "roundTripEfficiency" =>
                        v["charge_efficiency"] * v["discharge_efficiency"],
                    "marginalCost" => 0.0,
                    "energyToPowerRatio" =>
                        v["energy_rating"] / mean([
                            v["charge_rating"], v["discharge_rating"]
                        ]),
                    "nodes" => [string(v["storage_bus"])],
                ) for (k, v) in network["storage"]
            ),
        )
        YAML.write_file(joinpath(GEPPR_dir, "storage.yaml"), d)
    end

    # Time series
    nodes = sort([v["string"] for (k, v) in network["bus"]])
    d = Dict(string(v["load_bus"]) => v["pd"] for (k, v) in network["load"])
    af = Dict(
        (string(v["bus"]), v["name"]) => Float64.(v["af"]) for
        (k, v) in network["res"]
    )
    df = DataFrame(
        "Timestep" => repeat(1:nT; outer=length(nodes)),
        "Node" => repeat(nodes; inner=nT),
        "Load" => vcat([d[n] for n in nodes]...),
        [
            t => vcat(
                [
                    haskey(af, (n, t)) ? af[n, t] : [0.0 for i in 1:nT] for
                    n in nodes
                ]...,
            ) for t in res_names
        ]...,
    )
    name = if isempty(network["storage"])
        "timeseries_wo_storage.csv"
    else
        "timeseries.csv"
    end
    CSV.write(joinpath(GEPPR_dir, name), df)

    # Reduced network file to avoid memory issues
    grid_red = copy(network)
    for (k, v) in grid_red["load"]
        v["pd"] = 0.0
    end
    for (k, v) in grid_red["res"]
        v["af"] = 0.0
    end

    # Save the reduced network
    open(grid_red_path, "w") do f
        JSON.print(f, grid_red, 4)
    end

    return nothing
end

function storage_dispatch_2_node_injection(
    gep::GEPM, grid_orig_path::AbstractString, grid_mod_path::AbstractString
)
    network = parse_file(grid_orig_path)

    # Remove storage
    network["storage"] = Dict{String,Any}()

    # Get sum of storage charge and discharge on each node
    N, Y, P, T = GEPPR.get_set_of_nodes_and_time_indices(gep)
    STN = GEPPR.get_set_of_nodal_storage_technologies(gep)
    ST = GEPPR.get_set_of_storage_technologies(gep)
    sc = gep[:sc]
    sd = gep[:sd]
    grid_store_flow = Dict(
        n1 => [
            reduce(
                +,
                sd[(st, n2), Y[1], P[1], t] - sc[(st, n2), Y[1], P[1], t] for
                (st, n2) in STN if n2 == n1;
                init=0.0,
            ) for t in T
        ] for n1 in N
    )

    # Add a key in the bus dictionaries for the injection
    for (i, bus) in network["bus"]
        bus["store_inj"] = grid_store_flow[bus["string"]]
    end

    # Save the dictionary
    exp_pro = datadir("pro")
    open(joinpath(exp_pro, grid_mod_path), "w") do f
        JSON.print(f, network, 4)
    end

    # Adapt GEPPR input as well
    df = CSV.read(datadir("pro", "GEPPR", "timeseries.csv"), DataFrame)
    mod_load = Float64[]
    for row in eachrow(df)
        n = string(row["Node"])
        t = row["Timestep"]
        mod_load_val = row["Load"] - grid_store_flow[n][t]
        push!(mod_load, mod_load_val)
    end
    df[:,"Load"] = mod_load
    CSV.write(datadir("pro", "GEPPR", "timeseries_wo_storage.csv"), df)
    
    return network
end
