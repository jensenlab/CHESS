# Documentation Style Guide

Rules for writing and revising pages on the CHESS documentation sites.

## Prose

- Use plain, direct sentences.
- Do not use rhetorical interjections or filler: "full stop", "simply", "just", "note that".
- Keep `--` asides short, or turn them into sentences. Avoid long parentheticals.
- Keep a page's analogies to one place. The chess analogy is told on the Home page only.
- Write headings as plain noun phrases that name the topic ("Locations", "Mixing stocks"). Do not
  write slogans, contrasts, or "term: explanation" headings ("Recording moves, not positions",
  "A quantity, not just presence", "Chemicals: identity").
- Use "state" for what the ledger records and reconstructs: the state of the lab, of a location, of
  a well. Use "position" only for a literal physical location or an index in a sequence.

## Pages stand alone

- Do not refer to the conversation or to other pages' progress: no "we", "let's", "the previous
  chapter", "as established", or "already covered".
- Link to another page when a concept depends on it, and restate the one fact the reader needs.
- Do not describe implementation history or list callers of a function (for example "its only
  current caller is ..."). Describe what the function does and how to use it.

## Code in prose

- Use inline code for defined things: functions, types, macros, fields, and registered constants.
  A sentence may name a function and say what it does ("`move_into!` refuses a move that would
  over-fill the parent").
- Do not use inline code as a stand-in for a concept that words can explain. Write "subtracting one
  stock from another", not "`-` mixes by subtraction". Write "zero" and "full", not `0` and
  `1//1`, and "export", not `export`, when the word is used in its ordinary sense.
- Do not use code as a command in a sentence. Describe the behavior in plain language, for example
  "CHESS includes common location kinds such as ..." instead of "`using CHESS` registers ...".
- Introduce an example in words before the doctest. Put commands such as `using CHESS` in the
  doctest or setup block, not in the sentence that describes the setup.
- Reserve code for doctests where possible. When a sentence can say the same thing without code,
  leave the code out.

## Links and references

- Link functions, types, and macros with `@ref` instead of quoting source file paths.
- Do not use `---` horizontal rules between sections. Headings provide the structure.

## Code examples

- Every example is a `jldoctest` that runs as written.
- Start from `using CHESS`, plus the other package the page covers.
- Look up registered constants with the string macros: `loc"..."`, `rgt"..."`, `org"..."`,
  `attr"..."`, `read"..."`, `stock"..."`.
- Constants registered within the example are used through their binding, since the string macros
  find only constants registered by CHESS and lab modules.
- Register new names (`DemoPlate`, `LiCl`, `BSU_168`) rather than names CHESS already registers
  (`Room`, `WP96`, `Absorbance`).
- End a line with `;` when its output is random (a location built without a name, randomized
  placement). Sort `Dict` and set contents before printing.
- Keep recorded output free of stack traces and local paths.

## Checking a page

Run the page's doctests before committing:

```bash
julia --project=docs docs/make.jl
```

The build uses `checkdocs = :exports` and does not set `warnonly`, so an undocumented export or an
unresolved `@ref` fails it.
