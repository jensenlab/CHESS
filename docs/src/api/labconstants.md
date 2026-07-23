# CHESSLabConstants API Reference

`CHESSLabConstants` is overwhelmingly *data* -- registered reagents, organisms, location kinds,
instruments, and standard stock recipes, defined via `CHESSCore`'s registration macros (see
[Registering Lab Constants](../manual/registering-lab-constants.md)). The tables below are built
directly from [`registry_summary`](@ref), so they stay in sync with what's actually registered.

## Hand-written functions

```@docs
register_reagent!
register_organism!
register_chemical!
get_mw_density
CHESSLabConstants.chemical_cache_path
```

## Reagents

```@eval
using CHESS.CHESSLabConstants, CHESS.CHESSCore, Markdown
Unitful = CHESSCore.Unitful

summary = CHESSCore.registry_summary([CHESSLabConstants])
fmtq(x) = (ismissing(x) || isnothing(x)) ? "--" : (x isa Unitful.Quantity ? "$(round(Unitful.ustrip(x),digits=2)) $(Unitful.unit(x))" : string(x))

rows = ["| Name | Type | Molecular Weight | Density | PubChem ID |", "|---|---|---|---|---|"]
for r in sort(collect(summary.reagents); by=x->string(x.name))
    push!(rows, "| `$(r.name)` | $(r.type) | $(fmtq(r.molecular_weight)) | $(fmtq(r.density)) | $(fmtq(r.pubchemid)) |")
end
Markdown.parse(join(rows, "\n"))
```

## Organisms

```@eval
using CHESS.CHESSLabConstants, CHESS.CHESSCore, Markdown

summary = CHESSCore.registry_summary([CHESSLabConstants])

rows = ["| Name | Genus | Species | Strain |", "|---|---|---|---|"]
for o in sort(collect(summary.organisms); by=x->string(x.name))
    push!(rows, "| `$(o.name)` | $(o.genus) | $(o.species) | $(o.strain) |")
end
Markdown.parse(join(rows, "\n"))
```

## Location kinds

```@eval
using CHESS.CHESSLabConstants, CHESS.CHESSCore, Markdown
Unitful = CHESSCore.Unitful

summary = CHESSCore.registry_summary([CHESSLabConstants])
fmtq(x) = (ismissing(x) || isnothing(x)) ? "--" : (x isa Unitful.Quantity ? "$(round(Unitful.ustrip(x),digits=2)) $(Unitful.unit(x))" : string(x))
fmtcats(c) = isempty(c) ? "--" : join(c, ", ")

locs = sort(collect(filter(l -> !l.is_instrument, summary.locations)); by=x->string(x.name))
rows = ["| Name | Categories | Shape | Capacity |", "|---|---|---|---|"]
for l in locs
    push!(rows, "| `$(l.name)` | $(fmtcats(l.categories)) | $(fmtq(l.shape)) | $(fmtq(l.capacity)) |")
end
Markdown.parse(join(rows, "\n"))
```

## Instruments

```@eval
using CHESS.CHESSLabConstants, CHESS.CHESSCore, Markdown

summary = CHESSCore.registry_summary([CHESSLabConstants])
fmtcats(c) = isempty(c) ? "--" : join(c, ", ")

insts = sort(collect(filter(l -> l.is_instrument, summary.locations)); by=x->string(x.name))
rows = ["| Name | Categories |", "|---|---|"]
for l in insts
    push!(rows, "| `$(l.name)` | $(fmtcats(l.categories)) |")
end
Markdown.parse(join(rows, "\n"))
```

## Standard stock recipes

```@eval
using CHESS.CHESSLabConstants, CHESS.CHESSCore, Markdown

summary = CHESSCore.registry_summary([CHESSLabConstants])

stocks = sort(collect(filter(s -> s.module_ === CHESSLabConstants, summary.stocks)); by=x->string(x.name))
rows = ["| Name | Type |", "|---|---|"]
for s in stocks
    push!(rows, "| `$(s.name)` | $(s.type) |")
end
Markdown.parse(join(rows, "\n"))
```
