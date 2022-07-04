include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs.(plotsdir(sn), simsdir(sn))
dyfile = "days_for_analysis.csv"

opts_vec = options_diff_days(sn, dyfile)
opts_vec = [
    merge(
        opts,
        Dict(
            "time_out" => 1200,
            "initial_state_of_charge" => 0.5,
            "upward_reserve_levels_included_in_redispatch" => 1:10,
            "downward_reserve_levels_included_in_redispatch" => 1:10,
        ),
    ) for opts in opts_vec
]
opts_vec = vcat(
    [
        merge(
            opts,
            Dict(
                "absolute_limit_on_nodal_imbalance" => false,
                "save_path" => opts["save_path"] * "_AbsIm=false",
            ),
        ) for opts in opts_vec
    ]...,
    [
        merge(
            opts,
            Dict(
                "absolute_limit_on_nodal_imbalance" => true,
                "save_path" => opts["save_path"] * "_AbsIm=true",
            ),
        ) for opts in opts_vec
    ]...,
)
gep_vec = run_GEPPR(opts_vec)
d_vec = [save_gep_for_security_analysis(gep, opts) for opts in opts_vec]

# Some short analysis
function analyse_interaction_selected_days()
    df = DataFrame(
        "Name" => String[],
        "Month_Day" => String[],
        "AbsIm" => Bool[],
        "Load shedding [MWh]" => Float64[],
        "Reserve Shedding [GWh]" => Float64[],
    )
    dy4anl = CSV.read(datadir("pro", dyfile), DataFrame)
    for subdir in readdir(simsdir(sn))
        subdirfl = joinpath(dir, subdir)
        isdir(subdirfl) == false && continue
        change_gep_root_path(subdirfl)
        change_gep_root_path(subdirfl, "/data/leuven/331/vsc33168/ASoSEPOC")
        opts = JSON.parsefile(joinpath(subdirfl, "opts.json"))
        gep = load_GEP(subdirfl)
        push!(
            df,
            [
                subdir,
                month_day(opts),
                opts["absolute_limit_on_nodal_imbalance"],
                sum(gep[:loadShedding]),
                sum(gep[:rsL⁺]),
            ],
        )
    end
    CSV.write(simsdir(sn, "summary.csv"), df)
    return df
end

df = analyse_interaction_selected_days()