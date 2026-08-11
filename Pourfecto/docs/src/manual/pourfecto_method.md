# [The `pourfecto` method](@id pourfecto_method)



```@meta
CurrentModule = Pourfecto
```

Pourfecto separates liquid-handling protocol design into two related stages:

1. **Planning**: determines how source stocks can be combined to produce target stocks.
2. **Scheduling**: determines how the plan can be executed using specific labware and instrument configurations.


The main user-interface for planning and scheduling is [`pourfecto`](@ref). This method dispatches on the types of inputs you provide and chooses the appropriate workflow automatically.

`pourfecto` can run in either:

- **planning mode**, where it computes source-to-target transfer volumes, or
- **planning and scheduling mode**, where it also maps those transfers onto liquid-handler configurations.


---

## Planning 

### Planning from stocks

If you only have source and target `CHESSCore.Stock` objects, call:

```julia
pourfecto(sources::Vector{<:CHESSCore.Stock}, targets::Vector{<:CHESSCore.Stock})
```


This runs Pourfecto in **planning mode**. The result is a [`Pourcast`](@ref) containing the planned transfer matrix. Planning is useful to verify that the stock inputs result in a feasible liquid transfer plan. Planning **does not** consider any of the logistical details of the liquid handling workflow. 


---

### Planning from labware

If your source and target stocks are already placed in labware, you can pass labware directly:

```julia
pc = pourfecto(source_labware::Vector{<:CHESSCore.Labware}, target_labware::Vector{<:CHESSCore.Labware})
```

This also runs in **planning mode**. Pourfecto extracts the stocks from the supplied labware and plans transfers between those stocks.


---

## Planning and scheduling

To run in both planning and scheduling modes, provide source labware, target labware, and instrument configurations:

```julia
pc = pourfecto(source_labware::Vector{<:CHESSCore.Labware}, target_labware::Vector{<:CHESSCore.Labware},configs::Vector{<:Configuration})
```

This mode plans the required transfers and then schedules them using the provided liquid-handler configurations.

The resulting [`Pourcast`](@ref) contains both:

- transfer volumes, available with [`transfers`](@ref), and
- scheduled flow volumes, available with [`flows`](@ref).


---

### Planning and scheduling from configuration names

If configurations have been registered in Pourfecto’s `configurations` dictionary, you can provide their string identifiers instead of the configuration objects themselves:

```julia
pc = pourfecto(source_labware, target_labware, config_names)
```

where:

```julia
config_names::Vector{<:AbstractString}
```

For example:

```julia
pc = pourfecto(
    [source_plate],
    [target_plate],
    ["single_channel_pipette"],
)
```
---





## Planning, Scheduling, and Compiling 

Finally, Pourfecto also provides a high-level method that runs the full planning and scheduling workflow, checks the quality of the resulting [`Pourcast`](@ref), and automatically compiles output files into a directory.

```julia
pc = pourfecto(directory, source_labware, target_labware, configs)
```

where:

```julia
directory::AbstractString
source_labware::Vector{<:CHESSCore.Labware}
target_labware::Vector{<:CHESSCore.Labware}
configs::Union{Vector{<:AbstractString}, Vector{<:Configuration}}
```

This is the most automated `pourfecto` interface. It is useful when you want to go directly from populated labware and instrument configurations to compiled protocol outputs.

This method performs the following steps:

1. Runs Pourfecto in **planning and scheduling** mode
3. Checks the quality of the solution
4. If the solution passes quality control, compiles the `Pourcast` into the output directory
5. Returns the resulting [`Pourcast`](@ref).




--- 

## Dispatch summary

| Call | Mode |
|---|---|
| `pourfecto(sources, targets)` | Planning |
| `pourfecto(source_labware, target_labware)` | Planning | 
| `pourfecto(source_labware, target_labware, configs)` | Planning + scheduling| 
| `pourfecto(source_labware, target_labware, config_names)` | Planning + scheduling |
| `pourfecto(directory, source_labware, target_labware, configs)` | Planning + scheduling + compiling | 

---

## Keyword arguments

