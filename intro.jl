using DrWatson, Revise
@quickactivate "ASoSEPOC"

println(
"""
Currently active project is: $(projectname())

Path of active project: $(projectdir())
"""
)

includet.(srcdir.(readdir(srcdir())));
