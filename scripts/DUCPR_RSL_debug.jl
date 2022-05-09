include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs(plotsdir(sn))

opts = options_diff_days(sn)[4]
rm(opts["save_path"]; force=true, recursive=true)
opts["unit_commitment_type"] = "none"
opts["initial_state_of_charge"] = 0.0
opts["reserve_provision_cost"] = 200.0
gep = run_GEPPR(opts)

@show opts["reserve_provision_cost"]
@show sum(gep[:rsL⁺])
@show sum(gep[:loadShedding])
nothing


# opts_vec = [
#     merge(
#         opts,
#         Dict(
#             "unit_commitment_type" => "none",
#             "include_storage" => false,
#             "save_path" => joinpath(opts["save_path"], "simplest"),
#         ),
#     )
#     merge(
#         opts,
#         Dict(
#             "unit_commitment_type" => "none",
#             "save_path" => joinpath(opts["save_path"], "simpler"),
#         ),
#     )
#     merge(
#         opts,
#         Dict(
#             "unit_commitment_type" => "none",
#             "save_path" => joinpath(opts["save_path"], "full"),
#         ),
#     )
# ]
# gep_vec = run_GEPPR(opts_vec[1:2])
