```@meta
EditURL = "../../../examples/priority/priority.jl"
```

# Priority: Dosing a Poorly Water-Soluble Drug

This example works through a real dosing problem: we need to prepare wells
at a high and a low concentration of a drug that is only mildly soluble in
water but dissolves well in DMSO. We have two possible drug stocks: one
dissolved in water at a low, solubility-limited concentration, and one
dissolved in DMSO at a much higher concentration. DMSO is undesirable at
high concentrations (it's cytotoxic to cells), so we'd rather draw from the
water stock whenever the dose allows it, and only reach for the DMSO stock
when the water stock's low concentration makes that impossible. The rest of
each well is backfilled with water.

These goals compete: the water stock alone can't deliver a high dose
without exceeding a well's volume, but using the DMSO stock delivers DMSO
along with the drug. There's no way to hit an exact drug dose while also
guaranteeing zero DMSO. [`PriorityDict`](@ref) is exactly the tool for
expressing "get the drug dose right; prefer the water stock and minimize
DMSO; let backfill water make up the rest" -- and, as we'll see, it lets
Pourfecto *choose* which stock to draw from rather than us scripting it.

```julia
using Pourfecto, CHESSCore, Unitful, DataFrames
```

## Reagents and source labware

The water-based stock is dilute (0.1 µg of drug per µL of water), modeling
limited water solubility -- delivering a high dose from this stock alone
would require more volume than a well can hold. The DMSO-based stock is
concentrated (10 µg of drug per µL of DMSO), so a few microliters covers
even the high dose. A third reservoir supplies pure water for backfilling.

```julia
drug = string_to_reagent("drug", Solid)
dmso = string_to_reagent("dmso", Liquid)
water = string_to_reagent("water", Liquid)

water_drug_reservoir = build_location(location_kinds[:DeepReservoir])
children(water_drug_reservoir)[1].stock = 10u"mg" * drug + 100u"mL" * water

dmso_drug_reservoir = build_location(location_kinds[:DeepReservoir])
children(dmso_drug_reservoir)[1].stock = 100u"mg" * drug + 10u"mL" * dmso

water_reservoir = build_location(location_kinds[:DeepReservoir])
children(water_reservoir)[1].stock = 100u"mL" * water
```

## Target plate

The first row of the plate gets a high drug dose (50 µg), the second row a
low dose (5 µg), each backfilled to 200 µL with water. Delivering 50 µg from
the water stock alone would take 500 µL -- already more than a well holds --
so any feasible plan for the high-dose row needs some contribution from the
DMSO stock. Note that DMSO is never mentioned in a target's composition --
every well's declared DMSO target is implicitly zero.

```julia
target_plate = build_location(location_kinds[:WP96])

high_dose = 50u"µg"
low_dose = 5u"µg"
fill_volume = 200u"µL"

for col in 1:8
    children(target_plate)[1, col].stock = high_dose * drug + fill_volume * water
    children(target_plate)[2, col].stock = low_dose * drug + fill_volume * water
end

source_labware = [water_drug_reservoir, dmso_drug_reservoir, water_reservoir]
configs = ["single_channel", "eight_channel_horizontal", "plate_master"]
```

## A first attempt: priority without DMSO

It's tempting to only set a priority for the reagent we care about, the
drug, and leave DMSO alone:

```julia
naive_priority = PriorityDict("drug" => UInt64(1))
```

But [`PriorityDict`](@ref)'s default behavior is stricter than it looks,
and the failure mode it causes here is easy to miss. Any reagent that
appears only in source stocks -- never in a target's declared composition
-- is automatically assigned priority `0`, which means "blocked": its
delivered amount must match its target exactly. Since DMSO is never
declared in any target, its target amount is zero, and priority `0` forces
*zero net DMSO delivery to every well*.

With only one drug source this would make the model outright infeasible.
But because a second, DMSO-free source (the dilute water stock) exists,
Pourfecto can still find a solution -- it just quietly gives up on the
drug dose instead. `drug` is priority `1`, not `0`, so its slack isn't
required to be zero, only minimized, and with DMSO blocked the solver's
only option is to draw solely from the water stock:

```julia
pc_naive = pourfecto(source_labware, [target_plate], configs; priority=naive_priority)
```

## Setting priority explicitly

The fix is to give DMSO its own (nonzero) priority, ranked below the drug:
hit the drug dose first, then minimize DMSO (its target is zero, so
minimizing slack on it means minimizing how much is actually delivered)
subject to whatever the drug tier already locked in, and let water --
lowest priority -- absorb whatever volume is left over.

```julia
priority = PriorityDict(
    "drug" => UInt64(1),
    "dmso" => UInt64(2),
    "water" => typemax(UInt64),
)

pc = pourfecto(source_labware, [target_plate], configs; priority=priority)
```

## Comparing the naive and explicit runs

[`planned_stocks`](@ref) reconstructs what Pourfecto actually planned to
deliver to each well; [`target_stocks`](@ref) is what we asked for;
[`transfers`](@ref) is the full source-by-target volume matrix, which shows
exactly how much of each well came from the water-based drug stock versus
the DMSO-based drug stock. `CHESSCore.concentration` turns a
planned well's composition into a concentration for each species -- mass
per volume for the solid `drug`, volume fraction for the liquids `dmso` and
`water`. Since every well within a dose row is identical (nothing here
varies per well), one representative well per (run, dose) pair is enough
to compare the two runs side by side.

```julia
comparison = DataFrame()
for (run, pcast) in [("naive", pc_naive), ("explicit", pc)]
    planned = planned_stocks(pcast)
    requested = target_stocks(pcast)
    V = transfers(pcast)  # rows follow `source_labware` order: [water-drug, DMSO-drug, backfill water]
    for (dose, target) in [("high", high_dose), ("low", low_dose)]
        i = findfirst(t -> uconvert(u"µg", quantity(t, drug)) == target, requested)
        push!(comparison, (
            run=run,
            dose=dose,
            from_water_stock=V[1, i] * u"µL",
            from_dmso_stock=V[2, i] * u"µL",
            drug_conc=uconvert(u"µg/µL", concentration(planned[i], drug)),
            dmso_conc=uconvert(u"percent", concentration(planned[i], dmso)),
            water_conc=uconvert(u"percent", concentration(planned[i], water)),
        ))
    end
end

comparison
```

This page is generated without running a solver, so the block above only
shows the code that builds the table, not a live result. Running it
locally with a solver available (e.g. Gurobi) produces:

| Run      | Dose | Water Stock (µL) | DMSO Stock (µL) | Drug Conc. (µg/µL) | DMSO Conc. (%) | Water Conc. (%) |
|:---------|:-----|------------------:|------------------:|--------------------:|----------------:|-----------------:|
| Naive    | High | 200.0             | 0.0               | 0.100               | 0.0             | 100.0            |
| Naive    | Low  | 50.0              | 0.0               | 0.025               | 0.0             | 100.0            |
| Explicit | High | 197.0             | 3.0               | 0.2485              | 1.5             | 98.5             |
| Explicit | Low  | 50.0              | 0.0               | 0.025               | 0.0             | 100.0            |

The naive rows show the silent failure mode directly: `from_dmso_stock` is
zero in both (DMSO is blocked), which caps `drug_conc` on the high-dose row
well below the intended 0.25 µg/µL -- the water stock alone can't carry
more than that within a well's volume, so the shortfall shows up as a low
concentration with no error raised anywhere.

The explicit rows show the fix working as intended: `drug_conc` sits close
to target on both rows, `dmso_conc` is nonzero only on the high-dose row
(and is far smaller than it would be if DMSO alone supplied the whole
dose), and `from_water_stock` stays as large as the volume budget allows in
both cases -- Pourfecto leans on the dilute water stock first and tops up
with the concentrated DMSO stock only for what the water stock's volume
budget can't reach.

The general lesson: when a reagent you need is available from more than one
source, and one of those sources carries something undesirable, give the
undesirable carrier an explicit, low (but nonzero) priority. Leaving it
unset doesn't mean "don't care" -- it means "blocked," and depending on
whether an alternate, carrier-free route exists, that can either make the
plan infeasible outright or -- as it did here -- silently cap accuracy on
a reagent you thought you'd already prioritized.

---

*This page was generated using [Literate.jl](https://github.com/fredrikekre/Literate.jl).*

