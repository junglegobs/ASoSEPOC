using DrWatson
@quickactivate
includet(srcdir("util.jl"))
using YAML, PowerModels
net_data_path = datadir("pro", "grid.json")
GEPPR_dir = datadir("pro", "GEPPR")
mkrootdirs(GEPPR_dir)

network = parse_file(net_data_path)
