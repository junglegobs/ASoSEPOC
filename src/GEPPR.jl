using GEPPR, Suppressor, UnPack, Cbc, Infiltrator
isdefined(Main, :GRB_EXISTS) == false &&
    const GRB_EXISTS = haskey(ENV, "GUROBI_HOME")
isedefined(Main, :CPLEX_EXISTS) == false &&
    const CPLEX_EXISTS = haskey(ENV, "CPLEX_STUDIO_BINARIES")
include(srcdir("util.jl"))

### UTIL
function param_and_config(opts::Dict)
    @unpack optimization_horizon, rolling_horizon = opts
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
        "relativePathMatpowerData" => basename(grid_red_path),
        "reserveType" => opts["operating_reserves_type"],
        "reserveSizingType" => opts["operating_reserves_sizing_type"],
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
    return configFiles, param
end

function optimizer(opts::Dict)
    @unpack rolling_horizon = opts
    is_linear = (opts["unit_commitment_type"] == "none")
    opt_hrzn = opts["optimization_horizon"]
    nT = opt_hrzn[end] - opt_hrzn[1] + 1
    if GRB_EXISTS
        return optimizer_with_attributes(
            Gurobi.Optimizer,
            "TimeLimit" =>
                rolling_horizon ? 100 : nT * (2 + (1 - is_linear) * 2),
            "OutputFlag" => 1,
        )
    elseif CPLEX_EXISTS
        return optimizer_with_attributes(CPLEX.Optimizer)
    else
        return Cbc.Optimizer
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
        load_GEP(save_path)
    else
        @info "Running GEPM..."
        gep = gepm(opts)
        if rolling_horizon == false
            make_JuMP_model!(gep)
            apply_initial_commitment!(gep, opts)
            apply_operating_reserves!(gep, opts)
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

run_GEPPR(opts_vec) = [run_GEPPR(opts) for opts in opts_vec]

# TODO: alternative run_GEPPR which keeps GEPPR the same in between runs
# TODO: so as to save model load time

function apply_initial_commitment!(gep::GEPM, opts::Dict)
    @unpack save_path, optimization_horizon, initial_commitment_data_path = opts
    isempty(initial_commitment_data_path) && return nothing

    z_val = load_GEP(save_path)[:z]
    z = GEPPR.get_online_units_var(gep)
    N, Y, P, T = GEPPR.get_set_of_time_indices(gep)
    GN = GEPPR.get_set_of_nodal_generators(gep)
    t_init = optimization_horizon[1]
    for gn in GN, y in Y, p in P
        fix(z[gn, y, p, t_init], z_val[gn, y, p, t_init]; force=true)
    end
    return nothing
end

function apply_operating_reserves!(gep::GEPM, opts::Dict)
    @unpack include_probabilistic_operating_reserves = opts
    include_probabilistic_operating_reserves == false && return gep

    @info "Getting scenarios..."
    scens = load_scenarios(opts)

    @info "Converting scenarios to quantiles..."
    D⁺, D⁻, P⁺, P⁻, Dmid⁺, Dmid⁻ = scenarios_2_GEPPR(opts, scens)

    @info "Applying to GEPPR..."
    modify_parameter!(gep, "reserveType", "probabilistic")
    modify_parameter!(gep, "reserveSizingType", "given")
    modify_parameter!(gep, "includeReserveActivationCosts", true)
    modify_parameter!(gep, "includeDownwardReserves", true)
    L⁺ = gep[:I, :sets, :L⁺] = 1:n_levels
    L⁻ = gep[:I, :sets, :L⁻] = 1:n_levels
    ORBZ = GEPPR.get_set_of_operating_reserve_balancing_zones(gep)
    gep[:I, :uncertainty, :P⁺] = AxisArray(
        [P⁺[l, t] for l in L⁺, y in Y, p in P, t in T],
        Axis{:Level}(L⁺),
        Axis{:Year}(Y),
        Axis{:Period}(P),
        Axis{:Timestep}(T),
    )
    gep[:I, :uncertainty, :P⁻] = AxisArray(
        [P⁻[l, t] for l in L⁺, y in Y, p in P, t in T],
        Axis{:Level}(L⁺),
        Axis{:Year}(Y),
        Axis{:Period}(P),
        Axis{:Timestep}(T),
    )
    gep[:I, :uncertainty, :D⁺] = AxisArray(
        [D⁺[l, t] for z in ORBZ, l in L⁺, y in Y, p in P, t in T],
        Axis{:Zone}(ORBZ),
        Axis{:Level}(L⁺),
        Axis{:Year}(Y),
        Axis{:Period}(P),
        Axis{:Timestep}(T),
    )
    gep[:I, :uncertainty, :D⁻] = AxisArray(
        [D⁻[l, t] for z in ORBZ, l in L⁺, y in Y, p in P, t in T],
        Axis{:Zone}(ORBZ),
        Axis{:Level}(L⁺),
        Axis{:Year}(Y),
        Axis{:Period}(P),
        Axis{:Timestep}(T),
    )
    return gep
end

function save(gep::GEPM, opts::Dict)
    @unpack save_path = opts
    vars_2_save = get(opts, "vars_2_save", nothing)
    if vars_2_save !== nothing
        gep[:O, :variables] = GEPPR.OrderedDict(
            k => gep[k] for k in vars_2_save
        )
        gep[:O, :constraints] = nothing
        gep[:O, :expressions] = nothing
    end
    return GEPPR.save(gep, save_path)
end
