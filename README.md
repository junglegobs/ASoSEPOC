# ASoSEPOC

This code base is using the Julia Language and [DrWatson](https://juliadynamics.github.io/DrWatson.jl/stable/)
to make a reproducible scientific project named
> ASoSEPOC

It is authored by Sebastian Gonzato.

To (locally) reproduce this project, do the following:

0. Download this code base. Notice that raw data are typically not included in the
   git-history and may need to be downloaded independently.
1. Open a Julia console and do:

```julia
julia> using Pkg
julia> Pkg.add("DrWatson") # install globally, for using `quickactivate`
julia> include("path/to/this/project/instantiate.jl")
```

This will install all necessary packages for you to be able to run the scripts and
everything should work out of the box, including correctly finding local paths.

## General description

### Model

The Deterministic Unit Commitment with Probabilistic (Operating) Reserves (DUC-PR) model is described in `papers/main.pdf`. In brief:

* Network, unit commitment and storage are included in the model.
* Operating reserves are modeled using "reserve levels", which have an associated activation probability.
  * These reserve levels can essentially be thought of as different reserve types, e.g. FCR, RR, etc.
  * No ramping / flexibility requirements are associated with reserve level activation (though these are taken into account in the day ahead scheduling).

## Data

### Download

Input data can be found [here](https://www.dropbox.com/sh/mdvmc082gwng0tr/AABRyc3fZpxAFycmUfZmh8Csa?dl=0).

### Description

Grid, load, renewables and capacity mix data come from [this paper](https://www.mech.kuleuven.be/en/tme/research/energy-systems-integration-modeling/pdf-publications/wp-en2019-02). Brief description:

* It is a Belgium-like system with a very high share of renewables (~80%).
* The nuclear reactors in Doel and Tihange have been replaced by gas fired power plants.

More information can be found in `papers/main.pdf`.

### Model runs

#### Questions to be answered

* Is there load shedding with an entirely linear model with no network constraints?
* Above, but with unit commitment constraints?
* Above, but with the network?
* Above, but with simultaneous charging/discharging not allowed?
* Same 3 questions as above, but with operating reserves and for different reserve level shedding limits, i.e. attempting to trace a adequacy / security pareto curve? + additional run with reserve activation network constraints?
* Starting from the most "inflexible" system, does adding absolute limits on the nodal imbalance change anything?
* Same, but with convex hull constraints?
* Same, but with load multiplier

#### Model runs table

UC = Unit commitment constraints
DANet = Day ahead network constraints
PSCD = Prevent simultaneous charge and discharge
OR = Include operating reserves and reserve shedding limits
RANet = Reserve activation network constraints
AbsImb = absolute limits on nodal imbalance
ConvImb = convex hull limits on nodal imbalance
L1.5 = Load times 1.5

| UC | DA Net. | PSCD | OR | RANet | AbsImb | ConvImb | L1.5 |
|----|---------|------|----|-------|--------|---------|------|
|    |         |      |    |       |        |         |      |
| x  |         |      |    |       |        |         |      |
| x  | x       |      |    |       |        |         |      |
| x  | x       | x    |    |       |        |         |      |
| x  |         |      | x  |       |        |         |      |
| x  | x       |      | x  |       |        |         |      |
| x  | x       | x    | x  |       |        |         |      |
| x  | x       | x    | x  | x     |        |         |      |
| x  | x       | x    | x  | x     | x      |         |      |
| x  | x       | x    | x  | x     | x      | x       |      |
| x  | x       | x    | x  | x     | x      | x       | x    |

All this just for one day, the 4th day in the list of days chosen.
