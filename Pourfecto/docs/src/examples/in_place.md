```@meta
EditURL = "../../../examples/in_place/in_place.jl"
```

# In-Place Transfers: Adjusting an Already-Seeded Plate

So far every example has filled empty target wells from scratch. Often
the target plate may already have reagents
in every well, and the next step is to add something to each well --
adjusting pH, dosing a stimulant -- without discarding what's already
there. Pourfecto calls this an **in-place transfer**: the source and
target are the same physical wells.

As an example, we will add sodium hydroxide to every well
of an already-filled plate to neutralize pH, keeping the
existing water and buffer intact.

```julia
using Pourfecto, CHESSCore, Unitful
```

## Reagents and labware

`existing_plate` represents the plate's current contents. `target_plate`
represents what we want each well to contain afterward -- the same water
and buffer, plus the NaOH addition. Because `Well.stock` is a single
mutable field, "current state" and "desired state" for the same physical
plate have to be two separate `Labware` objects; Pourfecto recognizes them
as the same plate by matching labware name and well name, not object
identity, so both are built with the same name.

```julia
water = string_to_reagent("water", Liquid)
buffer = string_to_reagent("buffer", Liquid)
naoh = string_to_reagent("naoh", Liquid)

existing_plate = build_location(location_kinds[:WP96], "assay_plate")
for w in vec(children(existing_plate))
    w.stock = 150u"µL" * water + 50u"µL" * buffer
end

target_plate = build_location(location_kinds[:WP96], "assay_plate")
for w in vec(children(target_plate))
    w.stock = 150u"µL" * water + 50u"µL" * buffer + 5u"µL" * naoh
end

naoh_reservoir = build_location(location_kinds[:DeepReservoir])
children(naoh_reservoir)[1].stock = 100u"mL" * naoh

configs = ["single_channel", "eight_channel_horizontal", "plate_master"]
```

Each well already holds 200 µL against a 400 µL physical capacity
(`CHESSCore.wellcapacity`), so there's comfortable headroom for the 5 µL
addition -- capacity isn't the constraint in this example, but it's the
real bound Pourfecto checks for in-place wells, not the declared target
total.

## A first attempt: forgetting to opt in

`existing_plate` and `target_plate` share the name `"assay_plate"`.
Pourfecto treats a source/target name collision as a likely mistake by
default -- reusing a name changes the physical meaning of the transfer --
so it's rejected unless you explicitly opt in:

```julia
try
    pourfecto([naoh_reservoir, existing_plate], [target_plate], configs)
catch e
    println(e)
end
```

## Setting up the in-place transfer

`allow_in_place=true` opts in to matching same-named labware. Once
matched, Pourfecto pins each existing well's content -- it's forced to
transfer at its full existing quantity into itself -- so nothing is lost,
and no other well can draw from it. NaOH gets priority `0` (must land
exactly, no slack) since it's the only thing actually being dosed here.

```julia
priority = PriorityDict("naoh" => UInt64(0))

pc = pourfecto([naoh_reservoir, existing_plate], [target_plate], configs;
    allow_in_place=true, priority=priority)
```

`transfers(pc)` is the source-by-target volume matrix; rows follow the
order sources were passed in: `[naoh_reservoir, existing_plate]`. For any
well, the existing-plate row should show its full 200 µL carried forward,
and the naoh_reservoir row should show exactly 5 µL.

## Incomplete target declaration

Suppose the existing plate also has a trace of a preservative that was omitted
in the target -- it's not something we're trying to
change, just an oversight:

```julia
preservative = string_to_reagent("preservative", Liquid)

existing_plate_2 = build_location(location_kinds[:WP96], "assay_plate_2")
for w in vec(children(existing_plate_2))
    w.stock = 150u"µL" * water + 50u"µL" * buffer + 2u"µL" * preservative
end

target_plate_2 = build_location(location_kinds[:WP96], "assay_plate_2")
for w in vec(children(target_plate_2))
    w.stock = 150u"µL" * water + 50u"µL" * buffer + 5u"µL" * naoh  # preservative omitted
end
```

This isn't a naming mistake -- `allow_in_place=true` is set correctly --
but it's still infeasible, for the same underlying reason explored in the
[priority example](priority.md): a reagent that's never declared in any
target defaults to priority `0` (blocked), which means its delivered
amount must equal its target exactly -- zero. The pin says the
preservative's existing 2 µL must carry forward; priority 0 says it must
be zero. Unlike the priority example, there's no alternate source to fall
back on here, so this isn't a silent shortfall -- it's a hard
infeasibility, and Pourfecto's own diagnostics recognize this exact
combination:

```julia
try
    pourfecto([naoh_reservoir, existing_plate_2], [target_plate_2], configs;
        allow_in_place=true, priority=priority)
catch e
    println(e)
end
```

The fix is simple: restate the full existing composition in the target,
not just the part you're changing.

```julia
target_plate_2_fixed = build_location(location_kinds[:WP96], "assay_plate_2")
for w in vec(children(target_plate_2_fixed))
    w.stock = 150u"µL" * water + 50u"µL" * buffer + 2u"µL" * preservative + 5u"µL" * naoh
end

pc2 = pourfecto([naoh_reservoir, existing_plate_2], [target_plate_2_fixed], configs;
    allow_in_place=true, priority=priority)
```

## The general lesson

An in-place well's *entire* existing composition needs to be restated in
its target -- not just the part you're adding or changing -- or given
explicit nonzero priority if you genuinely want it to be able to drift.
Leaving something out doesn't mean "don't care" here any more than it did
in the priority example; it means "blocked." The difference is that a
fresh, empty target well often has another source it can fall back on when
a reagent is blocked, so the result can be a silent inaccuracy. An
in-place well is pinned to its own existing content with no alternative
route, so the same mistake surfaces immediately as a hard infeasibility
instead.

---

*This page was generated using [Literate.jl](https://github.com/fredrikekre/Literate.jl).*