Most high-level [`pourfecto`](@ref) methods accept the same keyword arguments and pass them through to the planning, scheduling, and compilation steps as needed.

These options control solver behavior, planning tolerances, reagent priorities, and scheduling objectives.

```julia
pc = pourfecto(
    sources,
    targets;
    priority = PriorityDict("water" => 1),
    quiet = true,
    min_vol_threshold = 0.1,
)
```

| Keyword | Default | Type | Used in | Description |
|---|---:|---|---|---|
| `objective` | `"min_cost_flow"` | `AbstractString` or `Vector{<:AbstractString}` | Scheduling | Sets the scheduling objective for Pourfecto. See `keys(objectives)` for available options. |
| `priority` | `PriorityDict()` | `PriorityDict` | Planning | Specifies which reagents take precedence over others in the plan. Lower values indicate higher priority. Reagents with priority `0` must match exactly. |
| `quiet` | `true` | `Bool` | Solver | Suppresses solver output when `true`. |
| `optimizer` | `Gurobi.Optimizer` | any JuMP-compatible optimizer | Solver | Sets the solver used for planning and scheduling. See [Choosing a solver](@ref pourfecto_choosing_a_solver). |
| `solver_timelimit` | `30` | `Real` | Solver | Sets the solver's time limit, in seconds. Applies to any solver. |
| `grb_feasibility_tol` | `1e-6` | `Real` | Solver | Sets Gurobi’s [`FeasibilityTol`](https://docs.gurobi.com/projects/optimizer/en/current/reference/parameters.html#feasibilitytol) parameter. Also reused as the indicator/big-M epsilon inside every MILP scheduling objective regardless of the active solver, so it isn't purely a Gurobi-only setting in practice. |
| `min_vol_threshold` | `0.1` | `Real` | Planning | Sets the minimum volume threshold in µL. Any required transfer must be at least this large. |
| `require_nonzero` | `true` | `Bool` | Planning | If a target contains a reagent, require that some amount of that reagent is delivered, even if the optimal relaxed solution would deliver none. |
| `enforce_minimum_shot` | `false` | `Bool` | Scheduling | Enforces minimum shot-volume constraints for each instrument. **Caution:** this introduces binary variables and turns the problem into a MILP. |
| `slack_tol` | `1e-2` | `Real` | Planning | Sets the tolerance for preserving slack values across priority levels. A value of `0.01` corresponds to a 1% tolerance. |
| `config_costs` | `ones(length(configs))` | `Vector{Real}` | Scheduling objective | Sets the relative cost of using each configuration. Used by objectives such as `"min_cost_flow"`. |
| `solution_tolerance` | `1e-2` | `Real` | Quality control / planning | Sets the allowable magnitude for individual slacks in solution-quality checks. Slacks are normalized per chemical, so a value of `1` allows a chemical's slack to be as large as the largest target quantity *of that chemical*, not the largest target in the whole model. |
| `allow_in_place` | `false` | `Bool` | Planning | Allows the same physical labware to appear in both `source_labware` and `target_labware`, for in-place transfers (e.g. adding a reagent to a plate's existing stocks). Wells shared between source and target keep their existing content by construction, bounded by physical well capacity rather than the target's declared quantity. See [Allow in-place transfers](@ref) below. |

!!! note
    Keyword arguments are stored in the [`ParameterDict`](@ref) inside the returned [`Pourcast`](@ref). You can inspect them with:

    ```julia
    params(pc)
    ```

---

## [Choosing a solver](@id pourfecto_choosing_a_solver)

`pourfecto`'s `optimizer` keyword accepts any [JuMP](https://jump.dev)-compatible optimizer. Pourfecto
defaults to `Gurobi.Optimizer` (free for academic use, but otherwise a commercial license), and is
tested against two free, open-source alternatives:

| Solver | License | Handles MIQP (`enforce_minimum_shot = true`) | Notes |
|---|---|---|---|
| [`Gurobi.Optimizer`](https://www.gurobi.com) | Commercial (free for academic use) | Yes | The production default; no known limitations against any of Pourfecto's objectives or constraints. |
| [`SCIP.Optimizer`](https://scipopt.org) | Free, open-source | Yes | Pourfecto's own test suite runs on SCIP by default. Handles every objective and constraint Pourfecto can build, but is noticeably slower than Gurobi/HiGHS on large continuous QPs (many reagents × many wells). |
| [`HiGHS.Optimizer`](https://highs.dev) | Free, open-source | **No** | Much faster than SCIP on large continuous QPs. However, HiGHS has no indicator- or quadratic-constraint support, so it **cannot** be used with `enforce_minimum_shot = true` or with scheduling objectives that require indicator constraints. It's safe with `enforce_minimum_shot = false` and objectives like the default `"min_cost_flow"` that don't need them. |

```julia
using SCIP
pc = pourfecto(sources, targets, configs; optimizer = SCIP.Optimizer)
```

```julia
using HiGHS
pc = pourfecto(sources, targets, configs; optimizer = HiGHS.Optimizer, enforce_minimum_shot = false)
```

!!! warning
    HiGHS silently fails to model indicator/quadratic constraints correctly if you request them — always pair `optimizer = HiGHS.Optimizer` with `enforce_minimum_shot = false` and an objective that doesn't need indicator constraints, or use SCIP/Gurobi instead.

---

## Common examples

### Run quietly

By default, Pourfecto suppresses solver output:

```julia
pc = pourfecto(
    sources,
    targets;
    quiet = true,
)
```

To show solver output:

```julia
pc = pourfecto(
    sources,
    targets;
    quiet = false,
)
```

---

### Set a solver time limit

The default solver time limit is 30 seconds, and applies regardless of which `optimizer` is used:

```julia
pc = pourfecto(
    sources,
    targets;
    solver_timelimit = 30,
)
```

For larger scheduling problems, increase the time limit:

```julia
pc = pourfecto(
    source_plate,
    target_plate,
    configs;
    solver_timelimit = 300,
)
```

---

### Reagent Priority 

In many problems, users care about satisfying certain reagent targets over others. For example, one might be working with a drug that is highly soluble in ethanol but weakly soluble in water. If both stocks are present, one might prefer to minimize the amount of ethanol but still want to ensure that the target drug concentration is hit. In cases like this, provide a Priority scheme to state these preferences. 

Use a [`PriorityDict`](@ref) to specify which reagents should be matched most carefully by the planning algorithm. 

```julia
target_priority = PriorityDict(
    "drug" => 0,
    "ethanol" => 1,
    "water" => 2,
)
```

Then pass it to [`pourfecto`](@ref):

```julia
pc = pourfecto(
    sources,
    targets;
    priority = target_priority,
)
```

Priority values are interpreted as:

| Priority value | Meaning |
|---:|---|
| `0` | Must match exactly |
| `1` | Highest optimization priority after exact-match reagents |
| `2`, `3`, ... | Lower optimization priority |
| `typemax(UInt64)` | Very low priority / effectively optimized last |

---

### Require nonzero reagent delivery

By default, `require_nonzero = true`. This means that if a target contains a reagent, Pourfecto requires some amount of that reagent to be delivered.

```julia
pc = pourfecto(
    sources,
    targets;
    require_nonzero = true,
    min_vol_threshold = 0.1,
)
```

Here, any required transfer must be at least `0.1 µL`.

This can be useful for ensuring that required reagents are physically transferred rather than ignored because of slack tolerances.

---


### Adjust slack tolerance

The default slack tolerance is:

```julia
slack_tol = 1e-2
```

This corresponds to a 1% tolerance when preserving optimized slack values across priority levels.

Use a smaller value to preserve high-priority solutions more strictly:

```julia
pc = pourfecto(
    sources,
    targets;
    slack_tol = 1e-4,
)
```

Use a larger value to give lower-priority optimization steps more flexibility:

```julia
pc = pourfecto(
    sources,
    targets;
    slack_tol = 5e-2,
)
```

---

### Choose a scheduling objective

The default scheduling objective is:

```julia
objective = "min_cost_flow"
```

You can choose another registered objective:

```julia
pc = pourfecto(
    [source_plate],
    [target_plate],
    [config];
    objective = "min_aspirations",
)
```

To see available objective names:

```julia
keys(objectives)
```

Some workflows can apply multiple objectives in sequence:

```julia
pc = pourfecto(
    [source_plate],
    [target_plate],
    [config];
    objective = [
        "min_cost_flow",
        "min_active_flow",
    ],
)
```

When a vector of objectives is supplied, Pourfecto applies and solves each objective in the order provided.

---

### Set relative configuration costs

The `config_costs` keyword controls the relative cost of using each configuration in the default `"min_cost_flow"` objective. By default, all configurations have equal cost:

```julia
config_costs = ones(length(configs))
```

For example, if you have three configurations and want to make the third one more expensive:

```julia
pc = pourfecto(
    [source_plate],
    [target_plate],
    configs;
    objective = "min_cost_flow",
    config_costs = [1.0, 1.0, 5.0],
)
```

This encourages Pourfecto to use the first two configurations when possible and avoid the third unless it improves feasibility or objective quality.

---

### Enforce minimum shot volumes

By default, Pourfecto does not enforce minimum-shot constraints:

```julia
enforce_minimum_shot = false
```

To require every nonzero scheduled flow to satisfy the minimum dispense shot volume of the corresponding instrument:

```julia
pc = pourfecto(
    [source_plate],
    [target_plate],
    [config];
    enforce_minimum_shot = true,
)
```

!!! warning
    Setting `enforce_minimum_shot = true` introduces binary variables and can make the scheduling problem significantly harder to solve.

---

### Adjust solution-quality tolerance

The default solution tolerance is:

```julia
solution_tolerance = 1e-2
```

This is used when evaluating whether the final [`Pourcast`](@ref) satisfies quality checks. The quality control check compares the value of every slack to the tolerance, and flags the solution for any slack exceeding the tolerance. Slacks are normalized, so a slack value of 0.01 indicates that the slack value is 1% of the magnitude of the target (i.e. it is 1% off.)

For stricter quality control:

```julia
pc = pourfecto(
    [source_plate],
    [target_plate],
    [config];
    solution_tolerance = 1e-3, # slacks can be at most 0.1% of target 
)
```

For more permissive quality control:

```julia
pc = pourfecto(
    [source_plate],
    [target_plate],
    [config];
    solution_tolerance = 5e-2, # slacks can be up to 50% of target 
)
```

---

### Planning with priorities and tolerances

```julia
priority = PriorityDict(
    "active_compound" => 0,
    "dmso" => 1,
    "water" => 2,
)

pc = pourfecto(
    sources,
    targets;
    priority = priority,
    quiet = true,
    min_vol_threshold = 0.1,
    require_nonzero = true,
    slack_tol = 1e-2,
    solution_tolerance = 1e-2,
)
```

---

### Allow in-place transfers

By default, Pourfecto rejects a source and target labware that share a name -- reusing a name changes the physical meaning of the transfer, so it's treated as a likely mistake unless you opt in:

```julia
allow_in_place = false
```

Setting `allow_in_place = true` lets the same physical labware appear on both sides, for transfers that add reagent to a plate's existing contents (e.g. adjusting pH, dosing an already-seeded assay plate) rather than filling an empty target from scratch. Source and target wells are matched by labware name and well name; a matched well's existing content is pinned -- forced to carry forward at its full existing quantity -- and bounded by its physical well capacity rather than the naively-summed target composition.

```julia
pc = pourfecto(
    [naoh_reservoir, existing_plate],
    [target_plate], # same name as existing_plate
    configs;
    allow_in_place = true,
)
```

!!! warning
    Every reagent in an in-place well's existing content must be restated in its target composition (or given explicit nonzero priority) -- a reagent that's never declared in any target defaults to priority `0` (blocked), which directly conflicts with the pin forcing its existing amount to carry forward. See the [in-place transfers example](../examples/in_place.md) for a full worked walkthrough, including this exact pitfall and how the resulting `InfeasibleSolveError` reports it.

---


