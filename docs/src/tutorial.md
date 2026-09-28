# Tutorial: A Growth Experiment

```@meta
DocTestSetup = :(using CHESS)
```

This tutorial follows one small experiment from start to finish: setting up a lab, preparing
media, inoculating a plate, incubating and reading it, correcting a recording mistake, and then
looking back at the plate's state at earlier points in its history. Each step links to the manual
chapter that covers it in depth.

Every example on this page runs as written, in order, in one Julia session.

## Set up a database

CHESS records operations in a SQLite database. [`create_db`](@ref) creates one and
[`connect_SQLite`](@ref) makes it the database every later call uses. This tutorial uses a
temporary file:

```jldoctest tutorial
julia> using CHESS, Dates

julia> path = joinpath(mktempdir(), "lab.db");

julia> create_db(path);

julia> connect_SQLite(path)
```

See [Database Architecture](manual/db-architecture.md) for what the database contains.

## Build the lab

[`generate_location`](@ref) builds a location and commits it to the database in one step, giving it
a permanent ID. The lab is a room with a bench, an incubator, and a plate reader, all kinds that
`using CHESS` already registers:

```jldoctest tutorial
julia> room = generate_location(loc"Room", "Room 101");

julia> bench = generate_location(loc"Bench", "Bench 1");

julia> incubator = generate_location(loc"Incubator", "Incubator");

julia> reader = generate_location(loc"Epoch2", "Plate reader");
```

Once a location is committed, every change to it goes through [`upload`](@ref), which applies the
change in memory and records it in the database together. `upload` returns the ledger ID of the
new record:

```jldoctest tutorial
julia> for x in (bench, incubator, reader); upload(move_into!, room, x); end
```

See [Locations](manual/core-concepts.md), [Movement & Occupancy](manual/movement.md), and
[Committing & Uploading](manual/committing-uploading.md).

## Prepare media and a starter culture

Material that already exists before the experiment starts, like a bottle of media, is built in
memory with [`build_location`](@ref), filled with [`deposit!`](@ref), and then committed with
[`commit_location!`](@ref). `stock"lb_1000mL"` is CHESS's registered recipe for a liter of LB broth;
multiplying it by a volume scales it:

```jldoctest tutorial
julia> bottle = build_location(loc"Bottle500mL", "LB bottle");

julia> deposit!(bottle["A1"], 250u"mL" * stock"lb_1000mL")

julia> bottle = commit_location!(bottle);
```

The starter culture is 5 mL of LB with 10 mL·OD of *S. mutans* biomass, in a 15 mL conical tube:

```jldoctest tutorial
julia> tube = build_location(loc"Conical15", "Starter culture");

julia> deposit!(tube["A1"], 5u"mL" * stock"lb_1000mL" + 10u"OD*mL" * org"SMU_UA159")

julia> tube = commit_location!(tube);

julia> for x in (bottle, tube); upload(move_into!, bench, x); end
```

`commit_location!` returns a new, committed location, so the variables are reassigned to its
result. See [Stocks](manual/stocks.md) and [Organisms & Cultures](manual/organisms-cultures.md).

## Fill and inoculate a plate

Wells A1 to A3 each get 198 µL of LB. A1 and A2 are then inoculated with 2 µL of the starter
culture, and A3 is left as a blank. The ledger IDs of the two inoculations are kept for later:

```jldoctest tutorial
julia> plate = generate_location(loc"WP96", "Growth plate");

julia> upload(move_into!, bench, plate);

julia> for w in ("A1", "A2", "A3"); upload(transfer!, bottle["A1"], plate[w], 198u"µL"); end

julia> inoculations = [upload(transfer!, tube["A1"], plate[w], 2u"µL") for w in ("A1", "A2")];

julia> stock(plate["A1"])
200 μL Culture (2 reagent(s))
 Organisms  Name                        Biomass     OD
──────────────────────────────────────────────────────────────
 SMU_UA159  Streptococcus mutans UA159  4.00 μL OD  0.0200 OD

 Solids  Name      Amount   Concentration
──────────────────────────────────────────
 lb      LB Broth  5.00 mg   25.0 mg mL⁻¹

 Liquids  Name   Amount  Concentration
───────────────────────────────────────
 water    water  200 μL          100 %
```

The well now holds 200 µL, with 4.00 µL·OD of *S. mutans* biomass.

See [Wells: Depositing & Transferring Material](manual/wells.md).

## Incubate

