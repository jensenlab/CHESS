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

lrs = parse_instrument_file("plate_read.xlsx")             # auto-detected
lrs = parse_instrument_file("plate_read.xlsx"; format="epoch2")
lrs = parse_instrument_file("plate_read.xlsx"; format=Epoch2Format)
```

Every parser returns `Vector{LabwareRead}` -- one `LabwareRead` (`metadata::Dict{String,Any}`,
`data::DataFrame`) per **(plate, channel)** found in the file, a channel being one specific
measurement configuration (e.g. absorbance at a given wavelength, or fluorescence at a given
excitation/emission pair). A file with 8 plates each read at 3 wavelengths yields 24 `LabwareRead`s.
`data` is exactly `well`/`time`/`value`; everything constant for that one (plate, channel) --
instrument, plate id, `read_kind`, wavelength or excitation/emission -- lives once in `metadata`
instead of being repeated on every row:

- `DataFrame(lr)` -- the tidy measurement table (`well`, `time`, `value`)
- `record_reads!(labware, lr)` -- record the reads onto a `CHESSCore.Labware` as `CHESSCore.Read`s
  (also accepts a `Vector{LabwareRead}` directly, looping over it)
- `labwareread_to_json(lr)` / `json_to_labwareread(j)` -- JSON round-trip

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

Not yet supported: BioSpa `.SES` session logs and the Take3 Trio nucleic-acid layout (see below).

Tested against 10 real exports spanning every archetype above and three different BioTek
reader-type strings (`"Epoch 2"`, `"Cytation5"`, `"CytationC10"`).

`BioSpaFormat` is still a stub: a BioSpa `.SES` session file is a chamber-level environmental log
(temperature/O2/CO2/humidity over time, plus a plate slot/barcode mapping), not a per-well plate
read, so it doesn't fit `LabwareRead`'s shape -- it needs its own result type, closer to
`CHESSCore.set_attribute!` over time. The same reasoning drops per-timepoint temperature from kinetic
output generally: it's one plate-level reading per timepoint, not a well-level measurement, so it
doesn't fit a `{well, time, value}` row or a metadata scalar either.

Also out of scope so far: BioTek's Take3 Trio nucleic-acid quant read (a `dna_read.xlsx`-shaped
file), which uses a different table layout and measurement semantics (ng/µL, 260/280, CV%) than the
`Absorbance`/`Fluorescence` well-grid reads handled here.

## Contributing a fixture

Gen5 exports vary slightly across protocols and instrument software versions, and there will
inevitably be shapes this parser hasn't seen yet. When one turns up:

1. **Drop the file into `data/`.** This directory is gitignored (`CHESSParsers/.gitignore`, mirroring
   `Pourfecto/.gitignore`'s own `data/` entry) -- it's your local, private working area for real lab
   exports, which often contain unpublished experiment/protocol names and real results. Nothing in
   it is ever committed; never explicitly `git add` a file in there.
2. **Run the triage script**: `julia --project=CHESSParsers CHESSParsers/dev/triage_fixtures.jl`. It
   attempts to parse every file in `data/` and reports `OK` with a plate/channel/row count, or `FAIL`
   with the error. A one-command way to check "does this new file work" without manual exploration.
3. **If it fails** (or parses with a wrong-looking count), investigate the raw cells (e.g. via
   `XLSX.jl` directly, or by opening the file) and fix `src/instruments/gen5.jl` -- or, if it's a
   genuinely different vendor/instrument shape (like the still-deferred BioSpa `.SES` or Take3 Trio
   layouts), that calls for a new `InstrumentFormat`, not a `gen5.jl` patch.
4. **Once it parses correctly, de-identify it** before it can become a permanent regression fixture:
   `julia --project=CHESSParsers CHESSParsers/dev/deidentify_fixture.jl data/<file>.xlsx test/fixtures/<descriptive_name>.xlsx`.
   This produces a structurally-identical copy with experiment/protocol paths, reader serial, real
   dates, and barcode-style plate names replaced by fixed placeholders, and every measurement value
   replaced by a seeded-random value roughly the same order of magnitude as the original (see the
   script's header comment for the exact rules). The output is safe to commit -- pick a descriptive
   filename rather than reusing the original (which may itself hint at real construct/strain names).
5. **Hand-verify a few values from the de-identified copy** (not the original -- its values are
   fake) and add a `@testset` to `test/runtests.jl` referencing it by name, following the existing
   fixture testsets as a template. Because it's committed, this one runs in CI for everyone, always --
   no "only works if you have the data locally" caveat.
