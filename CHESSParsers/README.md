# CHESSParsers.jl

Parses instrument-exported data files into a form the rest of [CHESS](../README.md) already knows
how to use. Starting with BioTek plate readers/incubators (Epoch2, Synergy, Cytation, BioSpa),
designed to support other instruments later without changing the core interface.

## Interface

Every concrete instrument format (`Epoch2Format`, `SynergyFormat`, `CytationFormat`, `BioSpaFormat`,
...) subtypes `InstrumentFormat` and is registered with `register_format!`. Parsing a file goes
through `parse_instrument_file`, which either auto-detects the format or uses one you pass explicitly:

```julia
using CHESSParsers

lrs = parse_instrument_file("plate_read.xlsx")             # auto-detected -> Vector{LabwareRead}
els = parse_instrument_file("session.SES")                 # auto-detected -> Vector{EnvironmentLog}
lrs = parse_instrument_file("plate_read.xlsx"; format="epoch2")
lrs = parse_instrument_file("plate_read.xlsx"; format=Epoch2Format)
```

Every parser returns a `Vector` of result objects -- one per **(plate, channel)** for the Gen5
plate-reader family, or one per **reading kind** for `BioSpaFormat`'s chamber-level environmental
log, since that data has no well to attach to at all:

- **`LabwareRead`** (`metadata::Dict{String,Any}`, `data::DataFrame`) -- the Gen5 result, one per
  (plate, channel), a channel being one specific measurement configuration (e.g. absorbance at a
  given wavelength, or fluorescence at a given excitation/emission pair). A file with 8 plates each
  read at 3 wavelengths yields 24 `LabwareRead`s. `data` is exactly `well`/`time`/`value`; everything
  constant for that one (plate, channel) -- instrument, plate id, `read_kind`, wavelength or
  excitation/emission -- lives once in `metadata` instead of being repeated on every row.
- **`EnvironmentLog`** (`metadata::Dict{String,Any}`, `data::DataFrame`) -- the BioSpa `.SES` result,
  one per reading kind (`Temperature`/`O2`/`CO2`/`Humidity`). `data` is exactly `time`/`value` (no
  well); `metadata["plates"]` carries the session's plate slot/barcode/Gen5-plate-number mapping.

- `DataFrame(lr)` / `DataFrame(el)` -- the tidy measurement table
- `record_reads!(labware, lr)` -- record `LabwareRead`s onto a `CHESSCore.Labware` as
  `CHESSCore.Read`s (also accepts a `Vector{LabwareRead}` directly, looping over it); no
  `EnvironmentLog` equivalent yet -- chamber-level data isn't a well-level `CHESSCore.Read`, and
  registering new time-series `ReadKind`s for it is a deliberately deferred design decision (see
  Status).
- `labwareread_to_json(lr)` / `json_to_labwareread(j)` -- JSON round-trip for `LabwareRead`
- `environmentlog_to_json(el)` / `json_to_environmentlog(j)` -- JSON round-trip for `EnvironmentLog`

## Status

The generic interface (registry, dispatch, `LabwareRead`, and all three output conversions) is
implemented and tested.

`Epoch2Format`, `SynergyFormat`, and `CytationFormat` are implemented: all three BioTek readers
export the same Gen5 `.xlsx` layout (a metadata header, then one or more data blocks -- endpoint
grids and/or kinetic wide tables, stacked sequentially when a protocol configures multiple "Read"
steps), differentiated only by the file's own `Reader Type:` field -- `src/instruments/gen5.jl` is
the shared parsing engine all three dispatch to.

