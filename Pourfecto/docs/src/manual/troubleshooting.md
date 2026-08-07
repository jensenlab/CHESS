# Troubleshooting Solver Failures

Pourfecto's planning and scheduling models can fail in a few distinct ways. This page describes
each failure mode, what error it raises, and how to read the resulting message.

## `ChemicalShortageError`

Raised by `check_inputs` before any model is built, when the *total* supply of a chemical across
all sources is less than the *total* demand across all targets. This is a coarse, aggregate check
-- it can pass even when the per-well plan is still infeasible (see `InfeasibleSolveError` below),
because it doesn't account for which source can reach which target.

The error carries a `balances` field: a `Dict{Reagent,Unitful.Quantity}` of the shortfall for each
chemical that failed the check.

## `InfeasibleSolveError`

Raised when the planning or scheduling model itself has no feasible solution -- the solver
returned `MOI.INFEASIBLE` (or `MOI.INFEASIBLE_OR_UNBOUNDED`). Unlike a generic solver error, this
carries a `causes` field: a list of the specific constraints the solver identified as jointly
responsible, each with a `category` and a human-readable `description`.

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

Possible categories:

Planning-stage (volumes only, no instruments):

- `:mass_balance` -- the source composition can't be combined to hit a target's composition (see `require_nonzero`, `min_vol_threshold`)
- `:overdraft` -- a source doesn't have enough material for everything drawing on it
- `:capacity` -- a target (or a pinned in-place well) can't hold the volume assigned to it (see `allow_in_place`)
- `:pinning` -- an in-place well's existing content conflicts with another constraint (see `allow_in_place`)
- `:priority0` -- a priority-0 chemical (must match its target exactly, zero slack) can't be hit exactly (see `priority`)

Scheduling-stage (instrument/config assignment, only present when scheduling with `pourfecto(source_labware, target_labware, configs; ...)`):

- `:flow_connection` -- a required transfer between two specific wells has no way to route through the available instrument flows
- `:invalid_flow` -- a specific aspirate/dispense pairing is physically impossible for a given config (wrong labware, mismatched piston, etc.)
- `:minimum_shot` -- a dispense is required to be either zero or above a config's minimum shot volume (only when `enforce_minimum_shot=true`), and neither option fits (see `enforce_minimum_shot`)
- `:source_flow_overdraft` -- a source can't supply everything drawing on it once instrument dead-volume padding is included

When several categories co-occur, the message includes a short interpretation of the likely root
cause -- for example, `:pinning` together with `:priority0` usually means an in-place well's
existing content includes a chemical the target never declares, which defaults that chemical to
priority 0 (must be exactly zero) while the pin forces its existing amount to carry forward.
`:invalid_flow` showing up at all usually means no configured instrument can physically reach both
wells involved in a required transfer -- add a compatible configuration, or remove the transfer.
`:minimum_shot` alongside `:priority0`/`:mass_balance` usually means a required dose is smaller
than every available config's minimum shot volume.

### Detailed vs. generic messages

Attributing a conflict to specific constraints requires the active optimizer to support conflict
(IIS) analysis. Gurobi and HiGHS both support this; SCIP does not. When conflict analysis isn't
available, `InfeasibleSolveError` still identifies the priority level (or scheduling stage) at
which the solve failed, but `causes` is empty and the message falls back to a generic "check your
targets, sources, and pinned wells" hint. Passing `optimizer=Gurobi.Optimizer` or
`optimizer=HiGHS.Optimizer` will produce a detailed breakdown for the same problem.

### Scheduling-stage infeasibility

`InfeasibleSolveError` can also be raised while scheduling (the instrument/config assignment
stage), reported with `level = "scheduling"`. This happens when the planned volumes are
achievable in principle but no valid combination of instruments and configurations can physically
execute them -- most commonly a required dose that falls below every available config's minimum
shot volume when `enforce_minimum_shot=true`. Note that `build_scheduling_model` folds instrument
constraints into the same joint model `solve_planning_model` iterates over, so this kind of
infeasibility is often reported at a priority level rather than at `"scheduling"` -- the level in
the message reflects where the solver actually detected it, not which stage introduced the
constraint.

### Worked example

Every well of a target plate needs a 0.1µL dose of NaOH, but the only available instrument
(`plate_master`) has a 1µL minimum shot -- with `enforce_minimum_shot=true`, each dispense must be
either exactly 0 or at least 1µL, and 0.1µL is neither:

```julia
water = string_to_reagent("water", Liquid)
X = string_to_reagent("X", Liquid)
NaOH = string_to_reagent("NaOH", Liquid)

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

This raises an `InfeasibleSolveError` whose message reads:

```text
the problem is infeasible at priority level 0. The following constraints cannot be satisfied together:
  - physical minimum-shot constraint: config "Gilson" dispensing onto labware "min_shot_target" requires each dispense to be 0 or at least 1 µL
  - mass/volume balance constraint linking source composition to well F11 of labware "min_shot_target" for chemical "NaOH"
  - priority-0 exact-match constraint requires 0 slack for chemical "NaOH" across all targets
  - flow-routing constraint requires transfers from well A1 of labware "..." to well F11 of labware "min_shot_target" to be carried entirely by available instrument flows
This usually means a required dose falls below every available configuration's minimum shot volume -- either allow a larger dose/slack, or add a configuration with a smaller minimum shot.
```

Reading the four causes together:

- `:minimum_shot` -- `plate_master`'s "Gilson" config can only dispense 0 or ≥1µL onto this plate
- `:mass_balance` -- the plan needs exactly 0.1µL of NaOH delivered to well F11 to hit the target
- `:priority0` -- NaOH is priority 0, so that 0.1µL must be delivered *exactly*, with zero slack
- `:flow_connection` -- the only route for that NaOH is through the same physically-constrained instrument flow

None of these is individually the "bug" -- together they pin the delivered NaOH volume to a value
no available instrument can produce. The auto-generated hint at the bottom (triggered by the
`:minimum_shot` + `:priority0`/`:mass_balance` combination described above) names the fix
directly: raise the dose (or its tolerance), or add a finer-grained instrument.

### Raw solver logs vs. `InfeasibleSolveError`

By default (`quiet=true`), Pourfecto silences the underlying optimizer's own console output.
Passing `quiet=false` re-enables it, so you may see native solver text -- for example, Gurobi
printing `Solution count 0` -- immediately before an `InfeasibleSolveError` is raised. That text is
the solver's own log for one particular `optimize!` call (planning can call it several times, once
per priority level, plus scheduling objectives each add their own); it isn't a separate failure and
isn't something Pourfecto controls the wording of. `InfeasibleSolveError` is Pourfecto's own
structured diagnosis of that same event, and it's what carries the `causes`. When `quiet=false`
triggers this, the error message is prefixed with a note pointing this out.

## Slacks and solution quality

If a solve *succeeds* but produces a plan that doesn't closely match the requested targets, that's
not an infeasibility -- see [`slacks`](@ref) and the "Quality Control and Reporting" section of the
[Pourcasts](@ref pourfecto_pourcasts) manual page for how to inspect and act on that.
