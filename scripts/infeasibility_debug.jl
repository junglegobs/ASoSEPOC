include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)

# No network, no UC, no network redispatch
opts_vec = options_3_days(sn)
opts_vec = [
    merge(opts, Dict(
        "reserve_shedding_limit" => 0.0,
        "unit_commitment_type" => "none",
        "vars_2_save" => [:z, :q, :ls, :rsL⁺],
        "copperplate" => true
    ))
]
gep_vec = run_GEPPR(opts_vec)
# Day 41 is still broken!!! Hmmmm...

# No UC
opts_vec = options_3_days(sn)
opts_vec = [
    merge(opts, Dict(
        "reserve_shedding_limit" => 0.0,
        "unit_commitment_type" => "none",
        "vars_2_save" => [:z, :q, :ls, :rsL⁺],
    ))
]
gep_vec = run_GEPPR(opts_vec)
