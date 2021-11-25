# ASoSEPOC

This code base is using the Julia Language and [DrWatson](https://juliadynamics.github.io/DrWatson.jl/stable/)
to make a reproducible scientific project named
> ASoSEPOC

It is authored by Sebastian Gonzato.

To (locally) reproduce this project, do the following:

0. Download this code base. Notice that raw data are typically not included in the
   git-history and may need to be downloaded independently.
1. Open a Julia console and do:

   ```
   julia> using Pkg
   julia> Pkg.add("DrWatson") # install globally, for using `quickactivate`
   julia> Pkg.activate("path/to/this/project")
   julia> Pkg.instantiate()
   ```

This will install all necessary packages for you to be able to run the scripts and
everything should work out of the box, including correctly finding local paths.

## Data description

Grid, load, renewables and capacity mix data come from [this paper](https://www.mech.kuleuven.be/en/tme/research/energy-systems-integration-modeling/pdf-publications/wp-en2019-02). It is a Belgium-like system with a very high share of renewables (~80%).

The following approximations were taken and additional processing performed:

* Storage was included by modifying the load. This was done by including 2 storage devices (characteristics shown below, loosely inspired by data in paper) and running a full year, linear operational model to obtain a storage charging and discharging profile. This was then added to to the load.

| Parameter            | Battery | P2G |
|----------------------|---------|-----|
| Roundtrip Efficiency | 0.9     | 0.3 |
| Power Capacity [GW]  | 12      | 2   |
| Energy Capacity [GWh]  | 80         | 6165    |

**For the energy capacity of P2G, in Belderbos' paper he mentions a hydrogen buffer capacity of 6165 MWH2. This strikes me as very low (lower than that of batteries!), so I presumed that he made a unit mistake?**
