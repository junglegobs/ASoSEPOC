using Plots, StatsPlots, PyPlot, Measures

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
    G = GEPPR.get_set_of_generators(gep)
    GN = [(g, n) for (g, n) in GN if n in N]
    G = [g for g in G if g in first.(GN)]
    STN = GEPPR.get_set_of_nodal_storage_technologies(gep)
    ST = GEPPR.get_set_of_storage_technologies(gep)
    STN = [(st, n) for (st, n) in STN if n in N]
    ST = [st for st in ST if st in first.(STN)]
    Tm = 1:length(T)

    # Get dispatches
    q = gep[:q]
    ls = gep[:ls]

    # Modify / reshape
    q = [
        reduce(+, q[(g, n), Y[1], p, t] for n in N if (g, n) in GN; init=0.0)
        for t in T, g in G
    ]

    ls = [sum(ls[n, Y[1], p, t] for n in N) for t in T]

    if GEPPR.has_storage_technologies(gep)
        sc = gep[:sc]
        sd = gep[:sd]
        e = gep[:e]
        sc = [
            reduce(
                +,
                sc[(st, n), Y[1], p, t] for n in N if (st, n) in STN;
                init=0.0,
            ) for t in T, st in ST
        ]
        sd = [
            reduce(
                +,
                sd[(st, n), Y[1], p, t] for n in N if (st, n) in STN;
                init=0.0,
            ) for t in T, st in ST
        ]
        e = [
            reduce(
                +, e[(st, n), Y[1], p, t] for n in N if (st, n) in STN; init=0.0
            ) for t in T, st in ST
        ]
    end

    # Alter sets accordingly
    if aggregate_conventional
        GD = GEPPR.get_set_of_dispatchable_generators(gep)
        GR = GEPPR.get_set_of_intermittent_generators(gep)
        q_conv = [sum(q[t, i] for i in 1:length(G) if G[i] in GD) for t in Tm]
        q_res = hcat(
            [[q[t, i] for t in Tm] for i in 1:length(G) if G[i] in GR]...
        )
        q = hcat(q_res, q_conv)
        G = vcat(GR..., "Conventional")
    end
    if aggregate_storage && GEPPR.has_storage_technologies(gep)
        sc = sum(sc; dims=2)
        sd = sum(sd; dims=2)
        e = sum(e; dims=2)
        ST = ["Storage"]
    end

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
            layout=Plots.grid(2, 1; heights=[0.3, 0.7]),
        )
    end

    return plt
end

nothing
