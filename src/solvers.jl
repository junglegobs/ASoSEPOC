isdefined(Main, :GRB_EXISTS) == false &&
    const GRB_EXISTS = haskey(ENV, "GUROBI_HOME")
isdefined(Main, :CPLEX_EXISTS) == false &&
    const CPLEX_EXISTS = haskey(ENV, "CPLEX_STUDIO_BINARIES")

if GRB_EXISTS
    try
        using Gurobi
    catch
        @warn "Unable to load Gurobi"
    end
end

if CPLEX_EXISTS
    try
        using CPLEX
    catch
        @warn "Unable to load CPLEX"
    end
end