# CHESS Documentation Audit

Audit of the CHESS/Pourfecto documentation — manual pages, docstrings, and READMEs — against five
criteria: staleness against current source, cross-reference validity, jargon/accessibility, tone
(rhetorical filler and conversational asides), and structural formatting. A sixth section covers
coverage gaps found by walking the onboarding path as a new user.

This is a diagnostic report, not a rewrite. Findings describe problems and quote the offending
text; they do not propose replacement prose, except for staleness/cross-reference findings, where
the correct target or behavior is stated as a fact.

**Scope:** `docs/src/manual/*` + `index.md` (21 files), `Pourfecto/docs/src/manual/*` +
`examples/*` + `index.md`/`quickstart.md`/`citation.md` (17 files), 5 READMEs, and ~450 docstrings
across `CHESSCore`, `CHESSDatabase`, `Pourfecto`, `CHESSLabConstants`. The three `@autodocs` API
stub pages (`docs/src/api/core.md`, `api/database.md`, `Pourfecto/docs/src/api_reference.md`) were
left out of scope.

---

## Part 1 — Executive Summary

### Manual pages and READMEs

| File | Lines | Critical | Moderate | Minor | Primary issues | Priority |
|---|---|---|---|---|---|---|
| README.md | 70 | 1 | 0 | 0 | Stale doc URL | High |
| Pourfecto/README.md | 108 | 1 | 1 | 0 | Broken admonition syntax, imprecise link | High |
| Pourfecto/benchmarks/*/README.md (×3) | ~112 ea | 0 | 0 | 0 | Clean | Low |
| docs/src/index.md | 66 | 0 | 1 | 3 | Incomplete sentence, jargon-before-definition | Medium |
| docs/src/manual/core-concepts.md | 184 | 2 | 1 | 2 | **Stale "four Location types" narrative + broken `Instrument` ref** | **High** |
| docs/src/manual/reads.md | 101 | 1 | 0 | 0 | Repeats the stale `Instrument`-type claim | High |
| docs/src/manual/instrument-interfaces.md | 80 | 0 | 1 | 0 | Echoes `Instrument`-type framing | Medium |
| docs/src/manual/interop.md | 121 | 0 | 1 | 0 | Echoes `Instrument`-type framing | Medium |
| docs/src/manual/db-architecture.md | 66 | 0 | 1 | 0 | Editorial aside leaked into prose | Low |
| docs/src/manual/movement.md | 180 | 0 | 0 | 1 | Clean | Low |
| docs/src/manual/attributes.md | 110 | 0 | 0 | 1 | Clean | Low |
| docs/src/manual/wells.md | 124 | 0 | 0 | 0 | Clean | Low |
| docs/src/manual/stocks.md | 120 | 0 | 0 | 0 | Clean | Low |
| docs/src/manual/recipes.md | 77 | 0 | 0 | 0 | Clean | Low |
| docs/src/manual/reagents-chemicals.md | 103 | 0 | 0 | 0 | Clean | Low |
| docs/src/manual/organisms-cultures.md | 60 | 0 | 0 | 0 | Clean | Low |
| docs/src/manual/acid-base.md | 136 | 0 | 0 | 0 | Clean | Low |
| docs/src/manual/reconstruction.md | 87 | 0 | 0 | 1 | Clean (light check) | Low |
| docs/src/manual/ledger.md | 81 | 0 | 0 | 0 | Clean | Low |
| docs/src/manual/caching-repair.md | 82 | 0 | 0 | 1 | Clean | Low |
| docs/src/manual/committing-uploading.md | 83 | 0 | 0 | 0 | Clean | Low |
| docs/src/manual/encumbrances.md | 76 | 0 | 0 | 0 | Clean | Low |
| docs/src/manual/registering-lab-constants.md | 110 | 0 | 0 | 0 | Clean | Low |
| Pourfecto/docs/src/quickstart.md | 93 | 0 | 0 | 3 | No H1, broken by 1a below, "we" | **High** (functional bug) |
| Pourfecto/docs/src/index.md | 37 | 0 | 0 | 1 | Formatting only | Low |
| Pourfecto/docs/src/citation.md | 29 | 0 | 0 | 0 | Clean | Low |
| Pourfecto/docs/src/manual/pourfecto_method.md | 522 | 1 | 0 | 1 | **Stale `JLIMS.*` type names throughout** | High |
| Pourfecto/docs/src/manual/configurations.md | 468 | 2 | 1 | 2 | Stale `JLIMS`/type-vs-symbol mismatch in `labware` field | High |
| Pourfecto/docs/src/manual/instruments.md | 228 | 0 | 0 | 0 | Clean | Low |
| Pourfecto/docs/src/manual/stocks.md | 214 | 0 | 0 | 0 | Clean | Low |
| Pourfecto/docs/src/manual/labware.md | 213 | 0 | 0 | 0 | Clean | Low |
| Pourfecto/docs/src/manual/compiling.md | 194 | 0 | 0 | 1 | Minor filler | Low |
| Pourfecto/docs/src/manual/troubleshooting.md | 145 | 0 | 0 | 2 | Missing `@id` anchor, filler | Low |
| Pourfecto/docs/src/manual/complexity.md | 128 | 0 | 0 | 0 | Clean | Low |
| Pourfecto/docs/src/manual/pourcasts.md | 481 | 0 | 0 | 0 | Clean | Low |
| Pourfecto/docs/src/manual/reagents.md | 33 | 0 | 0 | 0 | Clean | Low |
| Pourfecto/docs/src/examples/checkerboard.md | 155 | 0 | 0 | 5 | Heaviest "we/we'll" concentration | Medium (tone) |
| Pourfecto/docs/src/examples/combinatorial_media.md | 188 | 0 | 0 | 4 | "we" pattern | Medium (tone) |
| Pourfecto/docs/src/examples/in_place.md | 163 | 0 | 0 | 3 | "we" pattern (lighter) | Low |
| Pourfecto/docs/src/examples/priority.md | 195 | 0 | 0 | 5 | Highest "we" count of any file | Medium (tone) |

**Totals:** Critical 8, Moderate 6, Minor ~35 across 44 manual/README files.

### Docstrings (see Part 5 for full detail)

| Package | Docstrings reviewed | Symbols with findings | Critical | Moderate | Minor |
|---|---|---|---|---|---|
| CHESSCore | ~230 | 11 | 3 | 6 | 2 |
| CHESSDatabase | ~25 documented (most internals undocumented) | 5 | 2 | 3 | 0 |
| Pourfecto | ~104 | 11 | 4 | 4 | 3 |
| CHESSLabConstants | ~9 | 1 | 0 | 0 | 1 |

**The single highest-priority fix in this whole audit:** `core-concepts.md` — the first manual
chapter a new user reads — describes CHESS as having "exactly four concrete `Location` subtypes"
including `Instrument`. **`Instrument` does not exist anywhere in the source.** Only
`GenericLocation`, `Labware`, and `Well` are real types; "instrument" is a capability flag
(`is_instrument`) on `LocationKind`, not a fourth type. This was independently confirmed by three
separate passes (manual audit, docstring audit, and the scripted cross-reference check) and
propagates as a factual error into `reads.md`, `instrument-interfaces.md`, `interop.md`, and a
`LocationKind` docstring. See Part 2 and Part 4 for detail.

---

## Part 2 — Cross-Reference Audit Results

Scripted pass: extracted all 293 `[X](@ref)` / `(@ref name)` occurrences across `docs/src/` and
`Pourfecto/docs/src/`, diffed against every exported/defined symbol in the four `src/` trees and
every `(@id ...)` anchor; verified all 100+ relative markdown links resolve to real files; checked
external-link host consistency.

**Broken `@ref` targets:**

| File:line | Ref text | Target | Issue |
|---|---|---|---|
| `docs/src/manual/core-concepts.md:86` | `` [`Instrument`](@ref) `` | `Instrument` | No such type/struct/symbol exists anywhere in `CHESSCore`, `CHESSDatabase`, `CHESSLabConstants`, or `Pourfecto`. |
| `docs/src/manual/core-concepts.md:102` | `` [`Instrument`](@ref) `` | `Instrument` | Same. |
| `CHESSCore/src/locations/LocationKind.jl:19` (docstring) | `` [`Instrument`](@ref) `` | `Instrument` | Same broken ref, inside a docstring rather than a manual page. |
| `Pourfecto/src/instruments/{Nimbus,Cobra,Mantis,Tempest}.jl` (docstrings for `batch_design`, `write_instrument_files`) | `` [`convert_design`](@ref) `` | `convert_design` | `convert_design` is defined in 4 files but has no docstring anywhere, so nothing exists for the `@ref` to resolve to. |
| `CHESSDatabase/src/uploads.jl:66` (docstring) | `` [`Locaiton`](@ref) `` | `Locaiton` | Typo for `Location`; not a valid symbol either way. |

**Relative markdown links:** all resolve correctly — no missing files found.

**External URL consistency:** every link inside `docs/src/` and `Pourfecto/docs/src/` consistently
uses `jensenlab.github.io/CHESS/...`. The one inconsistency in the whole repo is
`README.md:64`, which uses `jensenlab.net/CHESS` instead — see Part 4.

---

## Part 3 — Global Tone Patterns (D1 filler / D2 insider references)

The corpus is overall clean on **D1** (rhetorical filler: "full stop," "obviously," "to be clear,"
etc.) — only 3 instances found in ~5,675 lines of prose, all in Pourfecto's manual:

| Pattern | Count | Files |
|---|---|---|
| "simply" | 1 | `Pourfecto/docs/src/manual/compiling.md:84` |
| "Note that" (filler opener) | 2 | `Pourfecto/docs/src/manual/troubleshooting.md:46,75` |

**D2** (conversational/insider references — "we," "let's," unnamed backward/forward references) is
concentrated almost entirely in one place: the four Pourfecto **example** walkthroughs and
`quickstart.md`. It is essentially absent from every manual/concept chapter in both doc trees.

| Pattern | Count | Files |
|---|---|---|
| "we" / "we'll" / "we're" (tutorial narration) | 19 | `checkerboard.md` (5), `priority.md` (5), `combinatorial_media.md` (4), `in_place.md` (3), `quickstart.md` (1), `db-architecture.md` (1, different flavor — see below) |
| "as we'll see" (unnamed forward reference) | 1 | `priority.md:22` |
| "We use this method to ensure..." (identical phrasing, two files — looks copy-pasted) | 2 | `CHESSCore/src/environments/Attributes.jl:208`, `CHESSCore/src/operations/attributes.jl:3` (docstrings) |
| Editorial/process language leaking into reader-facing prose | 1 | `docs/src/manual/db-architecture.md:63`, `"outside this pass's scope"` — refers to an internal documentation-authoring pass, meaningless to a reader |

**Representative quotes:**
- "We'll build this experiment in Pourfecto, let it choose from a set of..." (`checkerboard.md:23`)
- "This example works through a real dosing problem: we need to prepare wells..." (`priority.md:7`)
- "...and, as we'll see, it lets Pourfecto *choose* which stock to draw from" (`priority.md:22`)

**Takeaway:** a tone pass can be scoped narrowly. The four example files plus `quickstart.md`
account for essentially all of the D2 problem; the concept/manual chapters in both doc trees
already meet the house style.

---

## Part 4 — Per-File Detail

### READMEs

**`README.md`** — Verdict: needs one link fix.
- [Critical][A] Line 64: `` **[http://jensenlab.net/CHESS](https://jensenlab.net/CHESS)** `` — every
  other doc link in this same file (lines 3, 4, 18, 21, 24) uses `jensenlab.github.io/CHESS/...`.
  Should be the same host.

**`Pourfecto/README.md`** — Verdict: needs one formatting fix, one link precision fix.
- [Critical][E] Lines 51-52: uses Documenter.jl's `` !!! note `` admonition syntax. GitHub's
  markdown renderer (which is what actually renders this file) does not support it — it will
  display as literal `!!! note` text, not a callout box. Likely copy-pasted from Documenter source
  without adapting to GitHub-flavored markdown.
- [Moderate][A] Line 56: links "CHESSCore" to the generic docs root
  (`https://jensenlab.github.io/CHESS/dev/`) instead of the CHESSCore-specific API page
  (`.../dev/api/core/`, matching the pattern the root README uses).
- Clean on tone: zero D1/D2 hits across all 5 READMEs.
- Not stale: the citation DOI (`10.64898/...`) is correct — verified against openRxiv's own
  changelog; `10.64898` is the new bioRxiv/medRxiv prefix as of December 2025, not an error.

**3 benchmark READMEs** (`nimbus_batching_distance`, `rlforlqh_comparison`,
`combinatorial_media_scaling`) — Verdict: clean. Dense, technical, internally consistent; no
findings.

### `docs/src/index.md`
- [Moderate][E] Line 20: "**`CHESS`** -- packages everything into a single repository" — sentence
  fragment, missing a period, reads as incomplete.
- [Minor][E] Lines 20-22: inconsistent blank-line spacing before "## Installation" vs. the rest of
  the file.
- [Minor][C] Lines 5-6: "ledger" used and central to the framework's pitch, but not linked to
  [The Ledger](manual/ledger.md) on this page's first use (core-concepts.md does link it on its
  own first use).

### `docs/src/manual/core-concepts.md` — the highest-priority file in the audit
- [Critical][A] Lines 70-72, 86-88, 94-95, 100-102: the entire "four location types" section is
  stale. Quote: "exactly four concrete `Location` subtypes." Source has three:
  `GenericLocation`, `Labware`, `Well`. "Instrument" is the `is_instrument`/`is_capable` capability
  flag on `LocationKind`, not a fourth type — confirmed by `LocationKind.jl`'s own `concretetype`
  docstring.
- [Critical][B] Lines 86, 102: `` [`Instrument`](@ref) `` — broken reference (Part 2).
- [Moderate][A] Lines 129-131: describes `concretetype(kind)` as mapping to `Instrument` when
  `is_instrument` is set. Actual source (`LocationKind.jl:80-82`) has no `Instrument` branch at
  all — the ternary only chooses among `Well`, `Labware`, `GenericLocation`.
- [Minor][C] Line 92: "occupancy cost" used before its formal definition two chapters later.
- [Minor][E] Lines 146-151: six consecutive blank lines, likely an editing leftover.

### `docs/src/manual/reads.md`
- [Critical][A] Line 76: "There is a single concrete `Instrument` type for every instrument
  model." Doubly wrong — no `Instrument` type exists at all, and instrument capability is data on
  `LocationKind`, not a dedicated type.

### `docs/src/manual/instrument-interfaces.md`
- [Moderate][A] Line 10: "`CHESSCore` owns `Instrument`..." — phrased as though `Instrument` is a
  distinct owned type; it's the capability-flag machinery on `LocationKind`/`Location`.

### `docs/src/manual/interop.md`
- [Moderate][A] Line 90: describes `Instrument` as a distinct subtype with its own
  `actuatable_attributes`/`performable_operations`/`readable_types` fields — same stale framing.

### `docs/src/manual/db-architecture.md`
- [Moderate][D2] Line 63: "`Runs`/`Experiments` themselves are outside this pass's scope." —
  editorial/process language with no meaning to a reader.

### `docs/src/manual/movement.md`, `attributes.md`, `caching-repair.md`, `committing-uploading.md`,
`encumbrances.md`, `reagents-chemicals.md`, `recipes.md`, `acid-base.md`, `organisms-cultures.md`,
`registering-lab-constants.md`, `reconstruction.md`, `ledger.md`, `stocks.md`, `wells.md` — all
verified accurate against source with no Critical/Moderate findings; only scattered Minor
first-use-before-definition notes (`environment` in `attributes.md`, `provenance` in
`reconstruction.md`). See the source audit transcript for the full per-function verification list
if needed — all named functions/types checked resolved correctly.

### `Pourfecto/docs/src/quickstart.md`
- [Minor][E] No H1 title anywhere in the file — every other manual/example page opens with
  `# [Title](@id ...)`.
- [Minor][E] Line 37: typo "defualt" for "default."
- [Minor][D2] Line 37: "In this example we will select two defualt Configurations."
- **Functional issue found separately by the persona walkthrough (Part 6, item 1a): the example
  scripts reference placeholder files that don't exist, so nothing in this page is actually
  runnable as written.**

### `Pourfecto/docs/src/manual/pourfecto_method.md`
- [Critical][A] Lines 29, 32, 46, 59, 113-114: uses `JLIMS.Stock`/`JLIMS.Labware` as type
  signatures throughout. The real `pourfecto` method signatures
  (`Pourfecto/src/pourfecto_algorithms/algorithms.jl:495,512,535,554`) are typed
  `CHESSCore.Stock`/`CHESSCore.Labware`. `JLIMS` is a dead name — it doesn't exist as a live
  namespace anywhere in Pourfecto source (only a stray comment survives in
  `Pourfecto/src/default_labware.jl:16`), suggesting an incomplete project-wide rename.
- [Minor][E] Line 36: typo "platn" for "plan."
- Everything else on this page (the large keyword-argument table, solver comparison table,
  in-place-transfer description) was checked line-by-line against
  `pourfecto_algorithms/parameter_defaults.jl` and `algorithms.jl` and is accurate.

### `Pourfecto/docs/src/manual/configurations.md`
- [Critical][A] Line 304: field table says `labware` on `ConstrainedPosition` is a "Set of allowed
  `JLIMS.Labware` types." Actual field (`Pourfecto/src/types.jl:278`) is `labware::Set{Symbol}`,
  holding `CHESSCore.LocationKind` names like `:Conical15`, not Julia types.
- [Critical][A] Lines 289-297, 313-321: code examples construct `Set([MyPlateType])` /
  `Set([SLASLabware])` — these would fail to construct a valid `ConstrainedPosition` under the real
  `Set{Symbol}` field. Correct form: `Set([:SLAS])`.
- [Moderate][A] Lines 345-346: same stale pattern in the "Creating Decks from multiple positions"
  example.
- [Minor][E] Line 10: duplicated word, "aspirated aspirated."

### `Pourfecto/docs/src/manual/compiling.md`
- [Minor][D1] Line 84: "is simply set aside rather than erroring."
- Nimbus batching description (batch_ordering, `:greedy`/`:exact`, 8-item cap) checked against
  `Pourfecto/src/instruments/Nimbus.jl` and matches exactly.

### `Pourfecto/docs/src/manual/troubleshooting.md`
- [Minor][E] Line 1: missing `(@id ...)` anchor, unlike every other manual page in this doc set.
- [Minor][D1] Lines 46, 75: "Note that..." paragraph openers.
- Otherwise the best-verified page in the doc set — its worked `InfeasibleSolveError` example was
  checked end-to-end against `Pourfecto/src/instruments/PlateMaster.jl` and is accurate.

### `Pourfecto/docs/src/examples/checkerboard.md`, `combinatorial_media.md`, `in_place.md`,
`priority.md` — all technically accurate (configs, objective names, and API usage all verified
against source); each carries 3-5 unnamed "we/we'll" instances (Part 3). `in_place.md` is the
strongest of the four otherwise, with good use of named cross-references.

### `Pourfecto/docs/src/manual/instruments.md`, `labware.md`, `stocks.md`, `pourcasts.md`,
`reagents.md`, `complexity.md`, `Pourfecto/docs/src/index.md`, `citation.md` — clean, no findings
of note.

---

## Part 5 — Docstring Findings by Package

### CHESSCore

| File | Symbol | Line | Severity | Issue |
|---|---|---|---|---|
| `locations/LocationKind.jl` | `LocationKind` | 19 | Critical | Broken `[Instrument](@ref)` — no such symbol exists. |
| `operations/transfer.jl` | `transfer!` | 3 | Critical | Docstring signature omits the real `configuration::String=""` positional parameter entirely. |
| `stocks/Stocks.jl` | `*(::Volume,::Liquid)` | 222 | Critical | Docstring header literally shows `*(::Mass,::Solid)` — copy-pasted from the function above; body text is otherwise correct. |
| `stocks/Stocks.jl` | `/(stock,num)` | 253 | Moderate | Says scaled by `num`; actual behavior scales by `1/num`. |
| `locations/Location.jl` | `unlock!`, `lock!`, `toggle_lock!`, `activate!`, `deactivate!`, `toggle_activity!` | 171-241 | Moderate (×6) | All six take an `instrument::Union{Location,Nothing}=nothing` kwarg that none of their docstrings mention — a systematic omission across the whole lock/activity family. |
| `environments/Attributes.jl` | `set_attribute!` | 208 | Minor | D2: "We use this method to ensure a proper pairing..." |
| `operations/attributes.jl` | `set_attribute!` | 3 | Minor | Same phrasing, duplicated — looks copy-pasted between the two files. |
| `locations/Location.jl` | `toggle_lock!` | 193 | Minor | Signature line has a typo: `x:Location` missing `::`. |
| `stocks/Organisms.jl` | `strain` | 135 | Minor | "Acces" typo for "Access." |
| `interop/dataframe_interface.jl` | `df_to_labware` | 217 | Minor | Stray trailing `]` in prose. |

### CHESSDatabase
*(Most of this package's internals — reconstruction, validation/repair, caching, database schema —
have no docstrings at all, so the reviewable surface was much smaller than the file count suggests.)*

| File | Symbol | Line | Severity | Issue |
|---|---|---|---|---|
| `uploads.jl` | `upload_transfer` | 231 | Critical | Docstring signature (`sourceID::Integer, destinationID::Integer, quantity::Real, unit::AbstractString`) bears almost no resemblance to the real signature (`source::Well, destination::Well, quant::Union{Mass,Volume}, configuration::AbstractString=""`, plus 4 keyword args). Looks un-updated since a significant refactor. |
| `uploads.jl` | `upload_activity` | 66 | Critical | Broken ref: `` [`Locaiton`](@ref) `` — typo for `Location`, and not a valid symbol either way. |
| `uploads.jl` | `upload` | 27 | Moderate | Signature line has a typo ("Funciton") and malformed syntax (`time=DateTime=Dates.now()`); omits real kwargs `ledger_id`, `instrument_time`. |
| `reconstruction/reconstruct_location.jl` | `reconstruct_location!`, `reconstruct_location` | 5, 36 | Moderate (×2) | Header signature omits the real `max_cache` parameter (though it IS discussed in the body text). |
| `reconstruction/reconstruct_contents.jl` | `_reconstruction_transfer` | 4 | Moderate | Signature line omits the real `configuration::String=""` parameter. |

### Pourfecto

| File | Symbol | Line | Severity | Issue |
|---|---|---|---|---|
| `types.jl` | `Piston` | 73 | Critical | Docstring's literal field list (`minAsp`, `maxAsp`, `minDisp`, `maxDisp`, `deadPad`) doesn't match the real struct at all, which has 3 fields: `asp::Tuple`, `disp::Tuple`, `deadPad`. |
| `types.jl` | `UnconstrainedPosition` | 258 | Critical | Docstring shows only `name::String`; real struct has 4 fields (`name`, `aspirate`, `dispense`, `plotting_shape`). |
| `compiler/helpers.jl` | `slotting_requirements` | 234 | Critical | Docstring documents a `threshold::Real=1e-4` kwarg that doesn't exist — the real function takes no kwargs and hardcodes the comparison against `0`. |
| `Pourfecto.jl` | `random_adverb_verb_pairs` | 364 | Critical | Documented as `(adverbs, verbs, n; unique=true)`; actual signature is `(n=1; adverbs=..., verbs=..., make_unique=true)` — args/kwargs entirely swapped. |
| `types.jl` | `Head` | 152 | Moderate | Field list omits the real `channel_routing::BitMatrix` field, which the surrounding prose discusses. |
| `instruments/Cobra.jl` | `cobra_settings` | 70 | Moderate | Documents key `"AspDistnace"` (typo); real key is `"AspDistance"` — a reader copying the documented name gets a `KeyError`. Also omits the real `"maxShot"` key. |
| `Pourfecto.jl` | `pourfecto` (all 4 methods, shared kwarg doc) | 99 | Moderate | Never documents the `optimizer` kwarg despite it being commonly set. |
| `compiler/compile.jl` | `compile` | 15 | Moderate | Says `kwargs...` forward to both `slotting_requirements` and `write_instrument_files`; only the latter actually receives them. |
| `instruments/Mantis.jl` | `write_instrument_files` | 94 | Minor | One-line stub docstring with no argument/return documentation, unlike the Nimbus/compile equivalents. |
| `pourfecto_algorithms/objectives.jl` | `objectives` | 170 | Minor | Typos: "non-defualt," "scheudling." |
| `types.jl` | `InstrumentModel` | 126 | Minor | `jldoctest` block has no expected output; likely to fail if actually run. |

### CHESSLabConstants

| File | Symbol | Line | Severity | Issue |
|---|---|---|---|---|
| `pubchem.jl` | `get_mw_density` | 71 | Minor | Typo: "checmical." |

**Package-wide patterns:** `CHESSDatabase/src/uploads.jl` has the worst staleness of any single
file in the docstring audit — three of its documented functions each have a distinct, unrelated
defect. Pourfecto's `types.jl` struct docstrings (`Piston`, `Head`, `UnconstrainedPosition`) have
drifted from real field lists, consistent with an unrecorded refactor. CHESSLabConstants is almost
entirely clean — it's mostly data/registration files with sparse but accurate docstrings.

---

## Part 6 — Missing Concepts &amp; Effectiveness Recommendations

Findings from walking the actual onboarding path as a new user fluent in lab operations and Julia,
but new to CHESS/Pourfecto: README → `docs/src/index.md` → manual → Pourfecto README → Pourfecto
`index.md`/`quickstart.md` → Pourfecto manual/examples.

### 1. Setup/installation gaps

**1a. The flagship quickstart example does not run.** `README.md:48-59` and
`docs/src/index.md:46-57` both use `build_location(WP96, "Plate 1")`. `WP96` is registered via
`@location_kind`, which — per `docs/src/manual/registering-lab-constants.md`'s own text — never
exports the names it defines. `using CHESS` does not bring `WP96` into scope; the correct,
consistently-used form elsewhere in the manual is `loc"WP96"`. **The very first code example in the
project throws `UndefVarError` if copy-pasted.** Fix: change both snippets to
`build_location(loc"WP96", "Plate 1")`.

**1b. Root README and root `docs/src/index.md` give contradictory install instructions.**
`README.md` states CHESS must be used from a local clone and `Pkg.add(url=...)` will not work
(workspace-path resolution doesn't carry to consumers). `docs/src/index.md:25-39` says the opposite:
`Pkg.add(url="https://github.com/jensenlab/CHESS")` for "using CHESS as a dependency." These
directly contradict each other. Fix: reconcile to one true story.

**1c. Same contradiction, worse, on the Pourfecto side.** `Pourfecto/README.md` says Pourfecto is
not registry-published and must be installed from a local clone via `Pkg.activate("Pourfecto")`.
`Pourfecto/docs/src/index.md:12-28` says the opposite: install via `Pkg.add("Pourfecto")` from a
"Jensen Lab Registry." A newcomer following the docs-site version and failing to find that registry
is stuck before writing any code. Fix: reconcile to one instruction.

**1d. Gurobi/solver setup isn't signposted from quickstart.** The "Choosing a solver" section
(`pourfecto_method.md:185-208`) covers licensing well, but `quickstart.md` never mentions the
`optimizer` keyword or links there — a newcomer without a Gurobi license hits an opaque JuMP error
with no pointer back to the fix.

**1e. No Julia-version statement on the Pourfecto side.** The root README's "Julia 1.12+" workspace
requirement is never restated in `Pourfecto/README.md` or `Pourfecto/docs/src/index.md`, which
matters for a reader who discovers Pourfecto first (e.g. via the bioRxiv preprint).

### 2. Concepts used before they're introduced

**2a. `JLIMS.Stock`/`JLIMS.Labware` are used with zero definition anywhere** in
`pourfecto_method.md` and `configurations.md` (see Part 4) — likely a leftover from a package
rename that was never fully propagated. A newcomer has no way to know if this is a missing
dependency or a typo.

**2b. Pourfecto's own examples silently bypass the `deposit!`/immutable-`Stock` pattern the
CHESSCore manual just taught.** `wells.md` and `acid-base.md` teach `deposit!(well, stock)` and
stress that `Stock`s are immutable. But `Pourfecto/docs/src/manual/labware.md:211` and every
example file instead do direct field mutation (`children(A_reservoir)[1].stock = A_stock`) or
`+=` on `.stock`. This is never explained as a distinct Pourfecto-idiomatic shortcut, and it's
unclear whether it bypasses `deposit!`'s validation (e.g. capacity checks).

**2c. `add_stock!`** appears once in `labware.md:211` with no definition, docstring link, or
relationship stated to `deposit!`.

**2d. `location_kinds`** (the registry dict) is used throughout Pourfecto's docs before any
explanation of where it's populated from (`CHESSLabConstants`, or a user's own `register_lab` call)
— a concept taught only in the CHESSCore manual, which Pourfecto's docs don't clearly require
reading first.

### 3. Missing motivation before mechanics

**3a. `core-concepts.md`'s `@location_kind` macro example** shows a seven-positional-argument call
before any explanation of what each slot means.

**3b. `configurations.md`'s 400+ lines of `Piston`/`Head`/`Mask` type machinery** reads as pure
mechanics; only at line 426 (the very end) does the page reveal that most users never need any of
this. A "most users only need X below, skip to Y only if defining a new instrument" callout at the
top would save a lot of reader confusion.

**3c. `pourfecto_method.md`'s large keyword-argument table** (lines 160-173) has no "which knobs
matter for a first run" guidance — solver-internal tolerances (`grb_feasibility_tol`, `slack_tol`)
sit at the same visual priority as commonly-adjusted options.

### 4. Thin or absent end-to-end examples

**4a. CHESSCore has no single canonical "hello world."** The README/index quickstart (once fixed
per 1a) only demonstrates the location hierarchy — never a `Stock`, `deposit!`, `transfer!`, or
`Reagent`, despite chemistry being central to the package's stated purpose.

**4b. Pourfecto's `quickstart.md` is narrated, not runnable** — it references placeholder files
(`"<source_value_file>.csv"`) that don't exist. Meanwhile a genuinely complete, well-built,
runnable example already exists at `examples/checkerboard.md`, but quickstart never links to it.
Cheapest fix: add that forward pointer.

**4c. The manual itself never assembles a complete `pourfecto()` call.** `pourfecto_method.md` and
`pourcasts.md` use `sources`/`targets`/`configs` as unexplained pre-existing variables — each piece
is taught in its own chapter but never re-assembled in the manual proper (only in the separate
Examples section).

### 5. Unstated handoff points between the CHESS and Pourfecto manuals

**5a. Two same-named "Stocks" chapters** (`docs/src/manual/stocks.md` and
`Pourfecto/docs/src/manual/stocks.md`) cover almost entirely disjoint material. Pourfecto's version
links back to CHESSCore's at the bottom, but nothing at the *top* signals "read the other one
first" to someone arriving cold.

**5b. No explicit prerequisite-reading list** anywhere in Pourfecto's onboarding path stating which
CHESSCore chapters are required before starting Pourfecto (Locations, Movement, Reagents, Stocks —
reasonably yes; Ledger/database internals — reasonably no, but nothing says so).

**5c. `Configuration` (Pourfecto) and `Instrument` (CHESSCore's location type) are never
distinguished**, despite both describing "what a device can do." A reader could easily conflate
the two; nothing states whether/how a Pourfecto-planned transfer later connects to CHESSCore's
`upload(...; instrument=...)`.

### 6. Other gaps

- `reads.md`'s second `@location_kind` example (9 positional args) repeats the "no annotation of
  what each slot means" issue from 3a.
- Nothing in Pourfecto's own README/index restates the CHESS package family explained in the root
  README, for readers who land on Pourfecto first.
- CHESSCore has no troubleshooting/FAQ page collecting its common error types
  (`FixedMembershipError`, `OccupancyError`, `LockedLocationError`) the way Pourfecto's
  `troubleshooting.md` does well.
- `interop.md`'s `reagent_context` silent-failure gotcha ("leave it out and you get an empty,
  propertyless reagent with no error") is documented once, deep in an Interop chapter — and it's
  unclear whether it even applies to Pourfecto's DataFrame-based workflow, which uses
  `string_to_reagent` instead. Worth resolving explicitly on the Pourfecto side.

---

## Suggested prioritization

1. **Fix the `Instrument` staleness** (core-concepts.md, reads.md, instrument-interfaces.md,
   interop.md, one CHESSCore docstring) — one coordinated fix, highest-visibility since it's in the
   entry-point chapter.
2. **Fix the two broken quickstart examples** (`WP96` unexported; Pourfecto's placeholder CSVs) —
   these are the very first things a new user tries.
3. **Reconcile the two pairs of contradictory install instructions** (CHESS root README vs.
   `docs/src/index.md`; Pourfecto README vs. `Pourfecto/docs/src/index.md`).
4. **Fix the `JLIMS` → `CHESSCore`/`CHESSCore.Stock`/`.Labware` stale rename** in
   `pourfecto_method.md` and `configurations.md`, including the `Set{Symbol}`-vs-type mismatch in
   the `labware` field examples.
5. **Docstring signature drift**, especially `upload_transfer`, `Piston`, `UnconstrainedPosition`,
   `slotting_requirements`, `random_adverb_verb_pairs` — these actively mislead anyone reading
   generated API docs.
6. A tone pass on the four example files + `quickstart.md` (the D2 "we" concentration) — narrow,
   mechanical, low-risk.
7. Everything in Part 6 (coverage gaps) — larger effort, best scoped as its own follow-up once the
   correctness fixes above land.
