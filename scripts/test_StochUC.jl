include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)

opts_vec = options_3_days(sn)
gep_vec = run_GEPPR(opts_vec)
map(
    i -> save_gep_for_security_analysis(gep_vec[i], opts_vec[i]),
    eachindex(opts_vec),
)
