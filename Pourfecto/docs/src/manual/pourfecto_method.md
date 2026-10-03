# [The `pourfecto` method](@id pourfecto_method)

```@meta
CurrentModule = Pourfecto
```

Pourfecto separates liquid-handling protocol design into two related stages:

1. **Planning**: determines how source stocks can be combined to produce target stocks.
2. **Scheduling**: determines how the plan can be executed using specific labware and instrument configurations.

[`pourfecto`](@ref) is the main function for planning and scheduling. It chooses the workflow from the types of its inputs. It runs in one of two modes:

- **planning mode** computes source-to-target transfer volumes.
- **planning and scheduling mode** also maps those transfers onto liquid-handler configurations.

## Planning

### Planning from stocks

If you only have source and target `CHESSCore.Stock` objects, call:

```julia
pourfecto(sources::Vector{<:CHESSCore.Stock}, targets::Vector{<:CHESSCore.Stock})
```

This runs in **planning mode**. The result is a [`Pourcast`](@ref) that holds the planned transfer matrix. Planning checks whether the stocks give a feasible transfer plan. It does not consider the logistics of the liquid handling workflow.

### Planning from labware

If the source and target stocks are already in labware, the labware can be passed directly:

```julia
pc = pourfecto(source_labware::Vector{<:CHESSCore.Labware}, target_labware::Vector{<:CHESSCore.Labware})
```

This also runs in **planning mode**. Pourfecto takes the stocks from the labware and plans transfers between them.

## Planning and scheduling

Planning and scheduling mode takes source labware, target labware, and instrument configurations:

```julia
pc = pourfecto(source_labware::Vector{<:CHESSCore.Labware}, target_labware::Vector{<:CHESSCore.Labware},configs::Vector{<:Configuration})
```

It plans the required transfers and schedules them on the liquid-handler configurations. The resulting [`Pourcast`](@ref) contains both:

- transfer volumes, available with [`transfers`](@ref), and
- scheduled flow volumes, available with [`flows`](@ref).

### Planning and scheduling from configuration names

Configurations registered in the `configurations` dictionary can be given by their string identifiers instead of as objects:

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

## Planning, scheduling, and compiling

A fourth method runs the full workflow. It plans and schedules, checks the quality of the resulting [`Pourcast`](@ref), and compiles output files into a directory.

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

This is the most automated interface. It goes from populated labware and instrument configurations to compiled protocol files. It performs these steps:

1. Runs in **planning and scheduling** mode.
2. Checks the quality of the solution.
3. If the solution passes the check, compiles the `Pourcast` into the output directory.
4. Returns the [`Pourcast`](@ref).

## Dispatch summary

| Call | Mode |
|---|---|
| `pourfecto(sources, targets)` | Planning |
| `pourfecto(source_labware, target_labware)` | Planning | 
| `pourfecto(source_labware, target_labware, configs)` | Planning + scheduling| 
| `pourfecto(source_labware, target_labware, config_names)` | Planning + scheduling |
| `pourfecto(directory, source_labware, target_labware, configs)` | Planning + scheduling + compiling | 

## Keyword arguments

