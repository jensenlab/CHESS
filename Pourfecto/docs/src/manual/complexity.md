# [Time complexity](@id pourfecto_complexity)

```@meta
CurrentModule = Pourfecto
```

This page analyzes the asymptotic cost of [`pourfecto`](@ref)'s **planning** and **scheduling**
phases (see [The `pourfecto` method](@ref pourfecto_method) for what those phases do). It answers
a different question than a specific timed run: not "how long did this problem take," but "which
structural factors determine how that time grows."

## Symbols

| Symbol | Meaning |
|---|---|
| `N_s` | number of source stocks |
| `N_t` | number of target stocks (wells) |
| `N_c` | number of distinct chemicals (reagents, water, etc.) across sources and targets |
| `K` | number of distinct priority levels in the supplied [`PriorityDict`](@ref) |
| `A`, `D` | number of aspirate / dispense flow nodes generated for the chosen instrument configurations |
| `#src_lw`, `#tgt_lw` | number of source / target labware objects |
| `C` | number of instrument configurations supplied |

`N_s`, `N_t`, and `N_c` come directly from the problem inputs. `A` and `D` are derived from the
instrument configurations and labware geometry, not from raw well counts — see
[Scheduling phase](@ref pourfecto_complexity_scheduling) below.

## Planning phase

The planning phase builds one JuMP model with two variable blocks:

- `V[N_s, N_t]` — transfer volume from each source to each target.
- `slacks[N_t, N_c]` — deviation between the planned and requested composition of each target.

That's `O(N_s·N_t + N_t·N_c)` variables. Constraints are the same order: a mass-balance
constraint per target/chemical pair (`N_t·N_c`), one overdraft constraint per source (`N_s`), one
overproduction constraint per target (`N_t`), and — since `require_nonzero` defaults to `true` —
up to one constraint per target/chemical pair requiring a nonzero transfer whenever a chemical is
actually needed (another `N_t·N_c`). The dominant term is `O(N_s·N_t + N_c·N_t)`.

The objective is **always a quadratic program**, independent of the `objective` keyword: the
planning solve minimizes a weighted sum of squared slacks, one priority level at a time, and
`objective` only takes effect afterward, in the scheduling phase. Each distinct priority value in
the supplied `PriorityDict` triggers its own re-solve of this QP, with the previous level's slacks
frozen into a tolerance band before the next level is optimized — so the planning phase issues
`K` QP solves (plus a couple of fixed-cost fixup solves at the end), each over the
`O(N_s·N_t + N_c·N_t)`-variable model above. `K` is a direct multiplier on planning cost: a
priority scheme with many distinct levels costs proportionally more than one with few.

Because this is a genuine QP (not a linear program), the choice of QP algorithm matters as much
as problem size. Active-set QP methods scale poorly as the variable count grows; interior-point
("barrier") methods handle the same growth much better. This is an algorithm-class distinction,
not just an implementation detail — see [Choosing a solver](@ref pourfecto_choosing_a_solver) for
which bundled solvers use which method.

## [Scheduling phase](@id pourfecto_complexity_scheduling)

The scheduling phase reuses the planning model and adds a flow matrix `Q[A, D]`, where `A` and
`D` are counts of aspirate/dispense "flow nodes" — not raw well counts. A flow node is generated
per `(instrument configuration, labware)` pair, once per piston and once per valid head position
on that labware; the node count for a given configuration therefore depends on how its head
geometry compares to the labware's well grid:

| Configuration | Aspirate/dispense node scaling |
|---|---|
| `single_channel` | one node per well (no reduction) |
| `eight_channel_*` | roughly one node per 8 wells (the head's width divides out along one axis) |
| `tempest` | aspirate: 8 nodes per source bottle, independent of well count (piston-bound); dispense: roughly one node per well |

Supplying more configurations adds an **additive** term to `A`/`D` (one contribution per
config/labware pair), not a multiplicative one — using twice as many configurations roughly
doubles node count, it doesn't square it.

Building the flow-node-to-well connectivity is near-linear for instruments whose masks are
well-localized (single-channel, eight-channel, Tempest's dispense side), but can degrade toward
`O(N_s·N_t·A·D)`-shaped cost for blanket-style masks (e.g. reservoirs) with dense connectivity to
every well. The subsequent nested loop that checks flow validity and computes padding factors for
every `(a, d)` pair is genuinely `O(A·D)`, though each individual check is `O(1)` — it only
compares a few precomputed scalar fields and a small, fixed-size deck-slot check, never
re-evaluating mask geometry (masks are built once per configuration/labware pair and reused).

Setting `enforce_minimum_shot = true` unconditionally adds an `A·D`-sized block of **binary**
variables and `2·A·D` linear constraints, turning the model into a mixed-integer program
regardless of which `objective` is chosen.

## Objective choice

The `objective` keyword is the single largest lever a caller controls over scheduling-phase
complexity, because most non-default objectives introduce integer variables:

| Objective | New integer variables | Complexity class |
|---|---|---|
| `min_cost_flow` (default) | none | LP |
| `regularize_flows` | none | QP |
| `min_active_flow` | `A·D` binaries | MILP |
| `min_aspirations` | `A·D` binaries, plus `A` integers | MILP |
| `min_sources` | `N_s` binaries | MILP |
| `min_labware` | `#src_lw·#tgt_lw` binaries | MILP |
| `min_config` | `C` binaries | MILP |

See [Choose a scheduling objective](@ref) for how to select these. Only `min_cost_flow` and
`regularize_flows` keep the scheduling phase free of integer variables; every other objective
turns it into a MILP, which is NP-hard in the worst case and whose practical runtime depends on
branch-and-bound behavior rather than a closed-form bound. Supplying a vector of objectives
re-solves once per entry, and `min_active_flow`/`min_aspirations` each construct their own fresh
`A·D`-binary block when `enforce_minimum_shot = false` — combining either of them with another
objective, without `enforce_minimum_shot`, pays that `A·D` binary cost more than once.

## Compilation

Post-processing a solved [`Pourcast`](@ref) into instrument files (`compile`, see
[Compiling Pourcasts](@ref pourfecto_compiling)) is polynomial in the already-solved matrix dimensions: aggregating
transfers and flows by configuration is roughly `O(N_s·N_t)`/`O(A·D)`, and slotting labware onto
deck positions is `O(C·N_s·N_t)`. The one inefficiency worth noting is that the flow-node
connectivity computed during scheduling is recomputed from scratch during compilation rather than
reused — a constant-factor (roughly 2x) redundancy, not a change in complexity class.

## Practical guidance

In the common case — default `objective = "min_cost_flow"`, `enforce_minimum_shot = false`, and a
well-localized instrument configuration — overall cost is dominated by `N_t` (well count), since
it appears in `N_s·N_t`, `N_c·N_t`, and (for single-channel/eight-channel/Tempest-style
configurations) `A`/`D` alike. The number of distinct priority levels `K` multiplies planning cost
directly, so consolidating a priority scheme into fewer levels reduces the number of QP re-solves.
The biggest single lever, though, is objective choice: staying on `min_cost_flow` (or
`regularize_flows`) keeps the whole problem an LP/QP; any other objective, or
`enforce_minimum_shot = true`, introduces `O(A·D)`-or-larger blocks of integer variables and moves
the problem into MILP territory.
