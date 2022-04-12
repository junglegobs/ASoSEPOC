using XLSX, PowerModels, JSON, YAML, StatsBase, DataFrames, CSV, GEPPR, Dates
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
        name = row["E"]
        if ismissing(bus_id) == false && bus_id isa Number
            bus_type = (bus_id == 1 ? 3 : 2) # TODO
            network["bus"]["$bus_id"] = Dict(
                "index" => bus_id,
                "string" => name,
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
        cost = (fuel / catg_row[3]) * 1000 # Euros/MWh
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

    # Power to Gas
    h2_sh = gen["hydrogen_storage"]
    duration = 1000
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
            "charge_rating" => row["D"] / duration,
            "discharge_rating" => row["D"] / duration,
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

    # Utilities
    nodes = sort([v["string"] for (k, v) in network["bus"]])
    node2ids = sort(
        Dict(v["string"] => v["index"] for (k, v) in network["bus"])
    )
    ids2node = sort(Dict(v => k for (k, v) in node2ids))
    node_ids = [node2ids[name] for name in nodes]

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
                "nodes" => [ids2node[v["gen_bus"]]],
                "fuelType" => "Dummy",
            ) for (k, v) in gen
        ),
    )
    YAML.write_file(joinpath(GEPPR_dir, "units.yaml"), d)

    # Renewable generation
    res = network["res"]
    res_names = unique([v["name"] for (k, v) in res])
    res_nodes = Dict(
        t => [ids2node[v["bus"]] for (k, v) in res if v["name"] == t] for
        t in res_names
    )
    cap = Dict(
        t => Dict(
            ids2node[v["bus"]] => v["cap"] for (k, v) in res if v["name"] == t
        ) for t in res_names
    )
    d = Dict(
        "intermittentGeneration" => Dict(
            t => Dict(
                "nodes" => res_nodes[t],
                "availabilityFactor" => t, # [-]
                "installedCapacity" =>
                    Dict(string(k) => Float64(v) for (k, v) in cap[t]), # [MW]
                "averageGenerationCost" => 0.0,
                "variableOperationAndMaintenanceCost" => 0.0, 
                # Otherwise reserve activation doesn't work
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
                    "nodes" => [ids2node[v["storage_bus"]]],
                ) for (k, v) in network["storage"]
            ),
        )
        YAML.write_file(joinpath(GEPPR_dir, "storage.yaml"), d)
    end

    # Time series
    d = Dict(v["load_bus"] => v["pd"] for (k, v) in network["load"])
    af = Dict(
        (ids2node[v["bus"]], v["name"]) => Float64.(v["af"]) for
        (k, v) in network["res"]
    )
    df = DataFrame(
        "Timestep" => repeat(1:nT; outer=length(nodes)),
        "Node" => repeat(nodes; inner=nT),
        "Load" => vcat([d[n] for n in node_ids]...),
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
                sd[(st, n2), Y[1], P[1], t] - sc[(st, n2), Y[1], P[1], t]
                for (st, n2) in STN if n2 == n1;
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
    df[:, "Load"] = mod_load
    CSV.write(datadir("pro", "GEPPR", "timeseries_wo_storage.csv"), df)

    return network
end

"""
    load_scenarios(opts, files_dict; err_file)

Iterate over paths in `files_dict` to return forecasts and error scenarios.

# Keyword arguments

* `err_file`: log output to a file of this name in `datadir("pro", "scenario_loading")`.
"""
function load_scenarios(
    opts::Dict, files_dict::Dict; err_file=string(round(now(), Dates.Minute))
)
    myscens = Dict()
    mkrootdirs(datadir("pro", "scenario_loading"))
    myf = open(datadir("pro", "scenario_loading", err_file * ".dat"), "w")
    for (name, file_prefix) in files_dict
        print(myf, "-"^80 * "\nReading $name error scenarios\n")

        f_err = string(file_prefix, ".csv")
        forecast = string(file_prefix, "_forecast.csv")

        err_data = CSV.read(f_err, DataFrame; header=false) #--> 1st row is treated as a data row
        (err_rw, err_cl) = size(err_data)

        num_err = err_cl - 3 #-->first 3 columns are identifiers
        num_err_scens = (err_rw - 3) / 24 #--> first 3 rows are also identifiers
        print(myf, "Found $num_err_scens scenarios for $name error\n")

        if isinteger(num_err_scens) != true
            print(
                myf,
                "\n**** Terminal error: non-integer $name error scenario size",
            )
            close(myf)
            error()
        end

        myscens[name] = Dict()  #-- 1 subdict per branch + scenario (starting with 0)
        myscens[name]["total"] = Dict()
        myscens[name]["total"]["scenarios"] = Dict()
        myscens[name]["total"]["forecast"] = Dict()

        for jdx in 4:err_cl
            id = err_data[1, jdx]
            full_name = err_data[2, jdx]

            myscens[name][full_name] = Dict()
            myscens[name][full_name]["id"] = parse(Int64, id)
            myscens[name][full_name]["pmax_mw"] = parse(
                Float64, err_data[6, jdx]
            )
            myscens[name][full_name]["scenarios"] = Dict()
            myscens[name][full_name]["forecast"] = Dict()

            #-- reading row entrys for this column
            for idx in 4:err_rw
                the_scen = convert(
                    Int64, (parse(Float64, err_data[idx, 2]) + 1)
                )
                the_hour = parse(Float64, err_data[idx, 3])
                the_hour = convert(Int64, the_hour)

                if the_hour <= 9
                    hkey = string("0", "$the_hour", ":00")
                else
                    hkey = string("$the_hour", ":00")
                end

                #-- setting up (if needed) the scenario sub-dict for this substation
                if haskey(myscens[name][full_name]["scenarios"], the_scen) !=
                    true
                    myscens[name][full_name]["scenarios"][the_scen] = Dict()
                end

                #-- setting up (if needed) the scenario sub-dict for the total
                if haskey(myscens[name]["total"]["scenarios"], the_scen) != true
                    myscens[name]["total"]["scenarios"][the_scen] = Dict()
                end

                #-- hourly error for substation & scenario
                myscens[name][full_name]["scenarios"][the_scen][hkey] = parse(
                    Float64, err_data[idx, jdx]
                ) #-- already in MWh

                #-- adding to the total value
                if haskey(
                    myscens[name]["total"]["scenarios"][the_scen], hkey
                ) != true
                    myscens[name]["total"]["scenarios"][the_scen][hkey] = parse(
                        Float64, err_data[idx, jdx]
                    )
                else
                    myscens[name]["total"]["scenarios"][the_scen][hkey] += parse(
                        Float64, err_data[idx, jdx]
                    )
                end
            end
        end #- per column (substation)
        print(myf, "\n" * "-"^80 * "\n" * "-"^80 * "\nReading $name forecast\n")

        for_data = CSV.read(forecast, DataFrame; header=false) #--> 1st row is treated as a data row
        for_rw, for_cl = size(for_data)

        num_for = for_cl - 3 #-->first 3 columns are identifiers
        num_for_scens = (for_rw - 3) / 24 #--> first 3 rows are also identifiers
        print(myf, "Found $num_for_scens $name forecast\n")

        if isinteger(num_for_scens) != true
            print(myf, "\n****Terminal error: non-integer $name forecast size")
            close(myf)
            error()
        end

        for jdx in 4:for_cl
            full_name = for_data[2, jdx]

            if haskey(myscens[name], full_name)

                #-- reading row entrys for this column
                for idx in 4:for_rw
                    the_hour = parse(Float64, for_data[idx, 3])
                    the_hour = convert(Int64, the_hour)

                    if the_hour <= 9
                        hkey = string("0", "$the_hour", ":00")
                    else
                        hkey = string("$the_hour", ":00")
                    end

                    #-- hourly forecast for substation
                    myscens[name][full_name]["forecast"][hkey] = parse(
                        Float64, for_data[idx, jdx]
                    ) #-- already in MWh

                    #-- adding to the total value
                    if haskey(myscens[name]["total"]["forecast"], hkey) != true
                        myscens[name]["total"]["forecast"][hkey] = parse(
                            Float64, for_data[idx, jdx]
                        )
                    else
                        myscens[name]["total"]["forecast"][hkey] += parse(
                            Float64, for_data[idx, jdx]
                        )
                    end
                end #- row entries per column

            else
                print(
                    myf,
                    "** I found a forecast but no scenarios for $name @ $full_name",
                )
            end
        end #- per column (substation)
        print(myf, "\n" * "-"^80)
    end
    close(myf)
    return myscens
end

function load_scenarios(opts::Dict)
    return load_scenarios(
        opts,
        Dict(
            "Load" => opts["load_scenario_data_paths"],
            "Wind" => opts["wind_scenario_data_paths"],
            "Solar" => opts["solar_scenario_data_paths"],
        ),
    )
end

function scenarios_2_GEPPR(opts::Dict, scens)
    @unpack upward_reserve_levels, downward_reserve_levels = opts
    
    # Get net load forecast error per node
    mult = Dict("Load" => -1, "Wind" => 1, "Solar" => 1)
    net_load_forecast_error_dict = scenarios_2_net_load_forecast_error(opts, scens, mult)

    # Sum up uncertainty over entire network
    total_NLFE = sum(v for (k, v) in net_load_forecast_error_dict)

    # Get quantiles
    D⁺, D⁻, P⁺, P⁻, Dmid⁺, Dmid⁻ = get_probabilistic_reserve_parameters_from_scenarios(
        transpose(total_NLFE);
        n_up=upward_reserve_levels,
        n_down=downward_reserve_levels,
        coverage=10, # Number of scenarios ignored on tail ends
    )

    return D⁺, D⁻, P⁺, P⁻, Dmid⁺, Dmid⁻
end

function scenarios_2_net_load_forecast_error(opts::Dict, scens, mult)
    pm = PowerModels.parse_file(grid_red_path)

    # Convolute scenarios to get total net load forecast error
    net_load_forecast_error_dict = Dict{String,Matrix{Float64}}()
    for (k, bus) in pm["bus"]
        name = bus["string"]
        bus_scen_dicts = Dict(
            k1 => scens[k1][name] for
            (k1, v) in scens if haskey(scens[k1], name)
        )
        bus_scen_mat = Dict(
            k1 => hcat(
                [
                    [val for (hr, val) in sort(scen_dict)] for
                    (scen_id, scen_dict) in sort(v1["scenarios"])
                ]...,
            ) for (k1, v1) in bus_scen_dicts
        )

        # Net load is negative -> upward reserves are activated
        # Net load is positive -> downward reserves are activated 
        net_load_forecast_error_dict[name] = sum(
            scen_mat * mult[source] for (source, scen_mat) in bus_scen_mat
        )
    end
    return net_load_forecast_error_dict
end

function scenarios_2_forecast(opts, scens; src_name=first(collect(keys(k))))
    pm = PowerModels.parse_file(grid_red_path)
    forecast = Dict{String,Vector{Float64}}()
    for (k, bus) in pm["bus"]
        bname = bus["string"]
        forecast[bname] = collect(values(sort(scens[src_name][bname]["forecast"])))
    end
    return forecast
end

"""
    get_probabilistic_reserve_parameters_from_scenarios(scenarios; kwargs...)

# Keyword arguments #md
* `n_up`: Number of upward reserve (discretisation) levels
* `n_down`: Number of downward reserve (discretisation) levels
* `coverage`: Reserve coverage, cuts off `coverage` number of scenarios with highest and lowest values. 
"""
function get_probabilistic_reserve_parameters_from_scenarios(
    scenarios::AbstractMatrix; n_up=10, n_down=10, coverage=0
)
    sorted_scenarios = sort(scenarios; dims=1)
    nS = size(scenarios, 1)
    nT = size(scenarios, 2)
    @assert n_up + n_down + coverage < nS
    sorted_scenarios = sorted_scenarios[(coverage + 1):(nS - coverage), :]
    D⁺ = fill(NaN, n_up, nT)
    D⁻ = fill(NaN, n_down, nT)
    P⁺ = fill(NaN, n_up, nT)
    P⁻ = fill(NaN, n_down, nT)
    Dmid⁺ = fill(NaN, n_up, nT)
    Dmid⁻ = fill(NaN, n_down, nT)
    for t in 1:nT
        q_cut_up, q_mid_up, p_up, q_cut_down, q_mid_down, p_down = quantiles_and_probabilities(
            sorted_scenarios[:, t]; n_up=n_up, n_down=n_down
        )

        for l in 1:n_up
            D⁺[l, t] = max(q_cut_up[l + 1] - q_cut_up[l], 0)
            Dmid⁺[l, t] = q_mid_up[l]
            P⁺[l, t] = p_up[l]
        end
        for l in 1:n_down
            D⁻[l, t] = max(q_cut_down[l] - q_cut_down[l + 1], 0)
            Dmid⁻[l, t] = q_mid_down[l]
            P⁻[l, t] = p_down[l]
        end
    end
    return D⁺, D⁻, P⁺, P⁻, Dmid⁺, Dmid⁻
end

"""
    quantiles_and_probabilities(vec; n_up, n_down)
    
Returns the quantile cut off points, mid points and probabilities of deviating from the median to the mid points for above and below the median of `vec`.
"""
function quantiles_and_probabilities(vec; n_up=n_up, n_down=n_down)
    dist = ecdf(vec)

    qcf_down = reverse(range(minimum(vec), 0; length=n_down + 1)) # quantile cut of points
    qmp_down = [mean([qcf_down[j], qcf_down[j + 1]]) for j in 1:n_down] # quantile mid points
    qp_down = [dist(qmp_down[j]) for j in 1:n_down] # Quantile probabilities

    qcf_up = range(0, maximum(vec); length=n_up + 1) # quantile cut of points
    qmp_up = [mean([qcf_up[j], qcf_up[j + 1]]) for j in 1:n_up] # quantile mid points
    qp_up = [1 - dist(qmp_up[j]) for j in 1:n_up] # Quantile probabilities

    return vcat(qcf_up...), qmp_up, qp_up, vcat(qcf_down...), qmp_down, qp_down
end
