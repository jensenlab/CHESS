# Experimental Designs

```@meta
DocTestSetup = :(using CHESS, CHESSExperiments, DataFrames)
```

`CHESSExperiments` describes what an experiment is meant to test, before anything is prepared: a
design matrix of treatments, the factors its columns stand for, and the controls and replicates it
needs. It turns that design into `CHESSCore` stocks and per-plate conditions, and, with `RunMaps`
and `PlateMaps` loaded, into a plate layout. It is a separate package that is loaded separately
from `CHESS`.

## Experiments

An [`Experiment`](@ref) has two fields. `design` is a `DataFrame` with one row per planned trial and
one column per factor; a treatment run three times is the same row three times. `metadata` holds
everything that describes, schedules, or processes the design without being part of it: the name,
the plate layout once scheduled, per-plate conditions, and so on.

```jldoctest experiments
julia> using CHESSExperiments

julia> expt = Experiment(DataFrame(glucose = [10, 5]); name = "glucose screen");

julia> get_parameter(expt, :name)
"glucose screen"
```

Metadata keys can be registered as a [`ParameterKind`](@ref) with [`register_parameter!`](@ref),
giving them a type, a default, and an optional validator that [`get_parameter`](@ref) enforces.
[`parameter_registry`](@ref) holds the registered kinds, keyed by name.
Unregistered keys remain ordinary `Dict` entries. [`with_parameter`](@ref) returns a copy of the
experiment with one key set, leaving the original unchanged.

## How design columns are read

Every column in a design must mean something CHESS understands. [`factor_destination`](@ref) checks
a column name in this order:

1. One of the [`RESERVED_DESIGN_COLUMNS`](@ref) (`:control_role`, `:duplicates`), used by
   scheduling.
2. A registered reagent: the column holds an amount of that reagent (destination `:reagent`).
3. A registered organism: the column holds a biomass of that organism (destination `:organism`).
4. A registered [`Factor`](@ref), which names its own destination, usually `:condition`.

Anything else is an error. Reagent and organism columns need no registration of their own, since
CHESS already knows those names. Other factors do. A [`CategoricalFactor`](@ref) takes values from
a set of levels; a [`ContinuousFactor`](@ref) is numeric. Either can be *blocking*: two rows that
differ in a blocking factor must never share a plate, as with an incubation atmosphere:

```jldoctest experiments
julia> register_factor!(CategoricalFactor(:atmosphere;
           levels = () -> (:aerobic, :anaerobic), blocking = true, destination = :condition));
```

[`factor_registry`](@ref) holds the registered factors, keyed by name, and [`get_factor`](@ref) looks one
up and raises a `KeyError` for an unregistered name. [`factor_levels`](@ref) returns the currently
valid levels of a categorical factor, and [`is_blocking`](@ref) tests whether a factor is blocking:

```jldoctest experiments
julia> factor = get_factor(:atmosphere);

julia> factor_levels(factor)
(:aerobic, :anaerobic)

julia> is_blocking(factor)
true
```

Registering a name that is already taken raises a [`DuplicateRegistrationError`](@ref).

## Parsing a spreadsheet

