# CHESSParsers API Reference

`CHESSParsers` reads instrument export files, such as plate-reader spreadsheets and incubator
logs, into [`LabwareRead`](@ref)s and [`EnvironmentLog`](@ref)s. It is not re-exported by `CHESS`;
load it with `using CHESSParsers`. See [Parsing Instrument Files](../manual/parsing-instrument-files.md)
for worked examples.

The functions most code uses are [`parse_instrument_file`](@ref), which auto-detects the file's
format, and `record_reads!`, which records a parsed read onto a `CHESSCore` labware (it lives in a
package extension that loads with `CHESSCore`). New formats implement the
[`InstrumentFormat`](@ref) interface and are added with [`register_format!`](@ref).

```@autodocs
Modules = [CHESSParsers]
```
