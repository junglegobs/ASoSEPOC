include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs(plotsdir(sn))
mkrootdirs(simsdir(sn))

function sum_z(gep::GEPM)
    z = gep[:z]
    return sum(z.data, dims=(1,2,3))[:]
end

opts = options_diff_days(sn)[1]
append!(opts["vars_2_save"], [:w, :v])
TH = opts["optimization_horizon"]
T = [0,71]
opts["optimization_horizon"] = (TH[1] + T[1], TH[1] + T[end])
opts["initial_state_of_charge"] = 0.0
opts["operating_reserves_type"] = "none"
opts["time_out"] = 300
sp = opts["save_path"]
opts["save_path"] = sp * "_$(T)_no_reserves"
gep = run_GEPPR(opts)

z = Dict("T = 72" => sum_z(gep))
opts["sc"] = gep[:sc]
opts["sd"] = gep[:sd]

for T in [[0,8], [0,12], [0, 23], [0, 47]]
    opts["optimization_horizon"] = (TH[1] + T[1], TH[1] + T[end])
    opts["save_path"] = sp * "_$(T)_no_reserves"
    gep = run_GEPPR(opts)
    z["T = $(T[end])"] = sum_z(gep)
    GC.gc()
end