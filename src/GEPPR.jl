using Gurobi, GEPPR, Suppressor, UnPack
include(srcdir("util.jl"))

### UTIL
function param_and_config(opts::Dict)
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
    is_linear = (opts["unit_commitment_type"] == "none")
    opt_hrzn = opts["optimization_horizon"]
    nT = opt_hrzn[end] - opt_hrzn[1] + 1
    param = @suppress Dict{String,Any}(
        "optimizer" => optimizer_with_attributes(
            Gurobi.Optimizer,
            "TimeLimit" => nT * (2 + (1 - is_linear) * 2),
            "OutputFlag" => 1,
        ),
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
            "start" => [1, 1, opts["optimization_horizon"][1]],
            "end" => [1, 1, opts["optimization_horizon"][end]],
        ),
    )
    return configFiles, param
end

function gepm(opts::Dict)
    cf, param = param_and_config(opts)
    gep = GEPM(cf, param)
    return gep
end

function run_GEPPR(opts::Dict)
    @unpack save_path = opts
    gep = if isdir(save_path) && isfile(joinpath(save_path, "data.csv"))
        @info "GEPM found at $(save_path), loading..."
        load_GEP(save_path)
    else
        @info "Running GEPM..."
        gep = gepm(opts)
        make_JuMP_model!(gep)
        optimize_GEP_model!(gep)
        save_optimisation_values!(gep) # In case not saved due to TimeOut limit
        save(gep, opts)
        gep
    end
    return gep
end


run_GEPPR(opts_vec) = [run_GEPPR(opts) for opts in opts_vec]

# TODO: alternative run_GEPPR which keeps GEPPR the same in between runs
# TODO: so as to save model load time


function save(gep::GEPM, opts::Dict)
    @unpack save_path = opts
    return GEPPR.save(gep, save_path)
end
