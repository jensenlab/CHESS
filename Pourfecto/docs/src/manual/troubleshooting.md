# [Troubleshooting Solver Failures](@id pourfecto_troubleshooting)

The planning and scheduling models of Pourfecto can fail in several ways. This page describes each
failure, the error it raises, and how to read the message.

## `ComponentShortageError`

`check_inputs` raises this error before any model is built, when the total supply of a component
(a chemical reagent or an organism) across all sources is less than the total demand across all
targets. The check is aggregate. It can pass when the plan for individual wells is infeasible (see
`InfeasibleSolveError` below), because it does not consider which source can reach which target.

The error has a `balances` field, a `Dict{StockComponent,Unitful.Quantity}` with the shortfall of
each component that failed the check.

## `InfeasibleSolveError`

This error is raised when the planning or scheduling model has no feasible solution, meaning the
solver returned `MOI.INFEASIBLE` or `MOI.INFEASIBLE_OR_UNBOUNDED`. Unlike a generic solver error, it
has a `causes` field. This is a list of the constraints that the solver identified as jointly
responsible, each with a `category` and a readable `description`.

```julia
try
    pourfecto(sources, targets)
catch err
    err isa Pourfecto.InfeasibleSolveError || rethrow()
    for cause in err.causes
        println(cause.category, ": ", cause.description)
    end
end
```

The categories are:

Planning stage (volumes only, no instruments):

- `:mass_balance`: the source composition cannot be combined to reach the composition of a target (see `require_nonzero` and `min_vol_threshold`).
- `:overdraft`: a source does not have enough material for everything that draws on it.
- `:capacity`: a target, or a pinned in-place well, cannot hold the volume assigned to it (see `allow_in_place`).
- `:pinning`: the existing content of an in-place well conflicts with another constraint (see `allow_in_place`).
- `:priority0`: a priority-0 chemical, which must match its target exactly with zero slack, cannot be matched exactly (see `priority`).

Scheduling stage (instrument and configuration assignment, present only when scheduling with `pourfecto(source_labware, target_labware, configs; ...)`):

- `:flow_connection`: a required transfer between two wells cannot be routed through the available instrument flows.
- `:invalid_flow`: a specific aspirate and dispense pairing is physically impossible for a configuration, for example because of the wrong labware or a mismatched piston.
- `:minimum_shot`: a dispense must be either zero or above the minimum shot volume of a configuration (only when `enforce_minimum_shot=true`), and neither option fits (see `enforce_minimum_shot`).
- `:source_flow_overdraft`: a source cannot supply everything that draws on it once the dead-volume padding of the instrument is included.

When several categories occur together, the message includes a short interpretation of the likely
cause:

- `:pinning` with `:priority0` usually means that the existing content of an in-place well includes
  a chemical that the target never declares. That chemical defaults to priority 0, which requires
  it to be exactly zero, while the pin carries its existing amount forward.
- `:invalid_flow` at all usually means that no configured instrument can reach both wells of a
  required transfer. Add a compatible configuration or remove the transfer.
- `:minimum_shot` with `:priority0` or `:mass_balance` usually means that a required dose is smaller
  than the minimum shot volume of every available configuration.

### Detailed and generic messages

Assigning a conflict to specific constraints needs an optimizer that supports conflict (IIS)
analysis. Gurobi and HiGHS support it, and SCIP does not. Without conflict analysis,
`InfeasibleSolveError` still identifies the priority level or scheduling stage at which the solve
failed, but `causes` is empty and the message gives a generic hint to check the targets, sources,
and pinned wells. `optimizer=Gurobi.Optimizer` or `optimizer=HiGHS.Optimizer` produces a detailed
breakdown of the same problem.

### Scheduling-stage infeasibility

