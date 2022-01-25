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

function parse(::Type{UnitRange{T}}, str::AbstractString) where T<:Integer
    split_str = split(str,":")
    return parse(T, split_str[1]), parse(T, split_str[2])
end

# PATHS
grid_path = datadir("pro", "grid.json")
grid_red_path = datadir("pro", "GEPPR", "grid_red.json")
grid_wo_store_path = datadir("pro", "grid_wo_storage.json")
grid_wo_store_red_path = joinpath("pro", "GEPPR", "grid_red_wo_storage.json")
