include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs(plotsdir(sn))

function scatter_nodal_imbalance(dNLFE, n1, n2)
    x = net_load_forecast_error_dict[n1][:]
    y = net_load_forecast_error_dict[n2][:]
    return Plots.scatter(x, y; xlabel=n1, ylabel=n2, lab="")
end

opts = opts_vec[1]
scens = load_scenarios(opts)
mult = Dict("Load" => 1, "Wind" => -1, "Solar" => -1)
net_load_forecast_error_dict = scenarios_2_net_load_forecast_error(
    opts, scens, mult
)

scatter_nodal_imbalance(net_load_forecast_error_dict, "TIHANGE 1", "TIHANGE 3")

NLFE_vec = Dict(k => v[:] for (k, v) in net_load_forecast_error_dict)
df = DataFrame(NLFE_vec)
temp = mean_and_std.(eachcol(df))
m = first.(temp)
std = last.(temp)
node_names = [n for n in names(df)]
x = 0:2:length(node_names)*2
Plots.bar(
    x,
    m;
    lab="",
    xticks=(x, node_names),
    rotation=90,
    margin=10mm,
    ylabel="Mean imbalance [MWh]",
)
Plots.savefig(plotsdir(sn, "mean_imbalance.png"))
# Plots.bar(m; yerror=std, xticks=[n for n in names(df)])

y_min = minimum.(eachcol(df))
y_max = maximum.(eachcol(df))
StatsPlots.groupedbar(
    hcat(y_min, y_max);
    lab="",
    bar_position=:stack,
    ylabel="Imbalance range [MWh]",
    xticks=(x, node_names),
    rotation=90,
    margin=10mm,
)
Plots.savefig(plotsdir(sn, "imbalance_range.png"))
