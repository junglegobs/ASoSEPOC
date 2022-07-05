using Plots, StatsPlots, PyPlot, Measures

function plot_dispatch(
    gep::GEPM,
    p::Int;
    plot_state_of_charge=true,
    aggregate_conventional=true,
    aggregate_renewable=true,
    aggregate_storage=true,
    N=GEPPR.get_set_of_nodes_and_time_indices(gep)[1],
    Y=GEPPR.get_set_of_nodes_and_time_indices(gep)[2],
    T=GEPPR.get_set_of_nodes_and_time_indices(gep)[4],
)
    pyplot()

    # Get sets
    GN = GEPPR.get_set_of_nodal_generators(gep)
    GRN = GEPPR.get_set_of_nodal_intermittent_generators(gep)
    GDN = GEPPR.get_set_of_nodal_dispatchable_generators(gep)
    G = GEPPR.get_set_of_generators(gep)
    GN = [(g, n) for (g, n) in GN if n in N]
    GDN = [(g, n) for (g, n) in GDN if n in N]
    GRN = [(g, n) for (g, n) in GRN if n in N]
    G = [g for g in G if g in first.(GN)]
    GD = [g for g in G if g in first.(GDN)]
    GR = [g for g in G if g in first.(GRN)]

    STN = GEPPR.get_set_of_nodal_storage_technologies(gep)
    ST = GEPPR.get_set_of_storage_technologies(gep)
    STN = [(st, n) for (st, n) in STN if n in N]
    ST = [st for st in ST if st in first.(STN)]
    Tm = 1:length(T)

    # Get dispatches and load
    q = gep[:q]
    ls = gep[:loadShedding]
    D = GEPPR.get_demand(gep)
    D = [sum(D[n, Y[1], p, t] for n in N) for t in T]

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
        sc = Float64[
            reduce(
                +,
                sc[(st, n), Y[1], p, t] for n in N if (st, n) in STN;
                init=0.0,
            ) for t in T, st in ST
        ]
        sd = Float64[
            reduce(
                +,
                sd[(st, n), Y[1], p, t] for n in N if (st, n) in STN;
                init=0.0,
            ) for t in T, st in ST
        ]
        e = Float64[
            reduce(
                +, e[(st, n), Y[1], p, t] for n in N if (st, n) in STN; init=0.0
            ) for t in T, st in ST
        ]
    end

    # Alter sets accordingly
    if aggregate_conventional || aggregate_renewable
        if aggregate_conventional
            q_conv = [
                reduce(+, q[t, i] for i in 1:length(G) if G[i] in GD; init=0.0)
                for t in Tm
            ]
        else
            q_conv = hcat(
                [[q[t, i] for t in Tm] for i in 1:length(G) if G[i] in GD]...
            )
        end
        if aggregate_renewable
            q_res = hcat(
                [
                    [
                        reduce(
                            +,
                            q[t, i] for i in 1:length(G) if G[i] == g;
                            init=0.0,
                        ) for t in Tm
                    ] for g in GR
                ]...,
            )
        else
            q_res = hcat(
                [[q[t, i] for t in Tm] for i in 1:length(G) if G[i] in GR]...
            )
        end
        q = hcat(q_res, q_conv)
        GRl = vcat([g for (g, n) in GN if n in N && g in GR]...)
        GRs = unique(GRl)
        GDl = vcat([g for (g, n) in GN if n in N && g in GD]...)
        GDs = ["Conventional"]
        G = String[]
        if aggregate_renewable
            push!(G, GRs...)
        else
            push!(G, GRl...)
        end
        if aggregate_conventional
            push!(G, GDs...)
        else
            push!(G, GDl...)
        end
    end
    if aggregate_storage && GEPPR.has_storage_technologies(gep)
        sc = sum(sc; dims=2)
        sd = sum(sd; dims=2)
        e = sum(e; dims=2)
        ST = isempty(e) ? String[] : ["Storage"]
    end

    # Plot
    plt = Plots.plot(; size=(900, 600), margin=10 * mm)
    if GEPPR.has_storage_technologies(gep)
        StatsPlots.groupedbar!(
            plt,
            T .+ 0.5,
            hcat(ls, q, sd);
            label=hcat("Load shedding", G..., (ST .* " discharging")...),
            bar_position=:stack,
            bar_width=1.0,
            lw=0,
            ylab="Generation [MW]",
            xlab="Time [h]",
            legend=:outerright,
            xlims=(T[1], T[end] + 1),
            # ylims=(0, maximum(D) * 1.1),
        )

        StatsPlots.groupedbar!(
            plt,
            T .+ 0.5,
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
            T .+ 0.5,
            hcat(ls, q);
            label=hcat("Load shedding", G...),
            bar_position=:stack,
            bar_width=1.0,
            lw=0,
            ylab="Generation [MW]",
            xlab="Time [h]",
            legend=:outerright,
            xlims=(T[1], T[end] + 1),
        )
    end

    # Plot the load
    Plots.plot!(plt, T, D; lab="Demand", lc=:black, line=:steppost, lw=2)

    # Plot the load net of node injection if only one node
    if length(N) == 1
        inj = gep[:inj]
        inj = [inj[N[1], Y[1], p, t] for t in T]
        Plots.plot!(
            plt,
            T,
            D + reshape(inj, :, 1);
            lab="Demand - injection",
            lc=:black,
            line=:steppost,
            ls=:dash,
            lw=2,
        )
    end

    # Plot the state of charge
    if GEPPR.has_storage_technologies(gep) && plot_state_of_charge
        plt = Plots.plot(
            Plots.plot(
                T,
                e;
                lw=2,
                seriestype=:steppost,
                lab=hcat(ST...),
                ylabel="SOC [MWh]",
                margin=10 * mm,
                xlims=(T[1], T[end]),
            ),
            plt;
            layout=Plots.grid(2, 1; heights=[0.3, 0.7]),
        )
    end

    return plt
