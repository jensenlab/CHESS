
"""
    registry_summary(context=vcat([CHESSCore],CHESSCore.labmodules))

Assemble every registered constant across `context` (a `Module` or list of `Module`s, default:
`CHESSCore` plus every module registered via [`register_lab`](@ref)) into one `NamedTuple`, keyed by
category: `reagents`, `chemicals`, `organisms`, `locations`, `attributes`, `reads`, `stocks`.

`organisms`/`locations`/`attributes`/`reads` are read directly from CHESSCore's central registries
([`orgprops`](@ref)/[`location_kinds`](@ref)/[`attribute_kinds`](@ref)/[`read_kinds`](@ref)), which
already hold everything needed. `reagents`/`chemicals` have no such registry, and `stocks`'
registry ([`stock_recipes`](@ref)) only reflects `Stock`s explicitly registered via
[`@stock`](@ref) -- so like [`symbol`](@ref)'s own reverse lookup, all three are instead found here
by scanning `names(m; all=true)` of each module in `context` and filtering by type. This
deliberately finds every `Stock` in scope for a complete summary, including ones never registered
via `@stock` -- unlike [`@stock_str`](@ref)'s intentionally registry-only lookup.

This is a pure data-assembly step, intended as the groundwork for documentation generation (e.g. a
script that renders the result to Markdown/HTML) -- it does not itself produce any rendered output.
"""
function registry_summary(context=vcat([CHESSCore],CHESSCore.labmodules))
    mods = context isa Module ? [context] : context

    reagents = NamedTuple[]
    chemicals = NamedTuple[]
    stocks = NamedTuple[]
    for m in mods
        for n in names(m; all=true)
            isdefined(m,n) || continue
            v = getfield(m,n)
            if v isa Reagent
                push!(reagents,(module_=m,name=n,type=typeof(v),molecular_weight=molecular_weight(v),density=density(v),pubchemid=pubchemid(v)))
            elseif v isa Chemical
                push!(chemicals,(module_=m,name=n,charge=charge(v),molecular_weight=molecular_weight(v)))
            elseif v isa Stock
                push!(stocks,(module_=m,name=n,type=typeof(v)))
            end
        end
    end

    organisms = [(name=k,genus=v[1],species=v[2],strain=v[3]) for (k,v) in CHESSCore.orgprops]
    locations = [(name=k,categories=v.categories,shape=v.shape,capacity=v.capacity,is_instrument=v.is_instrument) for (k,v) in CHESSCore.location_kinds]
    attributes = [(name=k,unit=v.unit) for (k,v) in CHESSCore.attribute_kinds]
    reads = [(name=k,unit=v.unit,allowed_values=v.allowed_values) for (k,v) in CHESSCore.read_kinds]

    return (reagents=reagents,chemicals=chemicals,organisms=organisms,locations=locations,attributes=attributes,reads=reads,stocks=stocks)
end
