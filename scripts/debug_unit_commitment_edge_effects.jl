include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs(plotsdir(sn))
mkrootdirs(simsdir(sn))

for T in [[0,8], [0,12], [0, 23]]
    opts = options_diff_days(sn)[i]
    append!(opts["vars_2_save"], [:w, :v])
    TH = opts["optimization_horizon"]
    opts["optimization_horizon"] = (TH[1] + T[1], TH[1] + T[end])
    opts["initial_state_of_charge"] = 0.0
    opts["operating_reserves_type"] = "none"
    opts["time_out"] = 120
    opts["save_path"] *= "$(T)_no_reserves"
    gep_no_res = run_GEPPR(opts)

    opts["save_path"] = replace(opts["save_path"], "_no" => "")
    opts["operating_reserves_type"] = "probabilistic"
    gep_res = run_GEPPR(opts)

    GC.gc()

    @info "T = $(opts["optimization_horizon"])"
    for gep in [gep_no_res, gep_res]
        @info "Reserves: $(GEPPR.get_reserve_type(gep))"
        for s in [:z,:w,:v]
            sv = gep[s]
            sv_sum = sum(sv.data, dims=(1,2,3))[:]
            @info "Sum of $(s) for last 4 time steps: $sv_sum"
        end 
    end
end