Most high-level [`pourfecto`](@ref) methods accept the same keyword arguments and pass them to the planning, scheduling, and compilation steps as needed. The options control the solver, planning tolerances, reagent priorities, and scheduling objectives.

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
| `grb_feasibility_tol` | `1e-6` | `Real` | Solver | Sets Gurobi’s [`FeasibilityTol`](https://docs.gurobi.com/projects/optimizer/en/current/reference/parameters.html#feasibilitytol) parameter. Every MILP scheduling objective also uses it as the indicator and big-M epsilon, whichever solver is active. |
| `min_vol_threshold` | `0.1` | `Real` | Planning | Sets the minimum volume threshold in µL. Any required transfer must be at least this large. |
| `require_nonzero` | `true` | `Bool` | Planning | If a target contains a reagent, require that some amount of that reagent is delivered, even if the optimal relaxed solution would deliver none. |
| `enforce_minimum_shot` | `false` | `Bool` | Scheduling | Enforces minimum shot-volume constraints for each instrument. **Caution:** this introduces binary variables and turns the problem into a MILP. |
| `slack_tol` | `1e-2` | `Real` | Planning | Sets the tolerance for preserving slack values across priority levels. A value of `0.01` corresponds to a 1% tolerance. |
| `config_costs` | `ones(length(configs))` | `Vector{Real}` | Scheduling objective | Sets the relative cost of using each configuration. Used by objectives such as `"min_cost_flow"`. |
| `solution_tolerance` | `1e-2` | `Real` | Quality control / planning | Sets the allowable magnitude for individual slacks in solution-quality checks. Slacks are normalized per chemical, so a value of `1` allows a chemical's slack to be as large as the largest target quantity *of that chemical*, not the largest target in the whole model. |
| `allow_in_place` | `false` | `Bool` | Planning | Allows the same physical labware to appear in both `source_labware` and `target_labware`, for in-place transfers such as adding a reagent to a plate's existing stocks. Wells shared by the source and target keep their existing content, limited by the physical well capacity and not by the declared target quantity. See [Allow in-place transfers](@ref) below. |

!!! note
    The keyword arguments are stored in the [`ParameterDict`](@ref) of the returned [`Pourcast`](@ref). `params` shows them:

    ```julia
    params(pc)
    ```

## [Choosing a solver](@id pourfecto_choosing_a_solver)

The `optimizer` keyword of `pourfecto` accepts any [JuMP](https://jump.dev)-compatible optimizer. The default is `Gurobi.Optimizer`, which is free for academic use and otherwise needs a commercial license. Pourfecto is also tested against two free, open-source solvers:

| Solver | License | Handles MIQP (`enforce_minimum_shot = true`) | Notes |
|---|---|---|---|
| [`Gurobi.Optimizer`](https://www.gurobi.com) | Commercial (free for academic use) | Yes | The default. No known limitations with any Pourfecto objective or constraint. |
| [`SCIP.Optimizer`](https://scipopt.org) | Free, open-source | Yes | The Pourfecto test suite runs on SCIP by default. It handles every objective and constraint that Pourfecto builds but is noticeably slower than Gurobi and HiGHS on large continuous QPs with many reagents and wells. |
| [`HiGHS.Optimizer`](https://highs.dev) | Free, open-source | **No** | Much faster than SCIP on large continuous QPs. HiGHS does not support indicator or quadratic constraints, so it **cannot** be used with `enforce_minimum_shot = true` or with scheduling objectives that need indicator constraints. It can be used with `enforce_minimum_shot = false` and with objectives that need none, such as the default `"min_cost_flow"`. |

```julia
using SCIP
pc = pourfecto(sources, targets, configs; optimizer = SCIP.Optimizer)
```

```julia
using HiGHS
pc = pourfecto(sources, targets, configs; optimizer = HiGHS.Optimizer, enforce_minimum_shot = false)
```

!!! warning
    HiGHS does not warn when it models indicator or quadratic constraints incorrectly. Use `optimizer = HiGHS.Optimizer` only with `enforce_minimum_shot = false` and an objective that needs no indicator constraints. Otherwise use SCIP or Gurobi.

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

### Set a solver time limit

The default solver time limit is 30 seconds for every `optimizer`:

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

### Require nonzero reagent delivery

By default `require_nonzero = true`: if a target contains a reagent, Pourfecto requires some amount of that reagent to be delivered.

```julia
pc = pourfecto(
    sources,
    targets;
    require_nonzero = true,
    min_vol_threshold = 0.1,
)
```

Here, any required transfer must be at least `0.1 µL`.

This ensures that required reagents are transferred and not ignored because of slack tolerances.

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

### Allow in-place transfers

By default, Pourfecto rejects source and target labware that share a name, because a repeated name changes the physical meaning of the transfer and is likely a mistake:

```julia
allow_in_place = false
```

Setting `allow_in_place = true` lets the same physical labware appear on both sides. This is for transfers that add reagent to a plate's existing contents, such as adjusting pH or dosing a seeded assay plate, instead of filling an empty target. Source and target wells are matched by labware name and well name. The existing content of a matched well is pinned, which forces all of it to carry forward, and is limited by the physical well capacity and not by the sum of the target composition.

```julia
pc = pourfecto(
    [naoh_reservoir, existing_plate],
    [target_plate], # same name as existing_plate
    configs;
    allow_in_place = true,
)
```

!!! warning
    Every reagent in the existing content of an in-place well must be restated in its target composition or given an explicit nonzero priority. A reagent that no target declares defaults to priority `0`, which blocks it and conflicts with the pin that carries its existing amount forward. The [in-place transfers example](../examples/in_place.md) walks through this case and shows how the resulting `InfeasibleSolveError` reports it.

