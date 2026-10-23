# [Preparing a Stock by Hand](@id pourfecto_human)

```@meta
CurrentModule = Pourfecto
```

The `"human"` configuration plans a protocol in which a person weighs powders and measures liquids.
Pourfecto decides the amounts and the transfers. It does not plan mixing, filtering or labelling. A
program that needs those steps takes the planned steps as data and adds its own.

## Powders and liquids

A source that holds only solids, a `Mixture`, is a powder. A powder is weighed, and the planner counts
the amount drawn from it in milligrams. Every other source is measured by volume and counted in
microliters. [`amount_unit`](@ref) gives the unit of a source. Both units are on the same numeric scale,
so `min_vol_threshold` applies to a weighed amount in mg as it does to a volume in µL.

A powder adds no volume to its target. The capacity of a target well limits only the liquid that is
added, and the planned amount of the backfilling liquid, usually water, is therefore slightly more than
needed for a concentrated stock. The person brings the stock to its final volume.

## The `"human"` configuration

The head has two pistons that share one channel: a volume piston that measures from 1 mL to 10 L, and
a mass piston that weighs from 1 mg to 10 kg. A powder source can only be drawn by a mass piston and a
liquid source only by a volume piston ([`piston_dimension`](@ref)). If no configuration can draw a
source, `pourfecto` throws a `StockCompatibilityError` that names the well, before it solves anything.
A pipette configuration alone therefore rejects a powder, and in a run with `"human"` and `"p200"` the
powder is always weighed by the human while the liquids use either.

The limits apply when `enforce_minimum_shot=true`. A target that needs less than the smallest
amount is planned with the smallest amount, and `solution_quality` flags the difference. Volumes below
1 mL are better pipetted: include a pipette configuration in the same run.

A lab with different equipment builds its own configuration and registers it:

```julia
register_instrument!(human_configuration(min_mass=10u"mg", max_mass=2u"kg"); name="human_small_balance")
```

## The plan as data

[`protocol_steps`](@ref) returns the plan as a `DataFrame`, with one row for each transfer: its
`kind` (`"weigh"` or `"pipette"`), the `component`, the `amount` and its `unit`, the source labware and
well, the target labware and well, and the `instrument`.

```julia
pc = pourfecto(sources, targets, ["human"])
steps = protocol_steps(pc)
```

The rows are ordered by target well, then weighing before pipetting, then source well. The order is the
same for the same plan. Compiling a `Pourcast` writes `protocol_steps.csv` into the protocol folder of
the `Human` configuration, with the sources in the order of the protocol's slotting.

## Adjusting pH

Acid or base added to reach a pH is a planned amount like any other. Compute it with `CHESSCore.adjust_pH`,
which returns the stock with the titrant added, and use the result as the target. The titrant is then a
component of the target, and the plan draws it from a source of the titrant, liquid or solid.

## Re-planning a half-made stock

Use `allow_in_place=true` and declare the target in full: what the target already holds plus what it
still needs. The source labware is the half-made stock, and the target labware has the same name. The
content already in the well stays, and only the missing amounts are planned.

A declaration that leaves out something already in the well has no feasible plan, and `pourfecto` throws
an [`InfeasibleSolveError`](@ref). A declaration that asks for less of a component than the well holds
produces a plan that misses the target by more than the solution tolerance: `solution_quality` flags it,
and `pourfecto(directory, ...)` refuses to compile it.

## Dead volume

The `"human"` configuration adds no dead volume. `dead_volume_buffer` belongs to the Nimbus. A container's
residual volume is the business of the program that supplies the sources, which subtracts it before
planning.
