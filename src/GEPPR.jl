using GEPPR, Suppressor, UnPack, Cbc, Infiltrator, JLD2, JuMP, AxisArrays, JSON
include(srcdir("util.jl"))

### UTIL
function param_and_config(opts::Dict)
    @unpack optimization_horizon,
    rolling_horizon,
    include_downward_reserves,
    include_storage,
    copperplate,
    initial_state_of_charge,
    reserve_provision_cost,
    operating_reserves_type, cyclic_state_of_charge_constraint = opts

    is_linear = (opts["unit_commitment_type"] == "none")
    init_soc = opts["initial_state_of_charge"]

    GEPPR_dir = datadir("pro", "GEPPR")
    configFiles =
        joinpath.(
            GEPPR_dir,
            [
                "booleans.yaml",
                "parameters.yaml",
                "fuels.yaml",
                "units.yaml",
                "RES.yaml",
            ],
        )

    # Param
    param = @suppress Dict{String,Any}(
        "optimizer" => optimizer(opts),
        "unitCommitmentConstraintType" => opts["unit_commitment_type"],
        "relativePathTimeSeriesCSV" =>
            if opts["replace_storage_dispatch_with_node_injection"]
                "timeseries_wo_storage.csv"
            else
                "timeseries.csv"
            end,
        "includeDownwardReserves" => include_downward_reserves,
        "relativePathMatpowerData" => basename(grid_red_path),
        "optimizationHorizon" => Dict(
            "start" => [1, 1, optimization_horizon[1]],
            "end" => [1, 1, optimization_horizon[end]],
        ),
        "imposePeriodicityConstraintOnStorage" =>
            rolling_horizon || (cyclic_state_of_charge_constraint == false) ? false : true,
        "dispatchableGeneration" => Dict(),
        "intermittentGeneration" => Dict(),
        "reserveType" => operating_reserves_type,
    )

    # In case including storage
    if include_storage
        push!(configFiles, joinpath(GEPPR_dir, "storage.yaml"))
        opts["storageTechnologies"] = Dict()
    end

    # Reserve provision costs
    if reserve_provision_cost > 0.0
        rpc = reserve_provision_cost
        disp_data = YAML.load(open(datadir("pro", "GEPPR", "units.yaml")))["dispatchableGeneration"]
        res_data = YAML.load(open(datadir("pro", "GEPPR", "RES.yaml")))["intermittentGeneration"]
        for (k, v) in disp_data
            param["dispatchableGeneration"][k] = Dict(
                "reserveProvisionCost" => rpc
            )
        end
        for (k, v) in res_data
            param["intermittentGeneration"][k] = Dict(
                "reserveProvisionCost" => rpc
            )
        end
    end

    # Error if this optimization horizon too long
    if length(optimization_horizon[1]:optimization_horizon[end]) > 100 &&
        is_linear == false &&
        rolling_horizon == false
        error(
            "Optimisation length too long for unit commitment model, consider setting `rolling_horizon = true`.",
        )
    end

    # Copper plate model or not
    if opts["copperplate"] == true
        param["forceCopperPlateModel"] = true
    end

    # Storage initial state of charge
    if include_storage && ismissing(init_soc) == false
        init_soc = opts["initial_state_of_charge"]
        @assert 0 <= init_soc <= 1
        storage_data = YAML.load(open(datadir("pro", "GEPPR", "storage.yaml")))["storageTechnologies"]
        param["storageTechnologies"] = Dict(
            st => Dict(
                "initialStateOfCharge" =>
                    v["installedEnergyCapacity"] * init_soc,
            ) for (st, v) in storage_data
        )
    end

    return configFiles, param
end

function optimizer(opts::Dict)
    if GRB_EXISTS
        UC = (opts["unit_commitment_type"] != "none")
        return optimizer_with_attributes(
            Gurobi.Optimizer,
            "TimeLimit" => time_out(opts),
            "OutputFlag" => 1,
            # "Method" => UC ? 1 : -1,
            # "PreSolve" => 0,
        )
    elseif CPLEX_EXISTS
        return optimizer_with_attributes(CPLEX.Optimizer)
    else
        return Cbc.Optimizer
    end
