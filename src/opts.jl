
"""
    options(pairs)

Create a dictionary which specifies simulation parameters.
"""
function options(pairs...)
    opts = Dict(
        "include_storage" => false,
        "unit_commitment_type" => "binary",
        "operating_reserves_sizing_type" => "given",
        "operating_reserves_type" => "none",
        "initial_commitment_data_path" => "",
    )
    for (k,v) in pairs
        opts[k] = v
    end
    return opts
end