Section-title wording varies between protocols (some endpoint exports have no "Results" label at
all; kinetic exports word the same thing as "Start/End Kinetic" or "Discontinuous Kinetics"), so
dispatch keys on the *shape* of the data -- a numeric column-index header row, a "Time" header row,
or a "Wavelength" header row -- rather than which titles happen to be present. A data block's
trailing marker (e.g. `"OD600:600"`, `"Fluor:505,536"`, or a bare `500`) is read the same way:
whether it's Absorbance or Fluorescence is decided by the label's own shape (a comma means
excitation,emission), not by matching it back to a declared Read step's name -- Gen5's own
auto-naming of unnamed Read steps isn't consistent enough to rely on. Workbooks can also carry extra
per-channel "pivot summary" sheets (reshaped duplicates of a real plate sheet, lower fidelity, no
metadata header) and a data block can be followed by a Gen5-computed summary grid (e.g.
`"Max V [...]"`, `"Mean Max OD [...]"`); both are recognized structurally and skipped rather than
misparsed as real channels.

### Supported file archetypes

Each row below is a distinct Gen5 file *shape* the parser handles, and a committed fixture that
demonstrates it (see [`test/fixtures/`](test/fixtures) and "Contributing a fixture" below for how
these get added):

| Archetype | Example fixture |
|---|---|
| Single-wavelength endpoint, `"<name>:<wavelength>"` label | `single_plate_single_read.xlsx` |
| Single-wavelength endpoint, bare-numeric label (no name/colon) | `bare_wavelength_endpoint.xlsx` |
| Multi-wavelength "sweep" endpoint (many wavelength sub-rows per well-letter) | `multi_wavelength_sweep_endpoint.xlsx` |
| Single-channel kinetic (Time/T°/well wide table) | `single_plate_timeseries.xlsx` |
| Multi-channel kinetic (absorbance + multiple fluorescence filter sets stacked in one sheet) | `multi_channel_kinetic.xlsx`, `multi_channel_kinetic_biospa.xlsx` |
| Absorbance spectrum scan (Wavelength/well wide table, no time axis, can span several well-batch sub-blocks) | `absorbance_spectrum.xlsx` |
| Multi-plate workbook (multiple sheets, Gen5-numbered or real-barcode names) | `multi_plate_single_read.xlsx`, `multi_plate_timeseries.xlsx`, `multi_plate_kinetic_cytation5.xlsx` |
| Companion pivot/summary sheets and trailing computed summary grids | recognized and skipped; present in all multi-channel/kinetic fixtures above |
| BioSpa `.SES` session log (chamber-level environmental time series + plate mapping, XML not `.xlsx`) | `biospa_environment_log.SES` |
| Take3 Trio nucleic-acid quant (`"Blank Read"` well-indexed grid + `"Sample Read #N"` no-well `SPL#`-indexed slides, incl. a captured-not-recomputed ng/µL concentration channel) | `nucleic_acid_read.xlsx` |

Tested against 12 real exports spanning every archetype above, three different BioTek reader-type
strings (`"Epoch 2"`, `"Cytation5"`, `"CytationC10"`), one BioSpa `.SES` session, and one Take3 Trio
nucleic-acid quant export.

`BioSpaFormat` produces `EnvironmentLog`s, not `LabwareRead`s -- a `.SES` session is a chamber-level
environmental log (temperature/O2/CO2/humidity over time, plus a plate slot/barcode mapping), not a
per-well plate read, so it doesn't fit `LabwareRead`'s shape at all. It doesn't feed into
`CHESSCore`'s `Read`/`Attribute` system yet either: `Temperature`/`Humidity`/`CO2` are already
registered in `CHESSLabConstants` as `Attribute`s (single-slot, overwritable), not `ReadKind`s, and
not time-series-shaped -- recording thousands of timestamped values would need new time-series
`ReadKind`s and a `record_environment!`-style function, deliberately deferred until there's a real
need for it (`DataFrame`/JSON output only for now). The same "no well, no ready-made CHESS-object
integration" reasoning drops per-timepoint temperature from Gen5 kinetic output generally: it's one
plate-level reading per timepoint, not a well-level measurement, so it doesn't fit a
`{well, time, value}` row or a metadata scalar either.