end

function time_out(opts::Dict)
    @unpack rolling_horizon = opts
    time_out = get(opts, "time_out", missing)
    if ismissing(time_out) == false
        return time_out
    else
        is_linear = (opts["unit_commitment_type"] == "none")
        opt_hrzn = opts["optimization_horizon"]
        nT = opt_hrzn[end] - opt_hrzn[1] + 1
        return rolling_horizon ? 100 : nT * (2 + (1 - is_linear) * 2)
    end
end

function gepm(opts::Dict)
    cf, param = param_and_config(opts)
    gep = GEPM(cf, param)
    return gep
end

function run_GEPPR(opts::Dict; load_only=false)
    @unpack save_path, rolling_horizon = opts
    gep = if isdir(save_path) && isfile(joinpath(save_path, "data.csv"))
        @info "GEPM found at $(save_path), loading..."
        load_GEP(opts, save_path)
    elseif load_only == false
        @info "Running GEPM (save path is $(save_path))..."
        gep = gepm(opts)
        terminal_out = @capture_out begin
            if rolling_horizon == false
                apply_operating_reserves!(gep, opts)
                modify_network!(gep, opts)
                modify_timeseries!(gep, opts)
                @info "Building JuMP model..."
                make_JuMP_model!(gep)
                apply_initial_commitment!(gep, opts)
                constrain_reserve_shedding!(gep, opts)
                prevent_simultaneous_charge_and_discharge!(gep, opts)
                apply_initial_state_of_charge!(gep, opts)
                absolute_limit_on_nodal_imbalance!(gep, opts)
                convex_hull_limit_on_nodal_imbalance!(gep, opts)
                fix_storage_dispatch!(gep, opts)
                optimize_GEP_model!(gep)
                save_optimisation_values!(gep)
            else
                modify_network!(gep, opts)
                modify_timeseries!(gep, opts)
                run_rolling_horizon(gep; scheduleLength=168, slackVariables=(:sc, :sd, :z, :d⁺, :Δq, :v))
            end
            nothing
        end
        gep[:O, :terminal_out] = terminal_out
        save(gep, opts)
        gep
    else
        @warn "GEPPR model not found"
        return nothing
    end
    return gep
end

function run_GEPPR(opts_vec; kwargs...)
    return [
        try
            run_GEPPR(opts; kwargs...)
        catch
            @warn "Optimisation failed"
        end for opts in opts_vec
    ]
end

function GEPPR.load_GEP(opts::Dict, path::String)
    @load eval(joinpath(path, "config.jld2")) dictConfig
    cFVec = String[]
    for cf in dictConfig["configFile"]
        split_path = split(cf, "/data/")
        push!(cFVec, datadir(splitpath(split_path[2])...))
    end
    dictConfig["configFile"] = cFVec
    @save eval(joinpath(path, "config.jld2")) dictConfig
    return load_GEP(path)
end

function apply_initial_commitment!(gep::GEPM, opts::Dict)
    @unpack save_path, optimization_horizon, initial_commitment_data_path = opts
    isempty(initial_commitment_data_path) && return nothing

    @info "Applying initial commitment..."
    z_val = load_GEP(opts, initial_commitment_data_path)[:z]
    z = GEPPR.get_online_units_var(gep)
    N, Y, P, T = GEPPR.get_set_of_nodes_and_time_indices(gep)
    GN = GEPPR.get_set_of_nodal_dispatchable_generators(gep)
    t_init = optimization_horizon[1]
    for gn in GN, y in Y, p in P
        fix(z[gn, y, p, t_init], z_val[gn, y, p, t_init]; force=true)
    end
    return nothing
end

