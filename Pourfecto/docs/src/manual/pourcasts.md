# [Pourcasts](@id pourfecto_pourcasts)

```@meta
CurrentModule = Pourfecto
```

A [`Pourcast`](@ref) is the main result object returned by Pourfecto. It stores the inputs, results, and metadata from a `pourfecto` run.

Most users create `Pourcast` objects by calling [`pourfecto`](@ref):


```julia
pc = pourfecto(source_labware, target_labware, configs)
```

The returned `pc` contains everything needed to inspect the planned transfers, scheduled flows, target errors, instrument configurations, and run parameters.

---

## Stored Features of Pourcasts

A [`Pourcast`](@ref) contains:

- source stocks,
- target stocks,
- source labware,
- target labware,
- instrument configurations,
- run parameters,
- raw model solution variables,
- final objective value.


---

### Planning-only Pourcasts

If you call `pourfecto` with stocks:

```julia
pc = pourfecto(sources, targets)
```

or with labware but no configurations:

```julia
pc = pourfecto(source_labware, target_labware)
```

Pourfecto runs in **planning mode**.

A planning-only `Pourcast` contains:

- source stocks,
- target stocks,
- planning parameters,
- the transfer matrix `V`,
- slack variables.

It may not contain instrument-level flow variables, because no scheduling configurations were supplied.

---


### Accessing Pourcast fields

Pourfecto provides accessor functions for each field of a `Pourcast`.


For example:

```julia
source_stocks(pc)
target_stocks(pc)
params(pc)
scheduling_objective_value(pc)
```

---

### Source and target stocks

Use [`source_stocks`](@ref) and [`target_stocks`](@ref) to recover the stock objects used by Pourfecto.

```julia
S = source_stocks(pc)
T = target_stocks(pc)
```

The source stocks are the materials Pourfecto was allowed to use. The target stocks are the desired outputs Pourfecto attempted to create.

---

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

Labware is stored separately from stocks because the same planning machinery can be used with or without physical labware placement.

---

### Configurations

Use [`configs`](@ref) to inspect the instrument configurations used during scheduling.

```julia
configs(pc)
```

Planning-only `Pourcast`s do not use configurations and usually store an empty configuration vector.

---

### Parameters

Use [`params`](@ref) to inspect the `ParameterDict` associated with a run.

```julia
p = params(pc)
```

This dictionary stores user-provided keyword arguments, defaults, metadata, and run information.

Common entries include:

```julia
params(pc)[:objective]
params(pc)[:priority]
params(pc)[:quiet]
params(pc)[:grb_timelimit]
params(pc)[:min_vol_threshold]
params(pc)[:require_nonzero]
params(pc)[:slack_tol]
params(pc)[:solution_tolerance]
params(pc)[:solver_elapsed]
```

For example:

```julia
params(pc)[:solver_elapsed]
```

returns the elapsed solve time recorded by Pourfecto.

---

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

---

### Objective value

Use [`scheduling_objective_value`](@ref) to inspect the final objective value.

```julia
scheduling_objective_value(pc)
```

The interpretation of this value depends on the objective used during the run. For example, if the scheduling objective is `"min_cost_flow"`, the value corresponds to that objective’s final optimized cost.

---

## Computed Features 

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

Rows correspond to `source_stocks(pc)`, and columns correspond to `target_stocks(pc)`:

---

### Flow variables

Scheduled flow variables are accessed with [`flows`](@ref):


```julia
Q = flows(pc)
```

`Q` is indexed by aspiration node and dispense node:

```julia
Q[asp_node_index, disp_node_index]
```

Flow variables are only available for scheduled `Pourcast`s created with configurations.

For example:

```julia
pc = pourfecto(source_labware, target_labware, configs)

Q = flows(pc)
```

If a `Pourcast` was created in planning-only mode, it may not contain a `:Q` variable.

---

## Slack variables

Slack variables are accessed with [`slacks`](@ref):

```@docs
slacks
```

```julia
E = slacks(pc)
```

Slack variables describe the difference between requested target compositions and the compositions produced by the solved plan.

Conceptually, the planning model enforces:

```julia
planned_target - slack == requested_target
```

Small slack values indicate that the planned stock closely matches the requested target. Large slack values indicate that Pourfecto could not exactly produce one or more target components under the supplied constraints.

Slack variables are useful for diagnosing:

- insufficient source material,
- missing reagents,
- infeasible exact-match constraints,
- priority tradeoffs,
- target compositions that cannot be made exactly.

---


### Comparing planned and target stocks

Use [`planned_stocks`](@ref) to reconstruct the stocks implied by the planned transfers:

```julia
planned = planned_stocks(pc)
```

Then compare these to the requested targets:

```julia
target_stocks(pc)
planned_stocks(pc)
```

This is often the easiest way to check whether the plan produced the intended outputs.

---

## Visualizing scheduled flows

For scheduled `Pourcast`s, use:

```julia
plot_flows(pc)
```


---

## Serializing Pourcasts

Pourcasts can be saved to JSON and loaded later.

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

This is useful for archiving results, debugging failed runs, or passing Pourcasts to downstream compilation tools.

---

## Common inspection workflow

After running Pourfecto, a typical inspection workflow is:

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

---

## Troubleshooting

### `flows(pc)` is unavailable

If `flows(pc)` fails or the `:Q` variable is missing, the `Pourcast` was likely created in planning-only mode.

Use scheduling mode:

```julia
pc = pourfecto(source_labware, target_labware, configs)
```

instead of:

```julia
pc = pourfecto(sources, targets)
```

---

### Large slack values

Large slack values indicate that the requested targets could not be matched exactly.

Possible causes include:

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

---

### Unexpectedly small transfer values

Transfer and flow values are rounded according to `params(pc)[:min_vol_threshold]`.

Check:

```julia
params(pc)[:min_vol_threshold]
vol_sigdigs(pc)
```

If needed, rerun Pourfecto with a smaller threshold:

```julia
pc = pourfecto(
    sources,
    targets;
    min_vol_threshold = 0.01,
)
```

---