The incubator is set to 37 °C, and the plate goes onto its first shelf. The wells inherit the
incubator's temperature through the location hierarchy:

```jldoctest tutorial
julia> upload(set_attribute!, incubator, attr"Temperature"(37u"°C"));

julia> upload(move_into!, incubator[1], plate);

julia> environment(plate["A1"])
Dict{Symbol, Attribute} with 1 entry:
  :Temperature => 37.0 °C
```

See [Environmental Attributes & Inheritance](manual/attributes.md).

## Read the plate

After incubation, the plate moves into the reader and each well's absorbance is recorded.
Passing `instrument=reader` checks that the reader can record reads and stores which instrument
took them:

```jldoctest tutorial
julia> upload(move_into!, reader[1], plate);

julia> for (w, od) in (("A1", 0.42), ("A2", 0.39), ("A3", 0.05))
           upload(record_read!, plate[w], read"Absorbance"(od * u"OD"); instrument=reader)
       end

julia> reads(plate["A1"])
1-element Vector{Read}:
 0.42 OD
```

See [Reads & Instrument Measurements](manual/reads.md) and
[Instrument Interfaces](manual/instrument-interfaces.md).

## Correct a mistake

Suppose the A2 inoculation was actually 4 µL, not 2 µL. [`update`](@ref) with `replace` records a
new revision of that entry, at the same point in the history. The time just before the
correction is kept so the next section can look back at what was recorded then:

```jldoctest tutorial
julia> recorded_before_fix = now();

julia> sleep(1)  # only so that the correction gets a later timestamp in this quick demo

julia> update(transfer!, tube["A1"], plate["A2"], 4u"µL"; replace=get_sequence_id(inoculations[2]));
caches updated: 0
```

`update` also applies the transfer to the in-memory objects it is given, so `plate` and `tube` now
hold both the original and the corrected transfer. The database holds the corrected history, and
[`reconstruct_location`](@ref) rebuilds a location from it:

```jldoctest tutorial
julia> a2 = CHESSCore.location_id(plate["A2"]);

julia> stock(reconstruct_location(a2))
202 μL Culture (2 reagent(s))
 Organisms  Name                        Biomass     OD
──────────────────────────────────────────────────────────────
 SMU_UA159  Streptococcus mutans UA159  8.00 μL OD  0.0396 OD

 Solids  Name      Amount   Concentration
──────────────────────────────────────────
 lb      LB Broth  5.05 mg   25.0 mg mL⁻¹

 Liquids  Name   Amount  Concentration
───────────────────────────────────────
 water    water  202 μL          100 %
```

See [The Ledger](manual/ledger.md) and [Caching & Repair](manual/caching-repair.md).

## Look back in time

Because CHESS stores operations rather than states, any earlier state can be rebuilt.
`reconstruct_location` takes a sequence ID, a position in the history. Just before the
inoculation, A2 held only LB:

```jldoctest tutorial
julia> stock(reconstruct_location(a2, get_sequence_id(inoculations[2]) - 1))
198 μL Solution (2 reagent(s))
 Solids  Name      Amount   Concentration
──────────────────────────────────────────
 lb      LB Broth  4.95 mg   25.0 mg mL⁻¹

 Liquids  Name   Amount  Concentration
───────────────────────────────────────
 water    water  198 μL          100 %
```

It also takes a recording time, which shows what the database said at that moment, before the
correction was made:

```jldoctest tutorial
julia> stock(reconstruct_location(a2, get_last_sequence_id(), recorded_before_fix))
200 μL Culture (2 reagent(s))
 Organisms  Name                        Biomass     OD
──────────────────────────────────────────────────────────────
 SMU_UA159  Streptococcus mutans UA159  4.00 μL OD  0.0200 OD

 Solids  Name      Amount   Concentration
──────────────────────────────────────────
 lb      LB Broth  5.00 mg   25.0 mg mL⁻¹

 Liquids  Name   Amount  Concentration
───────────────────────────────────────
 water    water  200 μL          100 %
```

See [Reconstruction](manual/reconstruction.md).

## Where to go next

The [Manual](manual/core-concepts.md) covers each of these topics in depth, starting with
[Locations](manual/core-concepts.md). To plan liquid-handling steps like the plate filling above
automatically, see [Pourfecto](https://jensenlab.github.io/CHESS/pourfecto/dev/). To load real
plate-reader exports instead of typing values, see
[Parsing Instrument Files](manual/parsing-instrument-files.md).