function apply_operating_reserves!(gep::GEPM, opts::Dict)
    @unpack operating_reserves_type,
    operating_reserves_sizing_type,
    upward_reserve_levels,
    downward_reserve_levels,
    upward_reserve_levels_included_in_redispatch,
    downward_reserve_levels_included_in_redispatch = opts

    operating_reserves_type == "none" && return gep
    @assert operating_reserves_type == "probabilistic"
    @assert operating_reserves_sizing_type == "given"

    @info "Getting scenarios..."
    scens = load_scenarios(opts; for_GEPPR=true)

    @info "Converting scenarios to quantiles..."
    D⁺, D⁻, P⁺, P⁻, Dmid⁺, Dmid⁻ = scenarios_2_GEPPR(opts, scens)

    @info "Applying reserves to GEPPR model..."
    modify_parameter!(gep, "reserveType", "probabilistic")
    modify_parameter!(gep, "reserveSizingType", "given")
    modify_parameter!(gep, "includeReserveActivationCosts", true)
    modify_parameter!(gep, "includeDownwardReserves", true)
    modify_parameter!(
        gep,
        "upwardReserveLevelsIncludedInNetworkRedispatch",
        upward_reserve_levels_included_in_redispatch,
    )
    modify_parameter!(
        gep,
        "downwardReserveLevelsIncludedInNetworkRedispatch",
        downward_reserve_levels_included_in_redispatch,
    )
    L⁺ = gep[:I, :sets, :L⁺] = 1:upward_reserve_levels
    L⁻ = gep[:I, :sets, :L⁻] = 1:downward_reserve_levels
    ORBZ = GEPPR.get_set_of_operating_reserve_balancing_zones(gep)
    N, Y, P, T = GEPPR.get_set_of_nodes_and_time_indices(gep)
    gep[:I, :uncertainty, :P⁺] = Dict(
        (l, y, p, T[t]) => P⁺[l, t] for l in L⁺, y in Y, p in P,
        t in 1:length(T)
    )
    gep[:I, :uncertainty, :P⁻] = Dict(
        (l, y, p, T[t]) => P⁻[l, t] for l in L⁻, y in Y, p in P,
        t in 1:length(T)
    )
    gep[:I, :uncertainty, :D⁺] = Dict(
        (z, l, y, p, T[t]) => D⁺[l, t] for z in ORBZ, l in L⁺, y in Y, p in P,
        t in 1:length(T)
    )
    gep[:I, :uncertainty, :D⁻] = Dict(
        (z, l, y, p, T[t]) => D⁻[l, t] for z in ORBZ, l in L⁻, y in Y, p in P,
        t in 1:length(T)
    )
    return gep
end

function modify_network!(gep::GEPM, opts::Dict)
    @unpack rate_a_multiplier = opts
    if ismissing(rate_a_multiplier) == false
        @info "Multiplying network branch limits by a factor $rate_a_multiplier..."
        for (idx, br) in gep.networkData["branch"]
            br["rate_a"] *= rate_a_multiplier
        end
    end
    return gep
end

function constrain_reserve_shedding!(gep::GEPM, opts::Dict)
    @unpack reserve_shedding_limit,
    operating_reserves_type,
    operating_reserves_sizing_type = opts

    operating_reserves_type == "none" && return gep
    @assert operating_reserves_type == "probabilistic"
    @assert operating_reserves_sizing_type == "given"

    @info "Constraining reserve shedding..."

    rsL⁺ = GEPPR.get_upward_reserve_level_shedding_var(gep)
    D⁺ = GEPPR.get_upward_reserve_level_expression(gep)
    N, Y, P, T = GEPPR.get_set_of_nodes_and_time_indices(gep)
    ORBZ = GEPPR.get_set_of_operating_reserve_balancing_zones(gep)
    ORBZ2N = GEPPR.get_set_linking_operating_reserve_balancing_zones_to_nodes(
        gep
    )
    L⁺ = GEPPR.get_set_of_upward_reserve_levels(gep)

    norm_factor = Dict(
        t => sum(D⁺[z, l, Y[1], P[1], t] for z in ORBZ, l in L⁺) for t in T
    )
    gep[:M, :constraints, :reserveSheddingLimit] = @constraint(
        gep.model,
        [z = ORBZ, y in Y, p in P, t = T],
        sum(rsL⁺[n, l, y, p, t] for n in ORBZ2N[z], l in L⁺) /
        (iszero(norm_factor[t]) ? 1.0 : norm_factor[t]) <=
            reserve_shedding_limit
    )
    return gep
