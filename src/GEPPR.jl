using GEPPR, Suppressor, UnPack, Cbc, Infiltrator, JLD2, JuMP, AxisArrays
include(srcdir("util.jl"))

### UTIL
function param_and_config(opts::Dict)
    @unpack optimization_horizon, rolling_horizon, include_downward_reserves =
        opts
    is_linear = (opts["unit_commitment_type"] == "none")
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
    if opts["include_storage"]
        push!(configFiles, joinpath(GEPPR_dir, "storage.yaml"))
    end
    param = @suppress Dict{String,Any}(
        "optimizer" => optimizer(opts),
        "unitCommitmentConstraintType" => opts["unit_commitment_type"],
        "relativePathTimeSeriesCSV" => if opts["include_storage"]
            "timeseries.csv"
        else
            "timeseries_wo_storage.csv"
        end,
        "includeDownwardReserves" => include_downward_reserves,
        "relativePathMatpowerData" => basename(grid_red_path),
        "optimizationHorizon" => Dict(
            "start" => [1, 1, optimization_horizon[1]],
            "end" => [1, 1, optimization_horizon[end]],
        ),
        "imposePeriodicityConstraintOnStorage" =>
            rolling_horizon ? false : true,
    )
    if length(optimization_horizon[1]:optimization_horizon[end]) > 100 &&
        is_linear == false &&
        rolling_horizon == false
        error(
            "Optimisation length too long for unit commitment model, consider setting `rolling_horizon = true`.",
        )
    end
    if opts["copperplate"] == true
        param["forceCopperPlateModel"] = true
    end
    return configFiles, param
end

function optimizer(opts::Dict)
    if GRB_EXISTS
        return optimizer_with_attributes(
            Gurobi.Optimizer, "TimeLimit" => time_out(opts), "OutputFlag" => 1
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

function run_GEPPR(opts::Dict)
    @unpack save_path, rolling_horizon = opts
    gep = if isdir(save_path) && isfile(joinpath(save_path, "data.csv"))
        @info "GEPM found at $(save_path), loading..."
        load_GEP(opts, save_path)
    else
        @info "Running GEPM (save path is $(save_path))..."
        gep = gepm(opts)
        if rolling_horizon == false
            apply_operating_reserves!(gep, opts)
            @info "Building JuMP model..."
            make_JuMP_model!(gep)
            apply_initial_commitment!(gep, opts)
            constrain_reserve_shedding!(gep, opts)
            optimize_GEP_model!(gep)
            save_optimisation_values!(gep)
        else
            run_rolling_horizon(gep)
        end
        if isempty(save_path) == false
            save(gep, opts)
        else
            @warn "Not saving GEP model since $save_path already exists."
        end
        gep
    end
    return gep
end

run_GEPPR(opts_vec) = [
    try
        run_GEPPR(opts)
    catch
        @warn "Optimisation failed"
    end for opts in opts_vec
]

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

# TODO: alternative run_GEPPR which keeps GEPPR the same in between runs
# TODO: so as to save model load time

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

    gep[:M, :constraints, :reserveSheddingLimit] = @constraint(
        gep.model,
        [z = ORBZ, y in Y, p in P, t = T],
        sum(rsL⁺[n, l, y, p, t] for n in ORBZ2N[z], l in L⁺) /
        sum(D⁺[z, l, y, p, t] for z in ORBZ, l in L⁺) <= reserve_shedding_limit
    )
    return gep
end

function save(gep::GEPM, opts::Dict)
    @unpack save_path = opts
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
    return GEPPR.save(gep, save_path)
end

"""
    save_gep_for_security_analysis(gep::GEPM)

Saves data in the format: hour -> generator (with associated bus) -> value
"""
function save_gep_for_security_analysis(gep::GEPM, path::String)
    q = gep[:q]
    z = gep[:z]
    ls = gep[:loadShedding]
    UC_results = Dict{Integer,Dict}()
    N, Y, P, T = GEPPR.get_set_of_nodes_and_time_indices(gep)
    GDN = GEPPR.get_set_of_nodal_dispatchable_generators(gep)
    GRN = GEPPR.get_set_of_nodal_intermittent_generators(gep)
    y, p = first.([Y, P])
    for t in T
        UC_results[t] = Dict(
            "gen" => Dict(
                (g, n) => Dict(
                    "q" => q[(g, n), y, p, atval(t, typeof(q))],
                    "z" => z[(g, n), y, p, atval(t, typeof(z))],
                ) for (g, n) in GDN
            ),
            "res" => Dict(
                (g, n) => Dict("q" => q[(g, n), y, p, atval(t, typeof(q))])
                for (g, n) in GRN
            ),
            "load_shed" => Dict(
                n => ls[n,y,p,atval(t, typeof(ls))]
                for n in N
            )
        )
    end
    @save eval(path) UC_results
    return UC_results
end

function atval(idx, T::Type)
    if T <: AxisArray
        return atvalue(idx)
    else
        return idx
    end
end

function save_gep_for_security_analysis(gep::GEPM, opts::Dict)
    return save_gep_for_security_analysis(
        gep, joinpath(opts["save_path"], "security_analysis.jld2")
    )
end
