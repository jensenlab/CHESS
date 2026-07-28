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

If you only have source and target `JLIMS.Stock` objects, call:

```julia
pourfecto(sources::Vector{<:JLIMS.Stock}, targets::Vector{<:JLIMS.Stock})
```


This runs Pourfecto in **planning mode**. The result is a [`Pourcast`](@ref) containing the planned transfer matrix. Planning is useful to verify that the stock inputs result in a feasible liquid transfer platn. Planning **does not** consider any of the logistical details of the liquid handling workflow. 


---

### Planning from labware

If your source and target stocks are already placed in labware, you can pass labware directly:

```julia
pc = pourfecto(source_labware::Vector{<:JLIMS.Labware}, target_labware::Vector{<:JLIMS.Labware})
```

This also runs in **planning mode**. Pourfecto extracts the stocks from the supplied labware and plans transfers between those stocks.


---

## Planning and scheduling

To run in both planning and scheduling modes, provide source labware, target labware, and instrument configurations:

```julia
pc = pourfecto(source_labware::Vector{<:JLIMS.Labware}, target_labware::Vector{<:JLIMS.Labware},configs::Vector{<:Configuration})
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
source_labware::Vector{<:JLIMS.Labware}
target_labware::Vector{<:JLIMS.Labware}
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
| `grb_timelimit` | `30` | `Real` | Solver | Sets Gurobi’s [`TimeLimit`](https://docs.gurobi.com/projects/optimizer/en/current/reference/parameters.html#timelimit) parameter, in seconds. |
| `grb_feasibility_tol` | `1e-6` | `Real` | Solver | Sets Gurobi’s [`FeasibilityTol`](https://docs.gurobi.com/projects/optimizer/en/current/reference/parameters.html#feasibilitytol) parameter. |
| `min_vol_threshold` | `0.1` | `Real` | Planning | Sets the minimum volume threshold in µL. Any required transfer must be at least this large. |
| `require_nonzero` | `true` | `Bool` | Planning | If a target contains a reagent, require that some amount of that reagent is delivered, even if the optimal relaxed solution would deliver none. |
| `enforce_minimum_shot` | `false` | `Bool` | Scheduling | Enforces minimum shot-volume constraints for each instrument. **Caution:** this introduces binary variables and turns the problem into a MILP. |
| `slack_tol` | `1e-2` | `Real` | Planning | Sets the tolerance for preserving slack values across priority levels. A value of `0.01` corresponds to a 1% tolerance. |
| `config_costs` | `ones(length(configs))` | `Vector{Real}` | Scheduling objective | Sets the relative cost of using each configuration. Used by objectives such as `"min_cost_flow"`. |
| `solution_tolerance` | `1e-2` | `Real` | Quality control / planning | Sets the allowable magnitude for individual slacks in solution-quality checks. A value of `1` allows slack as large as the largest target quantity in the model. |

!!! note
    Keyword arguments are stored in the [`ParameterDict`](@ref) inside the returned [`Pourcast`](@ref). You can inspect them with:

    ```julia
    params(pc)
    ```

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

The default Gurobi time limit is 30 seconds:

```julia
pc = pourfecto(
    sources,
    targets;
    grb_timelimit = 30,
)
```

For larger scheduling problems, increase the time limit:

```julia
pc = pourfecto(
    source_plate,
    target_plate,
    configs;
    grb_timelimit = 300,
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