end

function prevent_simultaneous_charge_and_discharge!(gep::GEPM, opts::Dict)
    @unpack include_storage, prevent_simultaneous_charge_and_discharge = opts
    if include_storage == false ||
        prevent_simultaneous_charge_and_discharge == false
        return gep
    end
    @info "Preventing simultaneous charging and discharging"

    N, Y, P, T = GEPPR.get_set_of_nodes_and_time_indices(gep)
    STN = GEPPR.get_set_of_nodal_storage_technologies(gep)
    SCK = GEPPR.get_storage_charging_capacity_expression(gep)
    SDK = GEPPR.get_storage_discharging_capacity_expression(gep)
    gep[:M, :variables, :o] =
        o = @variable(
            gep.model,
            [stn = STN, y = Y, p = P, t = T],
            binary = true,
            base_name = "o"
        )
    sc = GEPPR.get_storage_charge_var(gep)
    sd = GEPPR.get_storage_discharge_var(gep)

    @constraint(
        gep.model,
        [stn = STN, y = Y, p = P, t = T],
        sc[stn, y, p, t] <= o[stn, y, p, t] * SCK[stn, y]
    )
    @constraint(
        gep.model,
        [stn = STN, y = Y, p = P, t = T],
        sd[stn, y, p, t] <= (1 - o[stn, y, p, t]) * SDK[stn, y]
    )

    return gep
end

function apply_initial_state_of_charge!(gep::GEPM, opts::Dict)
    @unpack initial_state_of_charge = opts
    ismissing(initial_state_of_charge) && return gep
    E_init = GEPPR.get_storage_initial_state_of_charge(gep; default=missing)
    e = GEPPR.get_storage_state_of_charge_var(gep)
    STN = GEPPR.get_set_of_nodal_storage_technologies(gep)
    N, Y, P, T = GEPPR.get_set_of_nodes_and_time_indices(gep)
    for stn in STN
        fix(e[stn, Y[1], P[1], T[1] - 1], E_init[stn]; force=true)
    end
    return gep
end

