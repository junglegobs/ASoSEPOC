include(joinpath(@__DIR__, "..", "intro.jl"))
sn = script_name(@__FILE__)
mkrootdirs(plotsdir(sn))
mkrootdirs(simsdir(sn))

opts = options_diff_days(sn)[1]
opts["initial_state_of_charge"] = 0.0
# opts["operating_reserves_type"] = "none"
opts["time_out"] = 120
gep = run_GEPPR(opts)
d = save_gep_for_security_analysis(gep, opts)

df = overall_network_results(gep)
df[:,"Load - net generation - load shed"]
CSV.write(joinpath(opts["save_path"], "aggregate_results.csv"), df)

# pfl is from Efthymios' power flow which I'm not pushing to github
function line_flow_comparison(gep, pfl, t)
    f_1 = gep[:f][:,:,:,t]
    # Im = GEPPR.get_incidence_matrix(gep)
    Im = calc_basic_incidence_matrix(gep.networkData)
    N, Y, P, Y = GEPPR.get_set_of_nodes_and_time_indices(gep)
    L = GEPPR.get_set_of_lines(gep)
    L2Lidx = GEPPR.get_line_indices(gep)
    node_index_2_node_name = Dict(
        v["index"] => v["string"] for (k,v) in gep.networkData["bus"]
    )

    my_flow = Float64[]
    ef_flow = Float64[]
    lidx_vec = Int64[]
    t_br = Int64[]
    f_br = Int64[]
    t_br_str = String[]
    f_br_str = String[]

    for l in L
        lidx = L2Lidx[l]
        br_vec = abs.(Im[lidx,:])
        n1, n2 = findall(br_vec .== 1)
        idx_opf = (lidx, n1, n2)
        push!(ef_flow, pfl[idx_opf])
        push!(my_flow, f_1[l,1,1]/100)
        push!(lidx_vec, lidx)
        push!(t_br, n1)
        push!(t_br_str, node_index_2_node_name[n1])
        push!(f_br, n2)
        push!(f_br_str, node_index_2_node_name[n2])
    end

    df = DataFrame(
        "Line_name" => L,
        "Line_index" => lidx_vec,
        "From_branch_name" => f_br_str,        
        "From_branch_idx" => f_br,
        "To_branch_name" => t_br_str,        
        "To_branch_idx" => t_br,
        "UC_flow" => my_flow,
        "OPF_flow" => ef_flow
    )

    CSV.write(joinpath(opts["save_path"], "line_flows_hour=$(t).csv"), df)

    return df
end

df = line_flow_comparison(gep, pfl, 5113)
