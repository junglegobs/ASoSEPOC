isdefined(Main, :GRB_EXISTS) == false &&
    const GRB_EXISTS = haskey(ENV, "GUROBI_HOME")
isedefined(Main, :CPLEX_EXISTS) == false &&
    const CPLEX_EXISTS = haskey(ENV, "CPLEX_STUDIO_BINARIES")

GRB_EXISTS && using Gurobi
CPLEX_EXISTS && using CPLEX