[`parse_design`](@ref) reads a design from a CSV file. Spreadsheet headers and values rarely match
CHESS's names, so a [`DesignColumnMap`](@ref) translates them for this one file: `columns` maps each
header to a factor name, `values` maps free-text cell values, and `units` gives one unit per reagent
or organism column. Here glucose is a concentration, the *S. mutans* inoculum is a biomass, and the
last two rows are control templates (see [Controls and replicates](#Controls-and-replicates)):

```jldoctest experiments
julia> path = joinpath(mktempdir(), "design.csv");

julia> write(path, """
       Glucose (g/L),S. mutans (OD*mL),Atmosphere,control_role
       10,0.01,aerobic,
       5,0.01,aerobic,
       10,0.01,anaerobic,
       5,0.01,anaerobic,
       0,0.01,,positive
       0,,,negative
       """);

julia> cmap = DesignColumnMap(
           columns = Dict("Glucose (g/L)" => :glucose, "S. mutans (OD*mL)" => :SMU_UA159,
                          "Atmosphere" => :atmosphere),
           values = Dict(:atmosphere => Dict("aerobic" => :aerobic, "anaerobic" => :anaerobic)),
           units = Dict(:glucose => "g/L", :SMU_UA159 => "OD*mL"));

julia> ctx = [CHESSCore, CHESSLabConstants];

julia> expt = parse_design(path; column_map = cmap, reagent_context = ctx, org_context = ctx);

julia> expt.design
6×4 DataFrame
 Row │ glucose  SMU_UA159   atmosphere  control_role
     │ Int64    Float64?    Symbol?     String15?
─────┼───────────────────────────────────────────────
   1 │      10        0.01  aerobic     missing
   2 │       5        0.01  aerobic     missing
   3 │      10        0.01  anaerobic   missing
   4 │       5        0.01  anaerobic   missing
   5 │       0        0.01  missing     positive
   6 │       0  missing     missing     negative

julia> classify_columns(propertynames(expt.design); reagent_context = ctx, org_context = ctx)
(reagent = [:glucose], organism = [:SMU_UA159], condition = [:atmosphere])
```

`reagent_context` and `org_context` list the modules whose registered names count, here CHESS's
own constants. [`is_registered_reagent`](@ref) is the test that identifies a reagent column:

```jldoctest experiments
julia> is_registered_reagent(:glucose; reagent_context = ctx), is_registered_reagent(:atmosphere; reagent_context = ctx)
(true, false)
```

 The column map is stored in the experiment's metadata, so the translation stays on
record.

## Resolving a row

[`resolve_stock`](@ref) turns one row's reagent and organism columns into a single `CHESSCore`
[`Stock`](@ref). Concentrations need a total volume, and `solvent` fills whatever volume the other
reagents leave. It also returns each organism's biomass value, for per-well records:

```jldoctest experiments
julia> stock, organisms = resolve_stock(expt.design[1, :], [:glucose], [:SMU_UA159];
           units = cmap.units, reagent_context = ctx, org_context = ctx,
           total_volume = 200u"µL", solvent = :water);

julia> stock
200 μL Culture (2 reagent(s))
 Organisms  Name                        Biomass     OD
──────────────────────────────────────────────────────────────
 SMU_UA159  Streptococcus mutans UA159  10.0 μL OD  0.0500 OD

 Solids   Name       Amount   Concentration
────────────────────────────────────────────
 glucose  D-glucose  2.00 mg   10.0 mg mL⁻¹

 Liquids  Name   Amount  Concentration
───────────────────────────────────────
 water    water  200 μL          100 %

julia> organisms
Dict{Symbol, Any} with 1 entry:
  :SMU_UA159 => 0.01
```

[`resolve_conditions`](@ref) returns a row's `:condition` values as a plain `Dict`, checking
categorical values against their levels. Conditions are only recorded. A plate cannot be set to
"anaerobic" the way a well can be filled.

```jldoctest experiments
julia> resolve_conditions(expt.design[1, :], [:atmosphere])
Dict{Symbol, Any} with 1 entry:
  :atmosphere => :aerobic
```

## Controls and replicates

Controls are not ordinary design rows. A row with a `:control_role` is a *template*: a blank cell
in a blocking column means "one copy for every block". [`expand_control_templates`](@ref) makes those
copies, one per blocking combination that the sample rows actually use, and tags each with the
block it belongs to. The positive and negative templates above each become two controls, one per
atmosphere:

```jldoctest experiments
julia> expand_control_templates(expt).design
8×5 DataFrame
 Row │ glucose  SMU_UA159   atmosphere  control_role  _block_key
     │ Int64    Float64?    Symbol?     String15?     Tuple…?
─────┼──────────────────────────────────────────────────────────────
   1 │      10        0.01  aerobic     missing       missing
   2 │       5        0.01  aerobic     missing       missing
   3 │      10        0.01  anaerobic   missing       missing
   4 │       5        0.01  anaerobic   missing       missing
   5 │       0        0.01  aerobic     positive      (:aerobic,)
   6 │       0        0.01  anaerobic   positive      (:anaerobic,)
   7 │       0  missing     aerobic     negative      (:aerobic,)
   8 │       0  missing     anaerobic   negative      (:anaerobic,)
```

[`partition_by_blocking`](@ref) groups the rows of an expanded design by the values of its blocking
factors. It returns the names of the blocking columns and a list of groups, each with the shared
values of the blocking factors and the indices of its rows. Rows in different groups never share a
plate:

```jldoctest experiments
julia> blocking_cols, groups = partition_by_blocking(expand_control_templates(expt));

julia> blocking_cols
1-element Vector{Symbol}:
 :atmosphere

julia> [(g.key, length(g.rows)) for g in groups]
2-element Vector{Tuple{Tuple{Symbol}, Int64}}:
 ((:aerobic,), 4)
 ((:anaerobic,), 4)
```

A `:duplicates` column (not used here) gives a row more than one physical well; the extra wells are
linked to the original so `CHESSProcessing` can average them later.

## Scheduling onto plates

With `RunMaps` and `PlateMaps` also loaded, [`schedule_blocked_layout`](@ref) expands the control
templates, splits the rows by blocking factor, and schedules each group onto its own plates. It
takes the usable wells of one plate as a `BitMatrix` and the control roles to place:

```jldoctest experiments
julia> using RunMaps, PlateMaps

julia> scheduled = schedule_blocked_layout(expt, trues(2, 4), (:positive, :negative);
           reagent_context = ctx, org_context = ctx);

julia> unique(layout(scheduled).labware)
2-element Vector{Union{Missing, String}}:
 "g1_p1"
 "g2_p1"

julia> sort(collect(get_parameter(scheduled, :plate_conditions)); by = first)
2-element Vector{Pair{Any, Dict{Symbol, Any}}}:
 "g1_p1" => Dict(:atmosphere => :aerobic)
 "g2_p1" => Dict(:atmosphere => :anaerobic)

```

The aerobic rows went to plate `g1_p1` and the anaerobic rows to `g2_p1`. The result records:

- `:layout`, a `DataFrame` with one row per well giving the design row it holds (`run_index`) and
  whether it is a positive or negative control;
- `:plate_conditions`, each plate's shared blocking values;
- `:well_conditions`, each placed well's organism and non-blocking condition values, keyed by
  `(labware, well)`;
- `:run_map` and `:plate_maps`, the scheduling structures `CHESSProcessing` uses later.

The layout has the columns in [`LAYOUT_COLUMNS`](@ref). [`populate_well_conditions`](@ref) fills
`:well_conditions` for any scheduled experiment, however it was scheduled, because it reads only the
layout and the design:

```jldoctest experiments
julia> LAYOUT_COLUMNS
10-element Vector{Symbol}:
 :well
 :row
 :col
 :run
 :positive
 :negative
 :run_index
 :labware
 :location_id
 :metadata

julia> repopulated = populate_well_conditions(scheduled; reagent_context = ctx, org_context = ctx);

julia> length(get_parameter(repopulated, :well_conditions)) == length(get_parameter(scheduled, :well_conditions))
true
```

Placement within a plate is randomized, so the exact wells vary from run to run. Looking a well up
by its design row works regardless. Design row 7 is the aerobic negative control, which has no
inoculum:

```jldoctest experiments
julia> lay = layout(scheduled);

julia> well7 = only(filter(r -> isequal(r.run_index, 7), eachrow(lay)));

julia> get_parameter(scheduled, :well_conditions)[(well7.labware, well7.well)]
Dict{Symbol, Any} with 1 entry:
  :SMU_UA159 => missing
```

[`schedule_layout`](@ref) is the lower-level form for a `RunMap` and plates you have already built
yourself.

## Saving designs and runs

`CHESSDatabase` stores designs and runs in the database of a lab (see
[Database Architecture](db-architecture.md)). [`upload_experiment`](@ref) creates an experiment
record from a name and a user and returns its ID. Protocols and runs belong to an experiment.
[`upload_design`](@ref) stores an `Experiment` under an experiment record and returns the ID of the
design. It stores the design matrix, the metadata, and, if the design is scheduled, one row for each
well of the layout. [`get_design`](@ref) rebuilds the `Experiment` from the ID, including its layout:

```jldoctest experiments
julia> path = joinpath(mktempdir(), "lab.db");

julia> create_db(path);

julia> connect_SQLite(path)

julia> exp_id = upload_experiment("glucose screen", "docs")
1

julia> design_id = upload_design(scheduled, exp_id)
1

julia> restored = get_design(design_id);

julia> size(restored.design) == size(scheduled.design)
true

julia> nrow(layout(restored)) == nrow(layout(scheduled))
true
```

A scheduled well is only a name until a real location is made for it. [`commit_run_location!`](@ref)
attaches a committed location to a well of the layout. It takes the design ID, the name of the
labware, the well, and the ID of the location. The name of the labware is needed because the same
well name occurs on every plate:

```jldoctest experiments
julia> first_well = first(eachrow(layout(scheduled)));

julia> plate = generate_location(loc"WP96", first_well.labware);

julia> well_id = CHESSCore.location_id(plate[first_well.well]);

julia> commit_run_location!(design_id, first_well.labware, first_well.well, well_id)
```

A [`Run`](@ref) is one run of an experiment. It holds the location that the run was performed in,
the ID of the experiment, and the location IDs of its controls and blanks. [`upload_run`](@ref)
records a run and returns its ID, [`get_run`](@ref) looks it up, and [`get_all_runs`](@ref) lists
the runs of an experiment:

```jldoctest experiments
julia> run_id = upload_run(Run(plate, exp_id))
1

julia> length(get_all_runs(exp_id))
1

julia> get_run(run_id) isa Run
true
```

## QC methods

A [`QCMethod`](@ref) is a quality-control or correction method. [`register_qc_method!`](@ref) lets
another package register a method type under a name, [`qc_method`](@ref) finds it again, and
[`qc_methods`](@ref) lists the registered names. Registering a name that is taken raises a
`DuplicateRegistrationError`. `CHESSExperiments` owns only the registry. The methods themselves live in
the packages that implement them.

The [CHESSExperiments API reference](../api/experiments.md) lists every function.
