using Pkg
juliaenv = "." # @__DIR__ is no good because it gives the absolute paths
cd(@__DIR__)
Pkg.activate(juliaenv)
ENV["JULIA_PKG_DEVDIR"] = joinpath(juliaenv, "dev")

# Deal with possibly not having Gurobi or CPLEX
include(joinpath(@__DIR__, "src", "solvers.jl"))
if CPLEX_EXISTS
    Pkg.add("CPLEX")
else
    try
        Pkg.rm("CPLEX")
    catch e
        nothing
    end
end
if GRB_EXISTS
    Pkg.add("Gurobi")
else
    try
        Pkg.rm("Gurobi")
    catch e
        nothing
    end
end

# Add my UC/ED/GEP package, GEPPR
try
    Pkg.rm("GEPPR")
catch
    nothing
end
Pkg.add(url="https://gitlab.kuleuven.be/UCM/GEPPR.jl.git")
Pkg.develop("GEPPR")
cd(joinpath(@__DIR__, "dev", "GEPPR"))
run(`git checkout a_sos_EPOC`) # If this fails then do this manually
cd(joinpath("..", ".."))

# Instantiate
Pkg.instantiate()
