using DrWatson
@quickactivate
using XLSX, PowerModels
net_data_dir = datadir("exp_raw", "Belderbos_Belgian_Model")

network = Dict{String,Any}(
    "name" => "Belderbos Belgium Model",
    "baseMVA" => 1,
    "source_type" => "matpower", # TODO
    "source_version" => "2", # TODO
    "bus" => Dict{String,Any}(),
    "branch" => Dict{String,Any}(),
    "load" => Dict{String,Any}(),
    "gen" => Dict{String,Any}(),
)
grid = XLSX.readxlsx(joinpath(net_data_dir, "BE-full2015_grid.xlsx"))
load_cols, load_labs = XLSX.readtable(joinpath(net_data_dir, "BE-full2015_load.xlsx"), "load")
gen = XLSX.readxlsx(joinpath(net_data_dir, "BE-full2015_portfolio.xlsx"))
ts = XLSX.readxlsx(joinpath(net_data_dir, "BE-full2015_transactions.xlsx"))
prices = XLSX.readxlsx(joinpath(net_data_dir, "BE-full2015_prices.xlsx"))

# Buses
node_sh = grid["node_information"]
for row in XLSX.eachrow(node_sh)
    bus_id = row["A"]
    if ismissing(bus_id) == false && bus_id isa Number
        bus_type = (bus_id == 1 ? 3 : 2) # TODO
        network["bus"]["$bus_id"] = Dict(
            "string" => "$bus_id",
            "number" => "$bus_id",
            "bus_i" => "$bus_id",
            "source_id" => ["bus", bus_id],
            "zone" => 1,
            "area" => 1
            "bus_type" => bus_type,
            "vmin" => 0.9 # TODO, assumed
            "vmax" => 1.1 # TODO, assumed
            "va" => 0.0 # TODO, no idea
            "vm" => 0.0 # TODO, no idea
            "base_kv" => 380.0 # TODO, assumed since not given
        )
    end
end

# Lines
line_sh = grid["line_information"]
for row in XLSX.eachrow(line_sh)
    line_id = row["A"]
    if ismissing(line_id) == false && line_id isa Integer
        network["branch"]["$line_id"] = Dict(
            "name" => "line_$line_id",
            "number_id" => line_id,
            "index" -> line_id,
            "f_bus" => row["C"],
            "t_bus" => row["D"],
            "rate_a" => row["F"], # TODO - this is the line capacity right?
            "br_r" => row["E"],
            "br_status" => 1, # = in service
            "ang_min" => -100.0, # TODO
            "ang_max" => 100.0, # TODO
            "transformer" => false,
        )
    end
end

# Load
for i = 1:length(load_cols)
    load_labs[i] == Symbol("Demand  [MW]") && continue
    bus = string(load_labs[i])
    bus_id = parse(Int, split(bus, "_")[end])
    load_vec = Float64.(load_cols[i])
    network["load"]["$bus_id"] = Dict(
        "source_id" => ["bus", bus_id],
        "load_bus" => bus_id,
        "pd" => load_vec,
        "pq" => fill(0.0, length(load_vec)),
        "index" => 1
    )
end

# Generation
pp_sh = gen["power_plant"]
gen_catg_sh = gen["category"]
for row in XLSX.eachrow(pp_sh)
    gen_id = row["A"]
    (ismissing(gen_id) || (gen_id isa Int) == false) && continue
    catg = row["C"]
    catg_row = gen_catg_sh["A$catg:X$catg"]
    fuel = catg_row[5]
    fuel_cost = prices["fuel_prices"][4,fuel+1]
    cost = fuel / catg_row[3] # Euros/MWh
    network["gen"]["$gen_id"] = Dict(
        "source_id" => ["gen", row["D"]], # second element is bus,
        "index" => gen_id,
        "pmax" => row["E"],
        "pmin" => row["E"] * row["G"] / 100
        "qmin" => 0.0, # TODO ???
        "qmax" => 0.0, # TODO ???
        "startup" => row["P"], # In kEur per start
        "shutdown" => 0.0,
        "gen_status" => 1 # i.e. On / availaible
        "cost" => cost, #  Euros / MWh
        "ncost" => 1, 
        "min_up" => catg_row[12], # TODO not part of PowerModels format
        "min_down" => catg_row[11], # TODO not part of PowerModels format
        "qg" => 0.0 # TODO not sure what this is
        "vg" => 0.0 # TODO not sure what this is
    )
end

# TODO renewables

# Save the dictionary
exp_pro = datadir("exp_pro")
open(joinpath(exp_pro, "grid.json"),"w") do f
    JSON.print(f, network, 4)
end