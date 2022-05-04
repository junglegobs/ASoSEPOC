include(joinpath(@__DIR__, "..", "intro.jl"))

for script in readdir(scriptsdir())
    pbs_script_name = splitext(script)[1] * ".pbs"
    open(projectdir("pbs", pbs_script_name), "w") do file
        write(file,
        """
        #!/bin/bash -l\n

        echo "Starting job"\n

        #PBS -l walltime=02:00:00
        #PBS -l nodes=1:ppn=36
        #PBS -l pmem=5gb
        #PBS -A lp_elect_gen_modeling
        #PBS -m abe
        #PBS -M sebastian.gonzato@kuleuven.be\n

        echo "Did PBS stuff"\n

        source \$VSC_DATA/ASoSEPOC/pbs/setup.rc
        cd \$VSC_DATA/ASoSEPOC
        julia -e "import Pkg; Pkg.instantiate()"
        julia \$VSC_DATA/ASoSEPOC/scripts/$(script)\n

        echo "Done"
        """
        )
    end
end
