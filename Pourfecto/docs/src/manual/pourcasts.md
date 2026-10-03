# [Pourcasts](@id pourfecto_pourcasts)

```@meta
CurrentModule = Pourfecto
```

A [`Pourcast`](@ref) is the result of a `pourfecto` run. It stores the inputs, results, and metadata of the run. [`pourfecto`](@ref) creates it:

```julia
pc = pourfecto(source_labware, target_labware, configs)
```

The returned `pc` holds the planned transfers, scheduled flows, target errors, instrument configurations, and run parameters.

## Stored features

A [`Pourcast`](@ref) contains:

- source stocks,
- target stocks,
- source labware,
- target labware,
- instrument configurations,
- run parameters,
- raw model solution variables,
- final objective value.

### Planning-only Pourcasts

Calling `pourfecto` with stocks:

```julia
pc = pourfecto(sources, targets)
```

or with labware and no configurations:

```julia
pc = pourfecto(source_labware, target_labware)
```

runs in **planning mode**. A planning-only `Pourcast` contains:

- source stocks,
- target stocks,
- planning parameters,
- the transfer matrix `V`,
- slack variables.

It has no instrument-level flow variables, because no configurations were supplied.

### Accessing Pourcast fields

Each field of a `Pourcast` has an accessor function:

```julia
source_stocks(pc)
target_stocks(pc)
params(pc)
scheduling_objective_value(pc)
```

### Source and target stocks

Use [`source_stocks`](@ref) and [`target_stocks`](@ref) to recover the stock objects used by Pourfecto.

```julia
S = source_stocks(pc)
T = target_stocks(pc)
```

The source stocks are the materials that Pourfecto could use. The target stocks are the outputs that it tried to create.

### Source and target labware

Use [`source_labware`](@ref) and [`target_labware`](@ref) to recover the labware associated with a scheduled run.

```julia
source_labware(pc)
target_labware(pc)
```

Not all `Pourcast`s have labware. Planning-only runs created directly from stocks store empty labware vectors:

```julia
source_labware(pc) == Labware[]
target_labware(pc) == Labware[]
```

Labware is stored separately from stocks because planning works with or without labware.

### Configurations

Use [`configs`](@ref) to inspect the instrument configurations used during scheduling.

```julia
configs(pc)
```

Planning-only `Pourcast`s do not use configurations and usually store an empty configuration vector.

### Parameters

Use [`params`](@ref) to inspect the `ParameterDict` associated with a run.

```julia
p = params(pc)
```

The dictionary holds the keyword arguments, defaults, metadata, and run information. Common entries include:

```julia
params(pc)[:objective]
params(pc)[:priority]
params(pc)[:quiet]
params(pc)[:solver_timelimit]
params(pc)[:min_vol_threshold]
params(pc)[:require_nonzero]
params(pc)[:slack_tol]
params(pc)[:solution_tolerance]
params(pc)[:solver_elapsed]
```

`params(pc)[:solver_elapsed]` is the elapsed solve time.

### Raw model solution

Use [`model_solution`](@ref) to access the raw solution dictionary extracted from the JuMP model.

```julia
m = model_solution(pc)
```

The keys are symbols corresponding to model variables:

```julia
keys(model_solution(pc))
```

Important entries include:

| Key | Meaning |
|---|---|
| `:V` | Source-to-target transfer volumes |
| `:Q` | Scheduled flow volumes |
| `:slacks` | Target-composition error variables |

Most users should use the convenience accessors [`transfers`](@ref), [`flows`](@ref), and [`slacks`](@ref) instead of reading `model_solution(pc)` directly.

### Objective value

Use [`scheduling_objective_value`](@ref) to inspect the final objective value.

```julia
scheduling_objective_value(pc)
```

The meaning of this value depends on the objective of the run. For `"min_cost_flow"`, it is the final optimized cost.

## Computed features

### Transfer variables

The transfer matrix is accessed with [`transfers`](@ref):

```julia
V = transfers(pc)
```

`V` is indexed by source stock and target stock:

```julia
V[source_index, target_index]
```

For example:

```julia
V[1, 2]
```

is the planned volume transferred from source stock `1` to target stock `2`.

Rows correspond to `source_stocks(pc)` and columns to `target_stocks(pc)`.

### Flow variables

Scheduled flow variables are accessed with [`flows`](@ref):

```julia
Q = flows(pc)
```

`Q` is indexed by aspiration node and dispense node:

```julia
Q[asp_node_index, disp_node_index]
```

Flow variables exist only for `Pourcast`s created with configurations. A planning-only `Pourcast` has no `:Q` variable.

### Slack variables