`Take3TrioFormat` reads the BioTek Take3 Trio nucleic-acid quant accessory's export, structurally
unrelated to the Gen5 plate-grid family despite sharing the same underlying Gen5 software (its header
says `"Gen5 version"`, not `"Software Version"`). Its `"Blank Read"` sheet is a real-well-indexed
`Absorbance` grid (260/280/320nm); its `"Sample Read #N"` sheets have no well at all -- only Gen5's
own generic `"SPL1"`.."SPL48"` sample tokens, spread across 3 "Slide" sub-blocks (a Take3 Trio slide
holds up to 48 samples) that get merged into one set of channels, same principle as the Gen5 spectrum
well-batch merge. Mapping an `SPL#` back to the plate/well it physically came from isn't information
the file has -- that's the caller's responsibility, not something this parser can resolve. The
260/280 ratio and `CV (%)` columns are skipped as redundant/aggregate, same as Gen5's own computed
summaries, but the ng/µL concentration is captured as its own `Concentration` channel exactly as Gen5
computed and exported it (an informational `read_kind`, not a registered `CHESSCore.ReadKind`,
mirroring `EnvironmentLog`'s treatment) rather than being skipped or re-derived: it's approximately
`A260 x 1000` for dsDNA, but Gen5 applies a further per-sample correction on top of that which isn't
recoverable from the exported raw values alone (confirmed directly -- two samples can share the same
rounded A260 yet report different concentrations).

## Contributing a fixture

Instrument exports vary slightly across protocols and software versions, and there will inevitably
be shapes this parser hasn't seen yet. When one turns up:

1. **Drop the file into `data/`.** This directory is gitignored (`CHESSParsers/.gitignore`, mirroring
   `Pourfecto/.gitignore`'s own `data/` entry) -- it's your local, private working area for real lab
   exports, which often contain unpublished experiment/protocol names and real results. Nothing in
   it is ever committed; never explicitly `git add` a file in there.
2. **Run the triage script**: `julia --project=CHESSParsers CHESSParsers/dev/triage_fixtures.jl`. It
   attempts to parse every file in `data/` and reports `OK` with a plate/channel/row count, or `FAIL`
   with the error. A one-command way to check "does this new file work" without manual exploration.
3. **If it fails** (or parses with a wrong-looking count), investigate the raw structure (e.g. via
   `XLSX.jl`/`XML.jl` directly, or by opening the file) and fix `src/instruments/gen5.jl`,
   `src/instruments/BioSpa.jl`, or `src/instruments/take3trio.jl` -- or, if it's a genuinely different
   vendor/instrument shape, that calls for a new `InstrumentFormat`, not a patch to an existing one.
4. **Once it parses correctly, de-identify it** before it can become a permanent regression fixture:
   - Gen5 `.xlsx` and Take3 Trio `.xlsx`: `julia --project=CHESSParsers CHESSParsers/dev/deidentify_fixture.jl data/<file>.xlsx test/fixtures/<descriptive_name>.xlsx`
     -- experiment/protocol paths, reader serial, real dates, and barcode-style plate names get fixed
     placeholders; every measurement value gets a seeded-random replacement at roughly the same order
     of magnitude as the original (see the script's header comment for the exact rules; Take3 Trio
     sheets are detected and scrubbed by their own rules within the same script, since they don't
     share the Gen5 family's metadata header).
   - BioSpa `.SES`: `julia --project=CHESSParsers CHESSParsers/dev/deidentify_biospa_fixture.jl data/<file>.SES test/fixtures/<descriptive_name>.SES`
     -- plate barcodes/experiment names and the session start date get placeholders (every kept
     timestamp shifted by the same offset, preserving spacing), every environmental reading gets the
     same seeded-random treatment, unparsed sections (`EventLog`/`Assay`/scheduling detail) are
     stripped, and the ~12000-sample time series is downsampled to a small evenly-spaced subset (see
     the script's header comment).

   Either way, the output is safe to commit -- pick a descriptive filename rather than reusing the
   original (which may itself hint at real construct/strain names).
5. **Hand-verify a few values from the de-identified copy** (not the original -- its values are
   fake) and add a `@testset` to `test/runtests.jl` referencing it by name, following the existing
   fixture testsets as a template. Because it's committed, this one runs in CI for everyone, always --
   no "only works if you have the data locally" caveat.