`InfeasibleSolveError` can also be raised while scheduling, the instrument and configuration
assignment stage, with `level = "scheduling"`. This happens when the planned volumes are achievable
in principle but no valid combination of instruments and configurations can carry them out. The most
common case is a required dose below the minimum shot volume of every available configuration when
`enforce_minimum_shot=true`. `build_scheduling_model` adds the instrument constraints to the same
joint model that `solve_planning_model` iterates over, so this infeasibility is often reported at a
priority level and not at `"scheduling"`. The level in the message is where the solver detected the
conflict, which is not necessarily the stage that introduced the constraint.

### Example

Every well of a target plate needs a 0.1µL dose of NaOH, but the only available instrument
(`plate_master`) has a 1µL minimum shot. With `enforce_minimum_shot=true`, each dispense must be
either exactly 0 or at least 1µL, and 0.1µL is neither:

```julia
water = string_to_component("water", Liquid)
X = string_to_component("X", Liquid)
NaOH = string_to_component("NaOH", Liquid)

target_plate = build_location(location_kinds[:WP96], "min_shot_target")
for w in vec(children(target_plate))
    w.stock = 150u"µL"*water + 50u"µL"*X + 0.1u"µL"*NaOH # below plate_master's 1µL minimum shot
end
source_plate = build_location(location_kinds[:WP96], "min_shot_source")
for w in vec(children(source_plate))
    w.stock = 150u"µL"*water + 50u"µL"*X
end
reservoir = build_location(location_kinds[:DeepReservoir])
children(reservoir)[1].stock = 100u"mL"*NaOH

pourfecto([reservoir, source_plate], [target_plate], [configurations["plate_master"]];
    allow_in_place=true, priority=PriorityDict("NaOH"=>UInt(0)), enforce_minimum_shot=true)
```

This raises an `InfeasibleSolveError` with the message:

```text
the problem is infeasible at priority level 0. The following constraints cannot be satisfied together:
  - physical minimum-shot constraint: config "Gilson" dispensing onto labware "min_shot_target" requires each dispense to be 0 or at least 1 µL
  - mass/volume balance constraint linking source composition to well F11 of labware "min_shot_target" for chemical "NaOH"
  - priority-0 exact-match constraint requires 0 slack for chemical "NaOH" across all targets
  - flow-routing constraint requires transfers from well A1 of labware "..." to well F11 of labware "min_shot_target" to be carried entirely by available instrument flows
This usually means a required dose falls below every available configuration's minimum shot volume -- either allow a larger dose/slack, or add a configuration with a smaller minimum shot.
```

The four causes read together:

- `:minimum_shot`: the "Gilson" configuration of `plate_master` can dispense only 0 or at least 1µL onto this plate.
- `:mass_balance`: the plan needs exactly 0.1µL of NaOH delivered to well F11 to reach the target.
- `:priority0`: NaOH is priority 0, so the 0.1µL must be delivered exactly, with zero slack.
- `:flow_connection`: the only route for that NaOH is through the same physically constrained instrument flow.

No single constraint is the cause. Together they fix the delivered NaOH volume at a value that no
available instrument can produce. The hint at the end of the message, which the combination of
`:minimum_shot` with `:priority0` or `:mass_balance` triggers, names the fix: raise the dose or its
tolerance, or add an instrument with a smaller minimum shot.

### Raw solver logs and `InfeasibleSolveError`

By default (`quiet=true`), Pourfecto silences the console output of the optimizer. With
`quiet=false`, native solver text appears, such as the line `Solution count 0` from Gurobi,
immediately before an `InfeasibleSolveError` is raised. That text is the log of one `optimize!` call.
Planning can make several of these calls, one for each priority level, and each scheduling objective
adds its own. It is not a separate failure, and Pourfecto does not control its wording.
`InfeasibleSolveError` is the structured diagnosis of the same event and carries the `causes`. When
`quiet=false` produces this output, the error message begins with a note that says so.

## Slacks and solution quality

A solve that succeeds but produces a plan that does not closely match the requested targets is not
an infeasibility. [`slacks`](@ref) and the "Quality control and reporting" section of the
[Pourcasts](@ref pourfecto_pourcasts) page describe how to inspect and act on it.