function absolute_limit_on_nodal_imbalance!(gep::GEPM, opts::Dict)
    @unpack absolute_limit_on_nodal_imbalance,
    allow_absolute_imbalance_slacks,
    absolute_imbalance_slack_penalty = opts
    absolute_limit_on_nodal_imbalance == false && return gep
    sp = absolute_imbalance_slack_penalty

    @info "Applying absolute limits on nodal imbalance..."
    scen_id = month_day(opts)
    data, file = produce_or_load(
        datadir("pro", "nodal_imbalance_abs_limits"),
        opts,
        absolute_limits_on_nodal_imbalance;
        filename="$(scen_id).jld2",
    )
    @unpack d_min, d_max = data
    dL⁺ = GEPPR.get_possible_nodal_imbalance_due_to_upward_reserve_level_activation(
        gep
    )
    dL⁻ = GEPPR.get_possible_nodal_imbalance_due_to_downward_reserve_level_activation(
        gep
    )
    N, Y, P, T = GEPPR.get_set_of_nodes_and_time_indices(gep)
    L⁺ = GEPPR.get_set_of_upward_reserve_levels_included_in_network_redispatch(
        gep
    )
    L⁻ = GEPPR.get_set_of_downward_reserve_levels_included_in_network_redispatch(
        gep
    )

    # Slack variables
    abs_slack_L⁺ =
        gep[:M, :variables, :abs_slack_L⁺] = @variable(
            gep.model,
            [n = N, l = L⁺, y = Y, p = P, t = T],
            base_name = "abs_slack_L⁺"
        )
    abs_slack_L⁻ =
        gep[:M, :variables, :abs_slack_L⁻] = @variable(
            gep.model,
            [n = N, l = L⁻, y = Y, p = P, t = T],
            base_name = "abs_slack_L⁻"
        )

    # Fix slacks if necessary
    if allow_absolute_imbalance_slacks == false
        JuMP.fix.(abs_slack_L⁺, 0.0; force=true)
        JuMP.fix.(abs_slack_L⁻, 0.0; force=true)
    end

    # Constraints
    gep[:M, :constraints, :MaxAbsNodalImbalanceUp] = @constraint(
        gep.model,
        [n = N, l = L⁺, y = Y, p = P, i = 1:length(T)],
        dL⁺[n, l, y, p, T[i]] + abs_slack_L⁺[n, l, y, p, T[i]] <= d_max[n][i]
    )
    gep[:M, :constraints, :MinAbsNodalImbalanceUp] = @constraint(
        gep.model,
        [n = N, l = L⁺, y = Y, p = P, i = 1:length(T)],
        dL⁺[n, l, y, p, T[i]] + abs_slack_L⁺[n, l, y, p, T[i]] >= d_min[n][i]
    )
    gep[:M, :constraints, :MaxAbsNodalImbalanceDown] = @constraint(
        gep.model,
        [n = N, l = L⁻, y = Y, p = P, i = 1:length(T)],
        dL⁻[n, l, y, p, T[i]] + abs_slack_L⁻[n, l, y, p, T[i]] <= d_max[n][i]
    )
    gep[:M, :constraints, :MinAbsNodalImbalanceDown] = @constraint(
        gep.model,
        [n = N, l = L⁻, y = Y, p = P, i = 1:length(T)],
        dL⁻[n, l, y, p, T[i]] + abs_slack_L⁻[n, l, y, p, T[i]] >= d_min[n][i]
    )

    # Overload objective
    obj = gep[:M, :objective]
    gep[:M, :objective_w_slack] = @objective(
        gep.model,
        Min,
        obj +
            sp *
        (sum(el^2 for el in abs_slack_L⁺) + sum(el^2 for el in abs_slack_L⁻))
    )

    return gep
end

function convex_hull_limit_on_nodal_imbalance!(gep::GEPM, opts::Dict)
    @unpack convex_hull_limit_on_nodal_imbalance,
    n_scenarios_for_convex_hull_calc = opts
    convex_hull_limit_on_nodal_imbalance == false && return gep

    @info "Applying convex hull limits on nodal imbalance..."
    n_scens = n_scenarios_for_convex_hull_calc
    scen_id = month_day(opts)
    poly_dict, file = produce_or_load(
        datadir("pro", "nodal_imbalance_convex_hull_limits"),
        opts,
        convex_hull_limits_on_nodal_imbalance;
        filename="$(scen_id)_n_scens=$(n_scens).jld2",
    )
    dL⁺ = GEPPR.get_possible_nodal_imbalance_due_to_upward_reserve_level_activation(
        gep
    )
    dL⁻ = GEPPR.get_possible_nodal_imbalance_due_to_downward_reserve_level_activation(
        gep
    )
    N, Y, P, T = GEPPR.get_set_of_nodes_and_time_indices(gep)
    L⁺ = GEPPR.get_set_of_upward_reserve_levels_included_in_network_redispatch(
        gep
    )
    L⁻ = GEPPR.get_set_of_downward_reserve_levels_included_in_network_redispatch(
        gep
    )

    gep[:M, :constraints, :convexHullNodalImbalance] = con = Dict()
    for ti in 1:length(T)
        t = T[ti]
        for l in L⁺
            dl = [dL⁺[n, l, Y[1], P[1], t] for n in sort(N)]
            con[t, l] = @constraint(gep.model, dl in poly_dict[string(ti)])
        end
        for l in L⁻
            dl = [dL⁻[n, l, Y[1], P[1], t] for n in sort(N)]
            con[t, -l] = @constraint(gep.model, dl in poly_dict[string(ti)])
        end
    end

    return gep