[`slacks`](@ref) returns the slack variables:

```@docs
slacks
```

```julia
E = slacks(pc)
```

Slack variables are the differences between the requested target compositions and the compositions that the solved plan produces. The planning model enforces:

```julia
planned_target - slack == requested_target
```

A small slack means that the planned stock closely matches the target. A large slack means that Pourfecto could not produce a target component exactly under the constraints. Slack variables help diagnose:

- insufficient source material,
- missing reagents,
- infeasible exact-match constraints,
- priority tradeoffs,
- target compositions that cannot be made exactly.

## Quality control and reporting

`pourfecto(directory, source_labware, target_labware, configs; kwargs...)` checks solution quality before compiling. It compares [`slacks`](@ref) with `params(pc)[:solution_tolerance]`, which is `1e-2` by default. A slack whose magnitude exceeds the tolerance fails the check. [Adjust solution-quality tolerance](@ref pourfecto_method) describes how to change the tolerance.

If any slack fails, `pourfecto` writes `solution_quality_report.csv` and `pourcast.json` to `directory` and raises an error. No protocol files are written. The check cannot be turned into a warning or skipped.

### Reading the quality report

`solution_quality_report.csv` has one row per `(stock, chemical)` pair that failed tolerance:

| Column | Meaning |
|---|---|
| `stock` | Index of the stock with the failing slack |
| `chemical_index` | Index of the chemical within that stock |
| `chemical` | Name of the chemical |
| `slack_value` | The slack's actual value |
| `tolerance` | The tolerance it was checked against |

```julia
using CSV, DataFrames

report = CSV.read(joinpath(directory, "solution_quality_report.csv"), DataFrame)
```

### Checking quality manually

The same check can be run on a solved `Pourcast` before compiling. `solution_quality` and `solution_quality_report` are not exported, so they are called with the module name:

```julia
flags = Pourfecto.solution_quality(pc)         # BitMatrix, true where a slack fails tolerance
report = Pourfecto.solution_quality_report(pc) # DataFrame of just the failures
```

### Comparing planned and target stocks

Use [`planned_stocks`](@ref) to reconstruct the stocks implied by the planned transfers:

```julia
planned = planned_stocks(pc)
```

Comparing `planned_stocks(pc)` with `target_stocks(pc)` is the simplest check that the plan produced the intended outputs.

## Visualizing scheduled flows

`plot_flows` plots the flows of a scheduled `Pourcast`:

```julia
plot_flows(pc)
```

## Serializing Pourcasts

A `Pourcast` can be saved to JSON and loaded later.

```julia
json = pourcast_to_json(pc)

open("pourcast.json", "w") do io
    write(io, json)
end
```

To load it back:

```julia
json = read("pourcast.json", String)
pc2 = json_to_pourcast(json)
```

This archives results, helps debug failed runs, and passes a `Pourcast` to downstream compilation tools. [Compiling Protocols](@ref pourfecto_compiling) describes turning a solved `Pourcast` into protocol files for an instrument.

## Common inspection workflow

A typical inspection workflow after a run:

```julia
pc = pourfecto(source_labware, target_labware, configs)

# 1. Check parameters and objective
params(pc)
scheduling_objective_value(pc)

# 2. Inspect planned source-to-target transfers
transfers(pc)

# 3. Inspect composition errors
slacks(pc)

# 4. Inspect scheduled instrument flows
flows(pc)

# 5. Reconstruct planned target stocks
planned_stocks(pc)

# 6. Visualize scheduled flows
plot_flows(pc)
```

## Troubleshooting

### `flows(pc)` is unavailable

If `flows(pc)` fails or the `:Q` variable is missing, the `Pourcast` was probably created in planning-only mode. Call `pourfecto(source_labware, target_labware, configs)`, which schedules, and not `pourfecto(sources, targets)`, which only plans.

### Large slack values

Large slack values mean that the requested targets could not be matched exactly. Possible causes:

- missing reagents in the source stocks,
- insufficient source volume,
- overly strict priority-zero constraints,
- minimum-volume constraints,
- incompatible target compositions.

Inspect:

```julia
slacks(pc)
params(pc)[:priority]
transfers(pc)
```

[Quality control and reporting](@ref) describes the automatic check of these slack values and the report written when they fail.

### Unexpectedly small transfer values

Transfer and flow values are rounded according to `params(pc)[:min_vol_threshold]`. Check:

```julia
params(pc)[:min_vol_threshold]
vol_sigdigs(pc)
```

To keep smaller transfers, rerun with a smaller threshold:

```julia
pc = pourfecto(
    sources,
    targets;
    min_vol_threshold = 0.01,
)
```