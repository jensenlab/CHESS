# [Quick Start](@id pourfecto_quickstart)

Using Pourfecto takes five steps:

1. Define source labware that holds reagent stocks.
2. Define target labware.
3. Select the available instrument configurations.
4. Run the planning and scheduling algorithm to create a solved [`Pourcast`](@ref).
5. Compile and inspect the `Pourcast`.

The example on this page is complete and runs as written. It mixes water and ethanol into three wells
of a plate. It uses the free SCIP solver. The default solver, Gurobi, needs a license, and
[Choosing a solver](@ref pourfecto_choosing_a_solver) describes the options. The
[Checkerboard Assay](@ref) example in the Examples section is a larger, runnable workflow.

## Define the source and target labware

Pourfecto reads source and target labware from tables. Each row describes one well: the labware kind,
the name of the labware, the well, the total volume, and the composition. A second table gives the
units of the values in the first. Here the sources are two 50 mL conical tubes, one of water and one
of ethanol, and the target is a 96-well plate with three filled wells:

```julia
using Pourfecto, DataFrames, SCIP

source_values = DataFrame(
    labware = ["Conical50", "Conical50"],
    name = ["water_tube", "ethanol_tube"],
    well = ["A1", "A1"],
    volume = [40_000, 40_000],
    water = [100, 0],
    ethanol = [0, 100],
)

target_values = DataFrame(
    labware = fill("WP96", 3),
    name = fill("target_plate", 3),
    well = ["A1", "A2", "A3"],
    volume = [200, 200, 200],
    water = [80, 50, 20],
    ethanol = [20, 50, 80],
)

units = DataFrame(volume = ["µL"], water = ["percent"], ethanol = ["percent"])

sources = df_to_labware(source_values, units)
targets = df_to_labware(target_values, units)
```

[`df_to_labware`](@ref) converts the tables to CHESSCore `Labware` objects. Pourfecto shows a warning
for each reagent that is not registered, here water and ethanol, and continues with a reagent that
has only a name. The [Labware](@ref pourfecto_labware) and [Stocks](@ref pourfecto_stocks) pages
describe the table formats.

## Select the configurations

A [`Configuration`](@ref) describes a liquid handler: its pipetting [`Head`](@ref) and a
[`Deck`](@ref) that can hold the source and target labware. The [`configurations`](@ref) dictionary
holds the pre-defined configurations. This example offers two of them:

1. an eight-channel pipette, oriented vertically, and
2. a Hamilton Nimbus, configured with slots for 50 mL conical tubes and one SLAS plate slot, a
   common configuration in the Jensen Lab.

```julia
configs = [configurations["eight_channel_vertical"], configurations["nimbus"]]
```

## Run the algorithm

[`pourfecto`](@ref) plans and schedules, saves the result as a `Pourcast`, and compiles the
`Pourcast` into instrument files in the output directory. It checks the quality of the solution
before compiling and raises an error if the solution is outside the tolerance.

```julia
pc = pourfecto("quickstart_output", sources, targets, configs; optimizer = SCIP.Optimizer)
```

Without a directory, `pourfecto` returns a `Pourcast` and compiles nothing. [`compile`](@ref) then
writes the files:

```julia
pc = pourfecto(sources, targets, configs; optimizer = SCIP.Optimizer)
compile("quickstart_output", pc)
```

!!! warning
    Pourfecto does not guarantee a solution that generates the targets exactly or uses resources
    efficiently. Check a solution before compiling it and running it in the lab.

## Inspect the solution

With an output directory, `pourfecto` creates this file structure:

```
<output_directory>/
├── pourcast.json
├── target_plate_images/
│   ├── <plate name 1>.png
│   └── ...
├── <Configuration 1>/
│   ├── <protocol 1>/
│   │   ├── loading_instructions.png
│   │   ├── loading_table.csv
│   │   └── instrument files ...
│   ├── <protocol 2>/ ...
│   └── ...
├── <Configuration 2>/
│   ├── <protocol 1>/
│   │   ├── loading_instructions.png
│   │   ├── loading_table.csv
│   │   └── instrument files ...
│   └── ...
└── ...
```

- `pourcast.json` is the saved `Pourcast`.
- `target_plate_images/` holds a heatmap of the planned final volume of each well in each target
  plate, which helps to verify the solution visually.
- Each `<Configuration>/` folder holds the instrument files for one configuration. Each subfolder is
  an executable protocol with a randomly generated name, and it contains the instrument loading
  instructions as a table and as an image. A configuration that the solution does not use has no
  folder. In this example the solution uses the Nimbus only.

The [Pourcasts](@ref pourfecto_pourcasts) page describes how to inspect the `Pourcast` itself.
