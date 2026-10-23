# Database Architecture

```@meta
DocTestSetup = :(using CHESS)
```

`CHESSDatabase` persists everything built with `CHESSCore` to a SQLite database. `create_db(path)`
builds a new schema at `path`, and `connect_SQLite(path)` opens the connection that every other
function in the package uses:

```jldoctest db_architecture
julia> path = joinpath(mktempdir(), "lab.db");

julia> create_db(path);

julia> connect_SQLite(path)
```

`create_db` also enables foreign-key enforcement, so the database rejects any write that would
leave a reference pointing at a row that does not exist. The relationships described below are
enforced by the database.

Each table below is listed as `Name(column, column, ...)`.

## Core identity

- `Ledger(ID, SequenceID, Time)` numbers every event in order, and the history in every other
  table refers to it. See [The Ledger](ledger.md).
- `LocationTypes(Name)` and `Locations(ID, Name, Type)` hold one row for every committed
  `Location`, whatever its Julia type.
- `Barcodes(Barcode, LocationID, Name)` maps a physical barcode string to a `Location`.
- `Containment(WellID, ContainerID, RowIdx, ColIdx)` records which labware each well belongs to, and the
  well's position in it. A well never leaves its labware, so a row is written once when the well is
  created and is never repaired or changed by amending the ledger. It is not a cache. Databases made
  before the table existed gain it, filled from the parent caches, when they are connected to
  ([`rebuild_containment!`](@ref) repeats that fill). [`well_container`](@ref),
  [`well_containers`](@ref) and [`container_wells`](@ref) read it.

## Lots

- `Products(ID, Supplier, CatalogNumber, ProductName, ManufacturerNumber, Grade, Notes,
  ReagentComponentID)` holds each supplier product that a lot refers to, once. `ReagentComponentID` is
  the reagent that the product is registered under, or `NULL`.
- `ObservedLots(ID, LedgerID, LocationID, ProductID, Lot, GTIN, Quantity, Unit, Cost, Received, Notes, ...)`
  holds the lot that a labware was received as. See [Observations](observations.md).

## Components and chemistry

`Components(ID, Type)`, `Reagents(ComponentID, Name, Type, MolecularWeight, Density, CID)`,
`Species(ID, Name, Charge, Formula, MolecularWeight, CID)`, `Dissolutions(ID, ReagentComponentID,
SpeciesID, Coefficient)`, and `Organisms(ID, ComponentID, Genus, Species, Strain)` persist the
`Reagent`, `Species`, `Organism`, and `Dissolution` types of `CHESSCore`. A species with an
elemental formula stores the formula as a Hill-order string and no molecular weight, since the weight
derives from the formula. A species without a formula stores its molecular weight. A species' PubChem ID
is stored in `Species.CID`. It is descriptive and not part of the species' natural key. The
`Reagents.CID` column belongs to databases written before PubChem IDs moved to species. It is no longer
read, and [`migrate_chemistry!`](@ref) copies it onto the species of a reagent made of one species.

A database created before the `Chemicals` and `CompositionRules` tables were renamed `Species` and
`Dissolutions` is converted by
[`migrate_chemistry!`](@ref).

## Environment

`Attributes(Attribute, BaseUnit)` is the registry of attribute kinds, and [`get_all_attributes`](@ref)
returns it as a `DataFrame`. `EnvironmentAttributes(ID,
LedgerID, LocationID, Attribute, Value, Unit, Time, InstrumentID, InstrumentTime)` has one row for
every `set_attribute!` call.

## Operations

Every mutating `CHESSCore` operation has a matching append-only table: `Transfers`, `Movements`,
`Reads`, `Locks`, `Activity`, and `InstrumentSettings`. Each has a `LedgerID`, which places the row
in the history, and an `InstrumentID` and `InstrumentTime`, which record the instrument that
performed the operation, if any. The `InstrumentID` columns are indexed. See
[Instrument Interfaces](instrument-interfaces.md).

## Caching

A family of `Cached*` tables stores snapshots of derived state, so that reconstructing a location
does not always replay its entire history. The tables are `CachedAncestors`, `CachedDescendants`,
`CachedEnvironments`, `CachedContents`, and `CachedLockActivity`. The backing tables
`CachedChildSets`, `CachedAttributeSets`, and `CachedStocks` store each shared child set, attribute
set, and stock once. See [Caching & Repair](caching-repair.md).

## Indexes

The ledger and the operation tables are indexed by the location an operation concerns and by its ledger
entry, so that rebuilding one location does not have to read every row of the ledger. The indexes are
named `idx_chess_<table>_<columns>`. [`create_db`](@ref) creates them. [`connect_SQLite`](@ref) adds
them to an existing database that has fewer than 1,000,000 ledger rows, and only warns about a larger
one, because building them there can take a long time; [`create_indexes!`](@ref) builds them on request.
An index is not created when the database already has one with the same leading columns, whoever made
it. [`drop_indexes!`](@ref) removes the `idx_chess_*` indexes and no others.

The ledger records a time with each entry, and the time of a new entry is never earlier than the time
of the entry before it, even if the computer's clock has been set back. Allocating the sequence ID of a
new entry is a single statement, so two programs writing to the same database never receive the same
sequence ID.

## Experiments, runs, protocols, and encumbrances

The tables `Experiments`, `Runs`, `Protocols`, `ProtocolEnforcement`, `Encumbrances`, and
`EncumbranceCompletion`, and a matching `Encumbered*` family of operation tables, group and reserve
future work for an experiment. See [Encumbrances](encumbrances.md) for protocols and encumbrances.

## Running SQL

[`query_db`](@ref) runs a statement that returns rows and gives a `DataFrame`. [`execute_db`](@ref)
runs a statement that changes the database, such as `INSERT`, `UPDATE`, or `CREATE`. Both take a
vector of parameters for the `?` placeholders of the statement. Parameters are safer than building
the SQL with string interpolation. Both raise an error if no database is connected.

[`sql_transaction`](@ref) runs a function in a transaction. If the function throws, every write that
it made is rolled back, and otherwise it returns the value of the function. `upload` and `update` use
it, so an operation and its database record succeed or fail together. [`sql_commit`](@ref) and
[`sql_rollback`](@ref) commit and roll back a named savepoint, and most code uses
`sql_transaction` instead:

```jldoctest db_architecture
julia> execute_db("CREATE TABLE Scratch (Name TEXT)");

julia> execute_db("INSERT INTO Scratch (Name) VALUES (?)", ["first"]);

julia> try
           sql_transaction() do
               execute_db("INSERT INTO Scratch (Name) VALUES (?)", ["second"])
               error("fail after the insert")
           end
       catch
       end

julia> query_db("SELECT Name FROM Scratch")
1×1 DataFrame
 Row │ Name
     │ String
─────┼────────
   1 │ first
```
