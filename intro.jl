using DrWatson
@quickactivate "ASoSEPOC"

println(
"""
Currently active project is: $(projectname())

Path of active project: $(projectdir())
"""
)
