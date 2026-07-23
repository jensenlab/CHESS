# Database Architecture

`CHESSDatabase` persists everything built with `CHESSCore` to a SQLite database. `create_db(path)`
builds a fresh schema at `path`; `connect_SQLite(path)` opens the connection every other function in
the package uses:

```julia-repl
julia> create_db("lab.db")

julia> connect_SQLite("lab.db")
```

`create_db` also turns on a setting that makes the database reject any write that would leave a
reference pointing at something that doesn't exist, so the relationships described below are
actually enforced, not just documented.

Each table below is listed as `Name(column, column, ...)`.

## Core identity

- `Ledger(ID, SequenceID, Time)` -- numbers every event in order; every other table's history hangs
  off of it. Covered in full in [The Ledger](ledger.md).
- `LocationTypes(Name)`, `Locations(ID, Name, Type)` -- every committed `Location` gets one row
  here, regardless of concrete Julia type.
- `Barcodes(Barcode, LocationID, Name)` -- maps a physical barcode string to a `Location`.

## Components and chemistry

`Components(ID, Type)`, `Reagents(ComponentID, Name, Type, MolecularWeight, Density, CID)`,
`Chemicals(ID, Name, Charge, MolecularWeight)`, `CompositionRules(ID, ReagentComponentID,
ChemicalID, Coefficient)`, `Organisms(ID, ComponentID, Genus, Species, Strain)` -- the persisted
counterparts of `CHESSCore`'s `Reagent`/`Chemical`/`Organism`/`CompositionRule` types.

## Environment

`Attributes(Attribute, BaseUnit)` -- the registry of attribute kinds. `EnvironmentAttributes(ID,
LedgerID, LocationID, Attribute, Value, Unit, Time, InstrumentID, InstrumentTime)` -- every
`set_attribute!` call, ever, one row each.

## Operations

Every mutating `CHESSCore` operation has a matching append-only table: `Transfers`, `Movements`,
`Reads`, `Locks`, `Activity`, `InstrumentSettings`. Each carries its own `LedgerID` (tying it to a
point in history) and its own `InstrumentID`/`InstrumentTime` pair (tying it to whichever
`Instrument` performed it, if any) -- these `InstrumentID` columns are indexed from day one, not
added later as an afterthought. [Instrument Interfaces](instrument-interfaces.md) covers exactly how
that attribution gets written.

## Caching

A parallel `Cached*` family (`CachedAncestors`, `CachedDescendants`, `CachedEnvironments`,
`CachedContents`, `CachedLockActivity`, plus the backing tables that store each shared
child-set/attribute-set/stock once, `CachedChildSets`/`CachedAttributeSets`/`CachedStocks`) stores
periodic snapshots of derived state,
so reconstructing a location doesn't always mean replaying its entire history. Covered in full in
[Caching & Repair](caching-repair.md).

## Experiments, runs, protocols, and encumbrances

`Experiments`, `Runs`, `Protocols`, `ProtocolEnforcement`, `Encumbrances`, `EncumbranceCompletion`,
and a mirrored `Encumbered*` family of operation tables exist for grouping and reserving future work
against an experiment. [Encumbrances](encumbrances.md) covers this in depth; `Runs`/`Experiments`
themselves are outside this pass's scope.

[The Ledger](ledger.md) covers how `Ledger`/`SequenceID` actually get written, and why they're kept
deliberately separate from both physical insertion order and wall-clock time.
