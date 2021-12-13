using Gurobi, GEPPR, Suppressor
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
    param = @suppress Dict{String,Any}(
        "optimizer" => optimizer_with_attributes(
            Gurobi.Optimizer,
            "TimeLimit" => 1_200,
            "OutputFlag" => 1,
        ),
        "unitCommitmentConstraintType" => opts["unit_commitment_type"],
        "relativePathTimeSeriesCSV" => "timeseries.csv",
        "relativePathMatpowerData" => if opts["include_storage"]
            basename(grid_red_path)
        else
            basename(grid_wo_store_red_path)
        end,
        "reserveType" => opts["operating_reserves_type"],
        "reserveSizingType" => opts["operating_reserves_sizing_type"],
        "optimizationHorizon" => Dict(
            "start" => [1,1,opts["optimization_horizon"][1]],
            "end" => [1,1,opts["optimization_horizon"][2]]
        )
    )
    return configFiles, param
end

function gepm(opts::Dict)
    cf, param = param_and_config(opts)
    gep = GEPM(cf, param)
    return gep
end

function run_GEPPR(opts::Dict)
    gep = gepm(opts)
    make_JuMP_model!(gep)
    optimize_GEP_model!(gep)
    return gep
end
