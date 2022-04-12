include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)

df = CSV.read(datadir("pro", "days_for_analysis.csv"), DataFrame)
opts_vec = options_3_days(sn)
map(x -> rm(x["save_path"]; force=true, recursive=true), opts_vec)
gep_vec = run_GEPPR(opts_vec)

# Plot
for i in 1:length(opts_vec)
    gep = gep_vec[i]
    opts = opts_vec[i]
    plt = plot_dispatch(gep, 1)
    Plots.savefig(plt, joinpath(opts["save_path"], "dispatch.pdf"))
    plt = plot_reserves_simple(gep, 1)
    Plots.savefig(plt, joinpath(opts["save_path"], "reserves.pdf"))
end
