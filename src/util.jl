"""
	mkrootdirs(dir::String)

Recursively creates directories if these do not exist yet.
"""
function mkrootdirs(dir::String)
    dir_vec = splitpath(dir)
    dd = first(dir_vec)
    for d in dir_vec[2:end]
        dd = joinpath(dd, d)
        if isdir(dd) == false
            mkdir(dd)
        end
    end
end

script_name(str) = splitext(splitdir(str)[2])[1]

function Base.parse(::Type{UnitRange{T}}, str::AbstractString) where T<:Integer
    split_str = split(str,":")
    return parse(T, split_str[1]), parse(T, split_str[2])
end

month_day(opts::Dict) = split(opts["load_scenario_data_paths"], "1000SC_BELDERBOS_load_")[end]

# DIRs
simsdir(args...) = datadir("sims", args...)

# PATHS
grid_path = datadir("pro", "grid.json")
grid_w_store_ts_path = datadir("pro", "grid_w_store_ts.json")
grid_red_path = datadir("pro", "GEPPR", "grid_red.json")
grid_wo_store_path = datadir("pro", "grid_wo_storage.json")
grid_wo_store_red_path = datadir("pro", "GEPPR", "grid_red_wo_storage.json")
scendir(args...) = datadir("raw", "Forecast_Error_Scenarios", args...)
