# Ticks

A tick is one ledger entry. It can hold rows of several operation tables. A slot is a `SequenceID`; its revisions are the ledger entries that share it, and the visible one counts.

## The rule

Operations fall in two groups.

- **Order-dependent:** transfers, discards, movements, locks and activity. The result of replaying them depends on the order, so each must be alone in its tick.
- **Independent:** environment samples, reads, instrument settings and observations. They may share a tick when no two state the same fact.

Facts: an environment sample is (location, attribute); an instrument setting is (instrument, setting); a component observation is (location, component); a parent observation is the child; a lot observation is the location. Reads never conflict.

An error names the offending pair, for example `ledger entry 12 (slot 7) cannot hold Transfers row 3 and Discards row 1: a transfer depends on the order of operations, so it must be alone in its tick`.

## Writing a tick

`upload_tick(op1, op2, ...; time, instrument, instrument_time)` takes operations as tuples of an operation function and its arguments, as passed to `upload`, and records them in one new ledger entry. An error leaves nothing recorded. `update_tick(ops...; replace=slot)` replaces the complete set of operations of a slot (`insert` and append work as in `update`). A replacement must have the same operation classes as the slot it replaces.

`update(...; replace=slot)` replaces one operation and therefore refuses a slot that holds several operations; use `update_tick`.

`check_tick(ledger_id)` applies the rule to an existing entry. `tick_operations(ledger_id)` lists its rows and `operation_classes(ledger_id)` its class set.

## Auditing existing data

`audit_ticks()` returns the entries that break the rule, superseded revisions included, with the first offending pair and the reason. Run it before enforcement is on for a database that predates the rule.

Enforcement is on by default. `tick_rule_enforcement!(false)` turns it off and returns the previous setting; the environment variable `CHESS_TICK_RULE=off` does the same at load.

## Effects on reconstruction

Several rows of a tick are read and replayed, none is dropped. Replay orders rows by slot, ledger entry, table and row; rows of one slot continue from the state the earlier ones left. `validate` and `cache_repair` handle every participant of an operation class in an entry. See [transfer closure](transfer_closure.md), T5.