end

function plot_reserves_simple(
    gep::GEPM,
    p::Int;
    Y=GEPPR.get_set_of_nodes_and_time_indices(gep)[2],
    T=GEPPR.get_set_of_nodes_and_time_indices(gep)[4],
)
    pyplot()

    # Get sets
    ORBZ = GEPPR.get_set_of_operating_reserve_balancing_zones(gep)
    L⁺ = GEPPR.get_set_of_upward_reserve_levels(gep)
    L⁻ = GEPPR.get_set_of_downward_reserve_levels(gep)
    Tm = 1:length(T)

    # Get reserve provision and aggregate
    rL⁺ = sum(gep[:rL⁺].data; dims=(1, 2, 3, 4))[:]
    rL⁻ = sum(gep[:rL⁻].data; dims=(1, 2, 3, 4))[:]
    rsL⁺ = sum(gep[:rsL⁺].data; dims=(1, 2, 3, 4))[:]
    D⁺ = gep[:I][:uncertainty][:D⁺]
    D⁺ = [sum(D⁺[z, l, y, p, t] for z in ORBZ, l in L⁺, y in Y) for t in T]
    D⁻ = gep[:I][:uncertainty][:D⁻]
    D⁻ = [sum(D⁻[z, l, y, p, t] for z in ORBZ, l in L⁻, y in Y) for t in T]

    # Plot
    ymax = max(D⁺..., D⁻...)
    plt_up = StatsPlots.groupedbar(
        T,
        hcat(rsL⁺, rL⁺);
        color=[:red :blue],
        lab=["Shedding" "Provision"],
        ylabel="Power [MW]",
        xlab="Time [h]",
        bar_width=1.0,
        bar_position=:stack,
        lw=0.0,
        ylims=(0, ymax),
        legend=:topleft,
    )
    Plots.plot!(
        plt_up,
        T,
        D⁺;
        lc=:black,
        lw=2,
        line=:stepmid,
        lab="Upward reserve demand",
    )

    plt_down = StatsPlots.bar(
        T,
        -rL⁻;
        color=:blue,
        lab="Provision",
        ylabel="- Power [MW]",
        xlab="",
        xticks=:none,
        bar_width=1.0,
        # bar_position=:stack,
        lw=0.0,
        ylims=(-ymax, 0),
    )
    Plots.plot!(
        plt_down,
        T,
        -D⁻;
        lc=:black,
        lw=2,
        line=:stepmid,
        lab="Downward reserve demand",
        legend=:bottomright,
    )
    plt_all = Plots.plot(
        plt_up, plt_down; layout=(2, 1), size=(800, 500), xlims=extrema(T)
    )
    return plt_all
end

function plot_commitment(
    gep::GEPM,
    p::Int;
    N=GEPPR.get_set_of_nodes_and_time_indices(gep)[1],
    Y=GEPPR.get_set_of_nodes_and_time_indices(gep)[2],
    T=GEPPR.get_set_of_nodes_and_time_indices(gep)[4],
)
    @assert length(Y) == 1
    z = gep[:z]
    GN = GEPPR.get_set_of_nodal_dispatchable_generators(gep)
    GN = [(g,n) for (g,n) in GN if n in N]
    z = [z[(g, n), Y[1], p, t] for (g, n) in GN, t in T]
    ytl = first.(GN)
    return Plots.heatmap(
        z;
        xlab="Time [h]",
        yticks=(eachindex(ytl), ytl),
        legend=:none,
        title="Commitment [Black=off]",
    )
end

nothing
