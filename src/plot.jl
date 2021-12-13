using Plots, PyPlot, Measures

function plot_dispatch(
    gep::GEPM,
    p::Int;
    plot_state_of_charge=true,
    aggregate_conventional=true,
    aggregate_storage=true,
    N=GEPPR.get_set_of_nodes_and_time_indices(gep)[1],
    Y=GEPPR.get_set_of_nodes_and_time_indices(gep)[2],
    T=GEPPR.get_set_of_nodes_and_time_indices(gep)[4],
)
    pyplot()

    # Get sets
    GN = GEPPR.get_set_of_nodal_generators(gep)
    G = first.(GN)
    STN = GEPPR.get_set_of_nodal_storage_technologies(gep)
    ST = first.(STN)

    # Get dispatches
    q = gep[:q]
    ls = gep[:ls]

    # Modify / reshape
    q = [
        sum(q[(g, n), Y[1], p, t] for n in N if (g, n) in GN) for t in T, g in G
    ]
    q = aggregate_conventional ? sum(q; dims=2) : q
    ls = [sum(ls[n, Y[1], p, t] for n in N) for t in T]

    if GEPPR.has_storage_technologies(gep)
        sc = gep[:sc]
        sd = gep[:sd]
        e = gep[:e]
        sc = [
            sum(
                sc[(st, parse(Int, n)), Y[1], p, t] for
                n in N if (st, parse(Int, n)) in STN
            ) for t in T, st in ST
        ]
        sd = [
            sum(
                sd[(st, parse(Int, n)), Y[1], p, t] for
                n in N if (st, parse(Int, n)) in STN
            ) for t in T, st in ST
        ]
        e = [
            sum(
                e[(st, parse(Int, n)), Y[1], p, t] for
                n in N if (st, parse(Int, n)) in STN
            ) for t in T, st in ST
        ]
        if aggregate_storage
            sc = sum(sc; dims=2)
            sd = sum(sd; dims=2)
            e = sum(e; dims=2)
        end
    end

    # Alter sets accordingly
    G = aggregate_conventional ? ["Conventional"] : first.(GN)
    ST = aggregate_storage ? ["Storage"] : first.(STN)

    # Plot
    plt = Plots.plot(; size=(1200, 800), margin=10 * mm)
    if GEPPR.has_storage_technologies(gep)
        StatsPlots.groupedbar!(
            plt,
            T,
            hcat(ls, q, sd);
            label=hcat("Load shedding", G..., (ST .* " discharging")...),
            bar_position=:stack,
            bar_width=1.0,
            lw=0,
            ylab="Generation [GW]",
            xlab="Time [h]",
            legend=:outerright,
            xlims=(T[1], T[end]),
        )

        StatsPlots.groupedbar!(
            plt,
            T,
            -sc;
            label=hcat((ST .* " charging")...),
            bar_position=:stack,
            bar_width=1.0,
            lw=0,
            fillcolor=:red,
            fillalpha=0.5,
        )
    else
        StatsPlots.groupedbar!(
            plt,
            T,
            hcat(ls, q);
            label=hcat("Load shedding", G...),
            bar_position=:stack,
            bar_width=1.0,
            lw=0,
            ylab="Generation [GW]",
            xlab="Time [h]",
            legend=:outerright,
        )
    end

    # Plot the load
    D = GEPPR.get_demand(gep)
    Plots.plot!(
        plt, T, [sum(D[n, Y[1], p, t] for n in N) for t in T]; lab="", lc=:black
    )

    # Plot the state of charge
    if GEPPR.has_storage_technologies(gep) && plot_state_of_charge
        plt = Plots.plot(
            Plots.plot(
                T,
                e;
                lw=2,
                seriestype=:steppost,
                lab=hcat(ST...),
                ylabel="SOC [GWh]",
                margin=10 * mm,
                xlims=(T[1], T[end]),
            ),
            plt;
            layout=grid(2, 1; heights=[0.3, 0.7]),
        )
    end

    return plt
end

nothing