end

function fix_storage_dispatch!(gep::GEPM, opts::Dict)
    try
        @unpack sc, sd = opts
        fix_model_variable!(gep, :sc, sc)
        fix_model_variable!(gep, :sd, sd)
    catch
        nothing
    end
    return gep
end

function modify_timeseries!(gep::GEPM, opts::Dict)
    @unpack load_multiplier = opts
    if ismissing(load_multiplier) == false
        @info "Multiplying load by a factor $load_multiplier..."
        gep.timeSeriesData[:, "Load"] *= load_multiplier
    end

    return gep
end

function save(gep::GEPM, opts::Dict)
    @unpack save_path = opts
    file_name = joinpath(save_path, "opts.jld2")
    wsave(file_name, opts)

    opts_new = copy(opts)
    delete!(opts_new, "sc")
    delete!(opts_new, "sd")
    file_name = joinpath(save_path, "opts.json")
    open(file_name, "w") do f
        JSON.print(f, opts_new, 4)
    end

    save_gep_for_security_analysis(gep, opts)

    vars_2_save = get(opts, "vars_2_save", nothing)
    exprs_2_save = get(opts, "exprs_2_save", nothing)
    if vars_2_save !== nothing
        gep[:O, :variables] = GEPPR.OrderedDict(
            k => gep[k] for k in vars_2_save
        )
        gep[:O, :constraints] = nothing
        gep[:O, :expressions] = GEPPR.OrderedDict(
            k => gep[k] for k in exprs_2_save
        )
    end
    GEPPR.save(gep, save_path)

    open(joinpath(save_path, "optimizer_out.dat"), "w") do io
        print(io, gep[:O, :terminal_out])
    end

    return gep
end

"""
    save_gep_for_security_analysis(gep::GEPM, path::String)

Saves data in the format: hour -> generator (with associated bus) -> values / name / bus etc.
"""
function save_gep_for_security_analysis(gep::GEPM, path::String)
    q = gep[:q]
    z = gep[:z, SVC(missing)]
    e = gep[:e, SVC(missing)]
    sc = gep[:sc, SVC(missing)]
    sd = gep[:sd, SVC(missing)]
    ls = gep[:loadShedding, gep[:ls, SVC(missing)] .+ gep[:lsel, SVC(missing)]]
    UC_results = Dict{Integer,Dict}()
    N, Y, P, T = GEPPR.get_set_of_nodes_and_time_indices(gep)
    GDN = GEPPR.get_set_of_nodal_dispatchable_generators(gep)
    GRN = GEPPR.get_set_of_nodal_intermittent_generators(gep)
    STN = GEPPR.get_set_of_nodal_storage_technologies(gep)
    TN2idx = tech_node_to_idx(gep)
    y, p = first.([Y, P])
    for t in T
        UC_results[t] = Dict(
            "gen" => Dict(
                TN2idx[(g, n)] => Dict(
                    "bus" => n,
                    "name" => g,
                    "q" => q[(g, n), y, p, atval(t, typeof(q))],
                    "z" => z[(g, n), y, p, atval(t, typeof(z))],
                ) for (g, n) in GDN
            ),
            "res" => Dict(
                TN2idx[(g, n)] => Dict(
                    "bus" => n,
                    "name" => g,
                    "q" => q[(g, n), y, p, atval(t, typeof(q))],
                ) for (g, n) in GRN
            ),
            "store" => Dict(
                TN2idx[(st, n)] => Dict(
                    "bus" => n,
                    "name" => st,
                    "e" => e[(st, n), y, p, atval(t - 1, typeof(e))],
                    "discharge" => sd[(st, n), y, p, atval(t, typeof(sd))],
                    "charge" => sc[(st, n), y, p, atval(t, typeof(sc))],
                ) for (st, n) in STN
            ),
            "load_shed" => Dict(
                n => Dict(
                    "value" => ls[n, y, p, atval(t, typeof(ls))],
                    "bus" => n,
                ) for n in N
            ),
        )
    end
    # @save eval(path) UC_results
    # JDL.save(path, "UC_results", UC_results)
    open(path, "w") do f
        JSON.print(f, UC_results)
    end
    return UC_results
