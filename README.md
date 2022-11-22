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

## Code description

* `src` - source files (i.e. individual functions)
* `scripts` - main scripts used for generating results
* `scripts_debug` - scripts used for debugging or testing purposes (may not be functional)
* `papers` - latex report of work done for this adequacy and operational security interaction.
* `pbs` - useful files for running on the [Flemish super computer](https://vlaams-supercomputing-centrum-vscdocumentation.readthedocs-hosted.com/en/latest/).

For the scripts:

* `process_input` - converts input data from Belderbos paper to format required for [`GEPPR.jl`](https://gitlab.kuleuven.be/UCM/GEPPR.jl).
* `check_and_fix_scenarios` - fixes infeasible wind, solar and load forecast errors (e.g. wind output less than that which is forecasted).
* `main_model_runs` - DUC-PR model runs to investigate whether tradeoff between adequacy and security is possible for day 285.
* `copperplate_adequacy_security_tradeoff` - same as above but without network constraints, to illustrate that the trade-off is possible in the absence of these.
* `interaction_check` - not sure.
* `interaction_selected_days` - not sure.
* `nodal_imbalance_investigation` - illustration of how to tighten reserve activation network constraints.

## General description

### Model

The Deterministic Unit Commitment with Probabilistic (Operating) Reserves (DUC-PR) model is described in `papers/main.pdf`. In brief:

* Network, unit commitment and storage are included in the model.
* Operating reserves are modeled using "reserve levels", which have an associated activation probability.
  * These reserve levels can essentially be thought of as different reserve types, e.g. FCR, RR, etc in that they have different probabilities of activation.
  * No flexibility requirements (e.g. ramping) are associated with reserve level activation though they are taken into account in the day ahead scheduling.
  * An attempt at including the network in the reserve level activation constraints is made, though this is a non-trivial task.

## Data

### Download

Input data can be found [here](https://www.dropbox.com/sh/mdvmc082gwng0tr/AABRyc3fZpxAFycmUfZmh8Csa?dl=0).

### Description

Grid, load, renewables and capacity mix data come from [this paper](https://www.mech.kuleuven.be/en/tme/research/energy-systems-integration-modeling/pdf-publications/wp-en2019-02). Brief description:

* It is a Belgium-like system with a very high share of renewables (~80%).
* The nuclear reactors in Doel and Tihange have been replaced by gas fired power plants.

More information can be found in `papers/main.pdf`.

### Model runs

#### Questions to be answered in preliminary investigation

* Is there load shedding with an entirely linear model with no network constraints?
* Above, but with unit commitment constraints?
* Above, but with the network?
* Above, but with simultaneous charging/discharging not allowed?
* Same 3 questions as above, but with operating reserves and for different reserve level shedding limits, i.e. attempting to trace a adequacy / security pareto curve? + additional run with reserve activation network constraints?
* Starting from the most "inflexible" system, does adding absolute limits on the nodal imbalance change anything?
* Same, but with convex hull constraints?
* Same, but with load multiplier

Table below outlines this better. Acronyms are:

* UC = Unit commitment constraints
* DANet = Day ahead network constraints
* PSCD = Prevent simultaneous charge and discharge
* OR = Include operating reserves and reserve shedding limits
* RANet = Reserve activation network constraints
* AbsImb = absolute limits on nodal imbalance
* ConvImb = convex hull limits on nodal imbalance
* L1.5 = Load times 1.5

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

All this just for one day, the 4th day (the day with the most scarcity) of the days selected for investigation. 

##### Trade off between load shedding and reserve shedding

There should be a tradeoff between shedding load in the day ahead stage and shedding reserves which would jeopardise real time operational security (since there are less reserves available to deal with unforeseen situations). The DUC-PR model is able to make this tradeoff in a coarse way, hence the real time operational security is then analysed using a Quasi Steady State Simulator (QSSS) developped by ULiege. This verifies how well the DUC-PR model is able to perform this trade-off (if at all).
