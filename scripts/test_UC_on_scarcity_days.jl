include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)

df = CSV.read(datadir("pro", "days_for_analysis.csv"), DataFrame)
opts = options(
    "include_storage" => false,
    "include_operating_reserves" => false,
    "operating_reserves_sizing_type" => "given",
    "operating_reserves_type" => "none",
)
opts_vec = [
    merge(
        opts,
        Dict(
            "optimization_horizon" => parse(UnitRange{Int}, df[i,"timesteps"]),
            "save_path" => datadir("sims", "$(sn)_$(df[i,"days"])"),
        ),
    ) for i in 1:size(df, 1)
]
gep_vec = run_GEPPR(opts_vec)

# Plot
for i in 1:length(opts_vec)
    gep = gep_vec[i]
    opts = opts_vec[i]
    plt = plot_dispatch(gep, 1)
    Plots.savefig(plt, joinpath(opts["save_path"], "dispatch.pdf"))
end
