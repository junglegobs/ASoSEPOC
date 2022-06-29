include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs(joinpath(datadir("sims"), sn))

opts_vec = options_diff_days(sn)

# Only analyse particular source of uncertainty
function plot_net_load_forecast_uncertainty(opts, scens, buses=String[])
    scens = load_scenarios(opts)

    # buses = ["GOUY"]
    buses = String[]
    buses_str = reduce(*, buses .* "_")
    for scens_cp in vcat(scens, [Dict(k => v) for (k, v) in scens])
        unc_srcs = reduce(*, collect(keys(scens_cp)) .* "_")[1:(end - 1)]
        plt_name = length(buses) > 0 ? buses_str * unc_srcs : unc_srcs
        @info "Plotting $unc_srcs..."

        # Get net load forecast error per node
        mult = Dict("Load" => -1, "Wind" => 1, "Solar" => 1)
        net_load_forecast_error_dict = scenarios_2_net_load_forecast_error(
            opts, scens_cp, mult
        )
        if length(buses) > 0
            net_load_forecast_error_dict = Dict(
                k => v for (k,v) in net_load_forecast_error_dict if k in buses
            )
        end

        # Sum up uncertainty over entire network
        total_NLFE = sum(v for (k, v) in net_load_forecast_error_dict)

        # Plot timeseries and bounds
        y = mean(total_NLFE; dims=2)[:]
        ymax = [quantile(total_NLFE[i, :], 0.95) for i in 1:size(total_NLFE, 1)]
        ymin = [quantile(total_NLFE[i, :], 0.05) for i in 1:size(total_NLFE, 1)]
        Plots.plot(
            y;
            ribbon=(y .- ymin, ymax .- y),
            ylab="Net load forecast error (90% CI)",
            title=unc_srcs,
        )
        Plots.savefig(
            joinpath(datadir("sims", sn, "uncertainty_sources=$(plt_name).png"))
        )
    end
end

# plot_net_load_forecast_uncertainty(opts_vec[i], )
