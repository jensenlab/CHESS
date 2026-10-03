# [Time complexity](@id pourfecto_complexity)

```@meta
CurrentModule = Pourfecto
```

This page analyzes the asymptotic cost of the **planning** and **scheduling** phases of
[`pourfecto`](@ref). [The `pourfecto` method](@ref pourfecto_method) describes the phases. The
analysis does not predict how long a specific problem takes. It identifies the structural factors
that determine how the time grows.

## Symbols

| Symbol | Meaning |
|---|---|
| `N_s` | number of source stocks |
| `N_t` | number of target stocks (wells) |
| `N_c` | number of distinct chemicals (reagents, water, etc.) across sources and targets |
| `K` | number of distinct priority levels in the supplied [`PriorityDict`](@ref) |
| `A`, `D` | number of aspirate and dispense flow nodes generated for the chosen instrument configurations |
| `#src_lw`, `#tgt_lw` | number of source and target labware objects |
| `C` | number of instrument configurations supplied |

`N_s`, `N_t`, and `N_c` come from the problem inputs. `A` and `D` come from the instrument
configurations and the labware geometry and are not raw well counts. See
[Scheduling phase](@ref pourfecto_complexity_scheduling) below.

## Planning phase

The planning phase builds one JuMP model with two blocks of variables:

- `V[N_s, N_t]` holds the transfer volume from each source to each target.
- `slacks[N_t, N_c]` holds the deviation between the planned and requested composition of each
  target.

This gives `O(N_s·N_t + N_t·N_c)` variables. The constraints are of the same order:

- a mass-balance constraint for each target and chemical pair (`N_t·N_c`),
- an overdraft constraint for each source (`N_s`),
- an overproduction constraint for each target (`N_t`),
- and, because `require_nonzero` defaults to `true`, up to one constraint for each target and
  chemical pair that requires a nonzero transfer when the chemical is needed (another `N_t·N_c`).

The dominant term is `O(N_s·N_t + N_c·N_t)`.

The planning objective is always a quadratic program, whatever the `objective` keyword says. The
planning solve minimizes a weighted sum of squared slacks one priority level at a time, and
`objective` takes effect afterward, in the scheduling phase. Each distinct priority value in the
`PriorityDict` triggers a new solve of the QP, with the slacks of the previous level frozen into a
tolerance band before the next level is optimized. The planning phase therefore issues `K` QP
solves, plus a few fixed-cost solves at the end, each over the model above with
`O(N_s·N_t + N_c·N_t)` variables. `K` multiplies the planning cost directly, so a priority scheme
with many levels costs more than one with few.

The planning problem is a quadratic program and not a linear program, so the choice of QP algorithm
matters as much as the problem size. Active-set methods scale poorly as the number of variables
grows, and interior-point (barrier) methods handle the growth much better. The difference is one of
algorithm class and not only of implementation. [Choosing a solver](@ref pourfecto_choosing_a_solver)
lists which bundled solvers use which method.

## [Scheduling phase](@id pourfecto_complexity_scheduling)

The scheduling phase reuses the planning model and adds a flow matrix `Q[A, D]`. `A` and `D` count
aspirate and dispense flow nodes and not raw wells. A flow node is generated for each
`(instrument configuration, labware)` pair, once for each piston and once for each valid head
position on that labware. The node count of a configuration therefore depends on how its head
geometry compares with the well grid of the labware:

| Configuration | Aspirate/dispense node scaling |
|---|---|
| `single_channel` | one node per well (no reduction) |
| `eight_channel_*` | roughly one node per 8 wells (the width of the head divides out along one axis) |
| `tempest` | aspirate: 8 nodes per source bottle, independent of well count (piston-bound); dispense: roughly one node per well |

Additional configurations add to `A` and `D` and do not multiply them, with one contribution for
each configuration and labware pair. Twice as many configurations roughly double the node count and
do not square it.

Building the connectivity between flow nodes and wells takes close to linear time for instruments
with well-localized masks: single-channel, eight-channel, and the dispense side of the Tempest. For
blanket-style masks, such as reservoirs, that connect densely to every well, the cost can grow
toward `O(N_s·N_t·A·D)`. The nested loop that checks flow validity and computes padding factors for
every `(a, d)` pair is `O(A·D)`, and each check is `O(1)`. A check compares a few precomputed scalar
fields and makes a small, fixed-size deck-slot check. It never re-evaluates mask geometry, because
masks are built once for each configuration and labware pair and reused.

Setting `enforce_minimum_shot = true` adds a block of `A·D` **binary** variables and `2·A·D` linear
constraints. This turns the model into a mixed-integer program whichever `objective` is chosen.

## Objective choice

The `objective` keyword has the largest effect on the complexity of the scheduling phase, because
most non-default objectives introduce integer variables:

| Objective | New integer variables | Complexity class |
|---|---|---|
| `min_cost_flow` (default) | none | LP |
| `regularize_flows` | none | QP |
| `min_active_flow` | `A·D` binaries | MILP |
| `min_aspirations` | `A·D` binaries, plus `A` integers | MILP |
| `min_sources` | `N_s` binaries | MILP |
| `min_labware` | `#src_lw·#tgt_lw` binaries | MILP |
| `min_config` | `C` binaries | MILP |

[Choose a scheduling objective](@ref) describes how to select one. Only `min_cost_flow` and
`regularize_flows` keep the scheduling phase free of integer variables. Every other objective makes
it a MILP, which is NP-hard in the worst case and whose practical runtime depends on the behavior of
branch and bound, with no closed-form bound.

A vector of objectives is solved once for each entry. When `enforce_minimum_shot = false`,
`min_active_flow` and `min_aspirations` each build their own `A·D` block of binaries. Combining
either of them with another objective, without `enforce_minimum_shot`, pays the cost of that block
more than once.

## Compilation

Post-processing a solved [`Pourcast`](@ref) into instrument files with `compile` (see
[Compiling Pourcasts](@ref pourfecto_compiling)) takes polynomial time in the dimensions of the
solved matrices. Aggregating transfers and flows by configuration is roughly `O(N_s·N_t)` and
`O(A·D)`, and slotting labware onto deck positions is `O(C·N_s·N_t)`. The flow-node connectivity
computed during scheduling is computed again during compilation and is not reused. This is a
redundancy of roughly a factor of 2 and does not change the complexity class.

## Practical guidance

In the common case, with the default `objective = "min_cost_flow"`, `enforce_minimum_shot = false`,
and a well-localized instrument configuration, the cost is dominated by `N_t`, the well count. It
appears in `N_s·N_t` and `N_c·N_t`, and for single-channel, eight-channel, and Tempest-style
configurations in `A` and `D` as well.

The number of priority levels `K` multiplies the planning cost directly, so a scheme with fewer
levels needs fewer QP solves. The largest effect comes from the objective. With `min_cost_flow` or
`regularize_flows`, the whole problem remains an LP or QP. Any other objective, or
`enforce_minimum_shot = true`, adds blocks of integer variables of size `O(A·D)` or larger and
makes the problem a MILP.
