include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs(plotsdir(sn))

opts_vec = options_diff_days()
df = CSV.read(datadir("pro", "days_for_analysis.csv"), DataFrame)

for i in eachindex(opts_vec)
    opts = opts_vec[i]
    day = df[i,"days"]
    @info "Plotting reserve requirements for day $day..."
    scens = load_scenarios(opts)
    D⁺, D⁻, P⁺, P⁻, Dmid⁺, Dmid⁻ = scenarios_2_GEPPR(opts, scens)
    pl = Plots.plot(
        hcat(sum(D⁺, dims=1)', -sum(D⁻, dims=1)'),
        lab=["Upward reserve requirement" "Downward reserve requirement"],
        ylabel="MW",
        xlabel="Hour"
    )
    Plots.savefig(pl, plotsdir(sn, "day=$day.pdf"))
end
