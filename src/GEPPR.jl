using GEPPR, Suppressor, UnPack, Cbc, Infiltrator
isdefined(Main, :GRB_EXISTS) == false &&
    const GRB_EXISTS = haskey(ENV, "GUROBI_HOME")
GRB_EXISTS && using Gurobi
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
            apply_initial_commitment!(opts, gep)
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

function apply_initial_commitment!(opts, gep)
    @unpack save_path, optimisation_horizon = opts
    return gep_init = load_GEP(save_path)
end

function save(gep::GEPM, opts::Dict)
    @unpack save_path = opts
    vars_2_save = get(opts, "vars_2_save", nothing)
    if vars_2_save !== nothing
        gep[:O, :variables] = GEPPR.OrderedDict(k => gep[k] for k in vars_2_save)
        gep[:O, :constraints] = nothing
        gep[:O, :expressions] = nothing
    end
    return GEPPR.save(gep, save_path)
end
