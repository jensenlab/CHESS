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

## Components and chemistry

`Components(ID, Type)`, `Reagents(ComponentID, Name, Type, MolecularWeight, Density, CID)`,
`Chemicals(ID, Name, Charge, MolecularWeight)`, `CompositionRules(ID, ReagentComponentID,
ChemicalID, Coefficient)`, and `Organisms(ID, ComponentID, Genus, Species, Strain)` persist the
`Reagent`, `Chemical`, `Organism`, and `CompositionRule` types of `CHESSCore`.

## Environment

`Attributes(Attribute, BaseUnit)` is the registry of attribute kinds. `EnvironmentAttributes(ID,
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

## Experiments, runs, protocols, and encumbrances

The tables `Experiments`, `Runs`, `Protocols`, `ProtocolEnforcement`, `Encumbrances`, and
`EncumbranceCompletion`, and a matching `Encumbered*` family of operation tables, group and reserve
future work for an experiment. See [Encumbrances](encumbrances.md) for protocols and encumbrances.
