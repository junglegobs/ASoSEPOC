include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs.(plotsdir(sn), simsdir(sn))

opts = options_diff_days(sn, "days_for_analysis_2022_06_21.csv")[4]
opts["initial_state_of_charge"] = 0.0
opts["time_out"] = 600
opts["save_path"] *= "SOC_init=0.0"
gep = run_GEPPR(opts)
d = save_gep_for_security_analysis(gep, opts)

opts = options_diff_days(sn, "days_for_analysis_2022_06_21.csv")[4]
opts["initial_state_of_charge"] = 0.5
opts["time_out"] = 600
opts["save_path"] *= "SOC_init=0.5"
gep = run_GEPPR(opts)
d = save_gep_for_security_analysis(gep, opts)

# Load the results in each folder
function analyse_UC_edge_effect_results(sn)
    r = Dict()
    for (root, dirs, files) in walkdir(simsdir(sn))
        for file in files
            occursin("security_analysis", file) == false && continue
            occursin("security_analysis_2022_7_1_14:0.json", file) && continue 
            file_path = joinpath(root, file)
            dir_name = splitpath(file_path)[end-1]
            if haskey(r, dir_name)
                @warn "Overwriting result at $dir_name due to more than one JSON file."
            end
            r[dir_name] = JSON.parsefile(file_path)
            
        end
    end

    z = Dict()
    for (k1, v1) in r
        T = string.(sort(parse.(Int, collect(keys(v1)))))
        i = 1
        gen_ids = string.(sort(parse.(Int, collect(keys(v1[T[1]]["gen"])))))
        z[k1] = fill(NaN, length(T), length(gen_ids))
        for t in T
            vals = v1[t]["gen"]
            gen_ids = string.(sort(parse.(Int, collect(keys(vals)))))
            j = 1
            for id in gen_ids
                z[k1][i,j] = vals[id]["z"]
                j += 1
            end
            i += 1
        end
    end

    plt_vec = Plots.Plot[]
    for (k,v) in z
        push!(plt_vec, heatmap(v', title=k, ylab="Unit", xlab="Time", zlab="Commitment", margin=20mm))
    end
    plt = Plots.plot(plt_vec..., size=(800,2000), layout=(length(plt_vec),1))
    Plots.savefig(plt, plotsdir(sn, "commitments.pdf"))
end