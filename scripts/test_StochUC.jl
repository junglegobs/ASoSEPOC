include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)

opts_vec = options_3_days()
gep_vec = run_GEPPR(opts_vec)
gep_vec = run_GEPPR(opts_vec[2])
save_fo