end

function tech_node_to_idx(gep::GEPM)
    nd = gep.networkData
    GDN = GEPPR.get_set_of_nodal_dispatchable_generators(gep)
    GRN = GEPPR.get_set_of_nodal_intermittent_generators(gep)
    STN = GEPPR.get_set_of_nodal_storage_technologies(gep)
    bus_idx_2_name = Dict(v["bus_i"] => v["string"] for (k, v) in nd["bus"])
    d = merge(
        Dict(
            gn => string(
                collect(nd["res"])[findfirst(
                    pair -> (
                        bus_idx_2_name[string(pair[2]["bus"])] ==
                        string(gn[2]) && pair[2]["name"] == gn[1]
                    ),
                    collect(nd["res"]),
                )][1],
            ) for gn in GRN
        ),
        Dict(
            gn => string(
                collect(nd["gen"])[findfirst(
                    pair -> (
                        bus_idx_2_name[string(pair[2]["gen_bus"])] ==
                        string(gn[2]) && pair[2]["name"] == gn[1]
                    ),
                    collect(nd["gen"]),
                )][1],
            ) for gn in GDN
        ),
        Dict(
            stn => string(
                collect(nd["storage"])[findfirst(
                    v -> (
                        bus_idx_2_name[string(v["storage_bus"])] ==
                        string(stn[2]) && v["name"] == stn[1]
                    ),
                    collect(values(nd["storage"])),
                )][1],
            ) for stn in STN
        ),
    )
    return d
end

function atval(idx, T::Type)
    if T <: AxisArray
        return atvalue(idx)
    else
        return idx
    end
end

function save_gep_for_security_analysis(gep::GEPM, opts::Dict)
    dt = now()
    dt_string = string(
        year(dt), "_", month(dt), "_", day(dt), "_", hour(dt), ":", minute(dt)
    )
    return save_gep_for_security_analysis(
        gep, joinpath(opts["save_path"], "security_analysis_$(dt_string).json")
    )
end

function change_gep_root_path(
    load_path,
    from_path="/vsc-hard-mounts/leuven-data/331/vsc33168/ASoSEPOC/",
    to_path="/home/u0128861/Desktop/ASoSEPOC/",
)
    @load eval(joinpath(load_path, "config.jld2")) dictConfig
    dc = dictConfig
    dc["configFile"] = [
        replace(el, from_path => to_path) for el in dc["configFile"]
    ]
    @save eval(joinpath(load_path, "config.jld2")) dictConfig

    return dictConfig
end

function change_gep_root_path_full(
    topdir,
    from_paths=["/vsc-hard-mounts/leuven-data/331/vsc33168/ASoSEPOC/", ],
    to_path="/home/u0128861/Desktop/ASoSEPOC/"
)
    for (root, dirs, file) in walkdir(topdir)
        for dir in dirs
            dirfl = joinpath(root, dir)
            if isfile(joinpath(dirfl, "config.jld2"))
                for from_path in from_paths
                    change_gep_root_path(dirfl, from_path, to_path)
                end
            end
        end
    end
end

function change_gep_config_files_full(topdir)
    for (root, dirs, file) in walkdir(topdir)
        for dir in dirs
            dirfl = joinpath(root, dir)
            opts_file = joinpath(dirfl, "opts.json")
            config_file = joinpath(dirfl, "config.jld2")
            if isfile(config_file) && isfile(opts_file)
                opts = JSON.parsefile(opts_file)
                opts = options(collect(opts)...)
                config, ~ = param_and_config(opts)
                @load eval(config_file) dictConfig
                dc = dictConfig
                dc["configFile"] = config
                @save eval(config_file) dictConfig
            end
        end
    end
end
