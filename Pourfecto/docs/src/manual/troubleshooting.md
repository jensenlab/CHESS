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

- `:mass_balance` -- the source composition can't be combined to hit a target's composition
- `:overdraft` -- a source doesn't have enough material for everything drawing on it
- `:capacity` -- a target (or a pinned in-place well) can't hold the volume assigned to it
- `:pinning` -- an in-place well's existing content conflicts with another constraint
- `:priority0` -- a priority-0 chemical (must match its target exactly, zero slack) can't be hit exactly

Scheduling-stage (instrument/config assignment, only present when scheduling with `pourfecto(source_labware, target_labware, configs; ...)`):

- `:flow_connection` -- a required transfer between two specific wells has no way to route through the available instrument flows
- `:invalid_flow` -- a specific aspirate/dispense pairing is physically impossible for a given config (wrong labware, mismatched piston, etc.)
- `:minimum_shot` -- a dispense is required to be either zero or above a config's minimum shot volume (only when `enforce_minimum_shot=true`), and neither option fits
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
