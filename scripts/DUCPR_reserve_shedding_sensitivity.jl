include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)

opts_vec = options_3_days(sn)
maps!(i -> opts_vec[i]["vars_2_save"] = [:z,:q,:ls,:rsl⁺], eachindex(opts_vec))
