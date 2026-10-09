

"""
    abstract type Reagent end

Represents a *physical form* — a substance you can weigh out and store (renamed from the old
`Species`). `Reagent`s are used to identify the composition of various mixtures and substances in
the lab, tracked in [`Stock`](@ref)'s `SolidDict`/`LiquidDict`.

All `Reagent` subtypes have four fields utilized by CHESSCore:
1) `name`: the name by which the reagent will be referred to
2) `molecular_weight`: the reagent's *stored* molecular weight, used as a fallback -- see [`molecular_weight`](@ref), which prefers deriving the value from the reagent's registered [`dissolution`](@ref) (`dissolutions`) whenever one exists, since that's the more authoritative, harder-to-drift source. If neither is known, `missing`.
3) `density`: the reagent's density at STP, if known, is used by CHESSCore to facilitate conversions between mass and volume quantities of the reagent. If `density` is unknown or undefined, it is assigned a value of `missing`
4) `pubchemid`: the reagent's integer [PubChem ID](https://pubchem.ncbi.nlm.nih.gov) connects the reagent to registered substances in the pubchem database. the [`@reagent`](@ref) macro uses `pubchemid` to query the PubChem database for the reagent's properties automatically.

See also: [`Species`](@ref) for the separate *chemical identity* axis (what a reagent behaves as once
dissolved), and [`StockComponent`](@ref) for the common dispatch/gathering ancestor `Reagent` shares
with [`Organism`](@ref).
"""
abstract type Reagent <: StockComponent end




function Base.show(io::IO,reagent::Reagent)
    try
        print(io,symbol(reagent))
    catch e
        e isa ArgumentError || rethrow()
        print(io,name(reagent))
    end
end

"""
    name(x::Reagent)

access the name property of a reagent
"""
name(x::Reagent)=x.name
"""
    molecular_weight(x::Reagent)

The molecular weight of a reagent: derived from its registered [`dissolution`](@ref)
(`dissolutions`) when one exists (the sum of each product [`Species`](@ref)'s molecular weight
times its coefficient), falling back to the reagent's stored value otherwise. Deriving from
the dissolution is safe because every registered [`Dissolution`](@ref) is required to be
non-negative, real stoichiometry (see its constructor).
"""
function molecular_weight(x::Reagent)
    haskey(dissolutions,x) || return x.molecular_weight
    rule = dissolutions[x]
    return sum(v*molecular_weight(k) for (k,v) in rule.products)
end
"""
    density(x::Reagent)

access the density property of a reagent
"""
density(x::Reagent)=x.density

"""
    pubchemid(x::Reagent)

access the pubchemid property of a reagent
"""
pubchemid(x::Reagent)=x.pubchemid




"""
    struct Solid <: Reagent

Solids are [`Reagent`](@ref) subtypes that exist in solid phase at STP. We typically express solid quantities in terms of a mass or moles.
"""
struct Solid <: Reagent
    name::String
    molecular_weight::Union{Unitful.MolarMass,Missing}
    density::Union{Unitful.Density,Missing}
    pubchemid::Union{Integer,Missing}
end
"""
    struct Liquid <: Reagent

Liquids are [`Reagent`](@ref) subtypes that exist in liquid phase at STP. We typically express liquid quantities in terms of a volume.
"""
struct Liquid <: Reagent
    name::String
    molecular_weight::Union{Unitful.MolarMass,Missing}
    density::Union{Unitful.Density,Missing}
    pubchemid::Union{Integer,Missing}
end

"""
    struct Gas <: Reagent

Gases are [`Reagent`](@ref) subtypes that exist in gas phase at STP. They have the same fields as
[`Solid`](@ref) and [`Liquid`](@ref).
"""
struct Gas <: Reagent
    name::String
    molecular_weight::Union{Unitful.MolarMass,Missing}
    density::Union{Unitful.Density,Missing}
    pubchemid::Union{Integer,Missing}
end

# Reagent has a name::String field, so it isn't isbits and Julia's default ==/hash fall back to
# object identity rather than value equality. SolidDict/LiquidDict/dissolutions use Reagent as
# a Dict key and currently only work because callers happen to reuse the same canonical `const`
# binding everywhere -- this makes that safe by construction (mirrors the equivalent fix already
# applied to Species). Constrained to same-concrete-type pairs so a Solid and a Liquid with
# identical fields are still correctly distinct.
#
# molecular_weight/density are hashed via a canonical unit (g/mol, g/mL), not the raw stored
# Quantity -- Unitful's own hash isn't unit-normalized, so e.g. 1.98u"g/L" and 0.00198u"g/mL" are
# `==`/`isequal` (same physical value) but would otherwise hash differently, breaking Julia's
# hash/equality contract (and any Dict/Set lookup, including dissolutions) for a Reagent whose
# fields weren't given in exactly the same unit every time it was constructed. Confirmed live: this
# is exactly what happened round-tripping a Gas reagent through the database, which canonicalizes
# density to g/mL on upload.
_hash_canon(x::Missing) = x
_hash_canon(x::Unitful.MolarMass) = uconvert(u"g/mol",x)
_hash_canon(x::Unitful.Density) = uconvert(u"g/mL",x)

Base.:(==)(a::T,b::T) where T<:Reagent = a.name==b.name && isequal(a.molecular_weight,b.molecular_weight) && isequal(a.density,b.density) && isequal(a.pubchemid,b.pubchemid)
Base.hash(a::Reagent,h::UInt) = hash(typeof(a),hash(a.name,hash(_hash_canon(a.molecular_weight),hash(_hash_canon(a.density),hash(a.pubchemid,h)))))

"""
    struct Species

Represents a *species* — what a [`Reagent`](@ref) behaves as once it's part of a reactive system
(e.g. Na⁺, Cl⁻ from dissolved NaCl; or, trivially, glucose's own identity for a non-dissociating
reagent). `Species` values are never added directly to a [`Stock`](@ref) — they exist purely as the
output vocabulary of [`dissolution`](@ref) (per-`Reagent`) and [`Recipe`](@ref) (per-`Stock`),
without changing how `Stock` stores its (undissociated) `Reagent` components.

A species carries a `name`, an integer `charge` (`0` for neutral species), and one of two
descriptions of its mass:

- an elemental formula string such as `"C6H12O6"` (see `CHESSCore.parse_formula`), from which
  [`molecular_weight`](@ref) is derived using atomic masses; or
- a stored molecular weight (or `missing`), for a species whose formula is not registered.

```julia
julia> Species("glucose",0,"C6H12O6")

julia> Species("mystery ion",1,missing)
```

Unlike `Reagent`, `Species` has real value-based equality/hash (not Julia's identity-based default)
because dissolutions and the identity-default fallback (see [`dissolution`](@ref)) routinely
construct `Species` values on the fly, and those must compare equal to independently-constructed-but-
identical values for `Dict` lookups (e.g. `Recipe`/`total_concentration`) to work correctly. Two
species are equal when their name, charge, and formula are equal (and, for species without a
formula, their stored molecular weights).
"""
struct Species
    name::String
    charge::Integer
    formula::Union{Dict{Symbol,Int},Missing}
    stored_molecular_weight::Union{Unitful.MolarMass,Missing}
    function Species(name::AbstractString,charge::Integer,formula::Union{Dict{Symbol,Int},Missing},stored_molecular_weight::Union{Unitful.MolarMass,Missing})
        !ismissing(formula) && !ismissing(stored_molecular_weight) && throw(ArgumentError(
            "Species \"$name\" was given both a formula and a stored molecular weight; give one or the other"))
        ismissing(formula) || isempty(formula) && throw(ArgumentError("Species \"$name\" has an empty formula"))
        new(String(name),charge,formula,stored_molecular_weight)
    end
end
Species(name::AbstractString,charge::Integer,formula::AbstractString) = Species(name,charge,parse_formula(formula),missing)
Species(name::AbstractString,charge::Integer,molecular_weight::Union{Unitful.MolarMass,Missing}) = Species(name,charge,missing,molecular_weight)
Species(name::AbstractString,formula::AbstractString) = Species(name,0,formula)
Species(name::AbstractString,molecular_weight::Union{Unitful.MolarMass,Missing}) = Species(name,0,molecular_weight)

Base.:(==)(a::Species,b::Species) = a.name==b.name && a.charge==b.charge && isequal(a.formula,b.formula) && isequal(a.stored_molecular_weight,b.stored_molecular_weight)
Base.hash(a::Species,h::UInt) = hash(a.name,hash(a.charge,hash(a.formula,hash(_hash_canon(a.stored_molecular_weight),h))))

function Base.show(io::IO,c::Species)
    try
        print(io,symbol(c))
    catch e
        e isa ArgumentError || rethrow()
        print(io,name(c))
    end
end

"""
    name(x::Species)
Access the `name` property of a [`Species`](@ref).
"""
name(x::Species)=x.name
"""
    molecular_weight(x::Species)
Return the molecular weight of a [`Species`](@ref): derived from its elemental formula using atomic
masses when it has one, otherwise its stored molecular weight (`missing` if none).
"""
molecular_weight(x::Species) = ismissing(x.formula) ? x.stored_molecular_weight : formula_mass(x.formula)
"""
    formula(x::Species)
Return the elemental formula of a [`Species`](@ref) as a dictionary from element symbol to atom
count, or `missing` if no formula is registered.
"""
formula(x::Species)=x.formula
"""
    charge(x::Species)
Access the `charge` property of a [`Species`](@ref).
"""
charge(x::Species)=x.charge

"""
    const H⁺

The canonical hydrogen ion (proton), used by [`pH`](@ref)/[`total_concentration`](@ref). Any custom
[`dissolution`](@ref) rule representing proton transfer (e.g. a strong base contributing a
*negative* count, so it nets against acids in the same sum) should reuse this
exact value rather than defining its own separate "H+" `Species`, so contributions net correctly.
"""
const H⁺ = Species("H+",1,"H")

"""
    const OH⁻

The canonical hydroxide ion, used by [`net_hydrogen_ion_concentration`](@ref)/[`pH`](@ref). Bases
should register their real dissociation formula using this value (e.g. `Na⁺ + OH⁻` for NaOH) rather
than a negative [`H⁺`](@ref) count -- see [`Dissolution`](@ref).
"""
const OH⁻ = Species("OH-",-1,"OH")

"""
    struct Dissolution

Describes the stoichiometric products of a [`Reagent`](@ref) breaking down into [`Species`](@ref)s
— e.g. `Dissolution(Dict(Na⁺=>1, Cl⁻=>1))` for NaCl, or `Dissolution(Dict(glucose_chem=>1))`
for a non-dissociating reagent (its own identity). Coefficients must be non-negative -- represent an
acid/base's hydroxide contribution via [`OH⁻`](@ref), not a negative [`H⁺`](@ref) count (see
[`net_hydrogen_ion_concentration`](@ref)) -- since [`molecular_weight`](@ref) sums a reagent's
registered products directly.

`+` and `*` build a `Dissolution` from [`Species`](@ref) values: `spc"Na+" + spc"Cl-"`, or
`spc"Mg2+" + 2*spc"Cl-"`. A reagent is defined from one by [`@reagent_formula`](@ref) or registered
with [`set_dissolution!`](@ref).
"""
struct Dissolution
    products::Dict{Species,Int}
    function Dissolution(products::Dict{Species,Int})
        all(c->c>=0, values(products)) || throw(ArgumentError(
            "Dissolution coefficients must be non-negative -- represent bases via OH⁻ (see `OH⁻`), not a negative H⁺ count"))
        new(products)
    end
end

Base.:(==)(a::Dissolution,b::Dissolution) = a.products == b.products
Base.hash(a::Dissolution,h::UInt) = hash(a.products,hash(:Dissolution,h))

"""
    const dissolutions

Registry mapping a specific [`Reagent`](@ref) *value* (e.g. the `NaCl` returned by `@reagent`) to its
[`Dissolution`](@ref). A per-value registry, not per-type dispatch, because individual reagents
are themselves named *values* of a small set of types (`Solid`/`Liquid`/`Gas`) — dispatch on
`typeof(reagent)` cannot distinguish e.g. `HCl` from `NaOH` (both `Solid`). Prefer
[`set_dissolution!`](@ref) over mutating this directly.
"""
const dissolutions = Dict{Reagent,Dissolution}()

"""
    set_dissolution!(r::Reagent,rule::Dissolution)

Register that `r` breaks down into ions/chemicals according to `rule` when dissolved — see
[`dissolution`](@ref).
"""
function set_dissolution!(r::Reagent,rule::Dissolution)
    dissolutions[r]=rule
    return nothing
end

"""
    dissolution(x::Reagent)

Return the [`Dissolution`](@ref) describing how `x` breaks down into [`Species`](@ref)s when
dissolved. Every `Reagent` has a dissolution — a non-electrolyte's default (for anything not
registered via [`set_dissolution!`](@ref)) is simply its own identity `Species`
(`Dissolution(Dict(Species(name(x),0,molecular_weight(x))=>1))`), not "no dissolution."
"""
function dissolution(x::Reagent)
    haskey(dissolutions,x) && return dissolutions[x]
    return Dissolution(Dict(Species(name(x),0,molecular_weight(x))=>1))
end

Base.:*(n::Integer,c::Species) = Dissolution(Dict(c=>n))
Base.:*(c::Species,n::Integer) = n*c
Base.:*(n::Integer,d::Dissolution) = Dissolution(Dict(k=>v*n for (k,v) in d.products))
Base.:*(d::Dissolution,n::Integer) = n*d
Base.:+(a::Species,b::Species) = Dissolution(mergewith(+,Dict(a=>1),Dict(b=>1)))
Base.:+(a::Dissolution,b::Species) = Dissolution(mergewith(+,a.products,Dict(b=>1)))
Base.:+(a::Species,b::Dissolution) = b+a
Base.:+(a::Dissolution,b::Dissolution) = Dissolution(mergewith(+,a.products,b.products))


"""
    @species labname name charge formula

Define a new [`Species`](@ref) value (e.g. an ion like Na⁺, or a standalone neutral species) and
import it into the workspace under `labname`. `charge` is `0` for neutral species. `formula` is an
elemental formula string such as `"C6H12O6"`; the molecular weight is derived from it. A molar
mass (or `missing`) may be given instead of a formula for a species whose formula is not registered.

Example:
```julia
julia> @species Na⁺ "Na+" 1 "Na"
Na+

julia> @species glucose_species "D-glucose" 0 "C6H12O6"
D-glucose
```

See also: [`@reagent`](@ref) for defining physical-form `Reagent`s instead, [`@spc_str`](@ref),
[`Dissolution`](@ref).
"""
macro species(labsymb,name,charge,formula)
    ls = Symbol(labsymb)
    docstr = """
            $labsymb

        The species $name (charge $charge)

        Formula: $formula
        """
    esc(quote
        const global $ls = CHESSCore.Species($name,$charge,$formula)
        @doc $docstr $ls
    end)
end


"""
    @reagent labname name type molecular_weight density pubchemid

Define a new reagent (a physical `Solid`/`Liquid`/`Gas`) and import it into the workspace under
`labname`. The `name` argument is the display name for the reagent, which can include a larger set
of characters and formatting than the `labname`. Automatically registers the reagent's identity
[`Species`](@ref) via [`set_dissolution!`](@ref) (discoverable in [`dissolutions`](@ref)),
matching the default [`dissolution`](@ref) would compute anyway for a non-dissociating reagent.

There are three valid type parameters for reagents:
1) [`Solid`](@ref)
2) [`Liquid`](@ref)
3) [`Gas`](@ref)

For a given reagent, its `type` parameter should be the phase in which it exists at STP.


Examples:
```julia
julia> using Unitful

julia> @reagent water "water" Liquid 18.015u"g/mol" 1.00u"g/mL" 962
water

julia> molecular_weight(water)
18.015 g mol⁻¹

julia> @reagent myreagent "my madeup reagent" Solid missing missing missing # reagents without defined properties can be created with the `missing` keyword
myreagent

julia> molecular_weight(myreagent)
missing
```

Reagents can also be defined manually with type constructors.

Example:
```julia
julia> water=Liquid("water",18.015u"g/mol",1.00u"g/mL",962)
water
```

See also: [`Solid`](@ref), [`Liquid`](@ref), [`Gas`](@ref), [`@reagent_formula`](@ref)
"""
macro reagent(labsymb,name,type,molecular_weight,density,pubchemid)

    expr =Expr(:block)
    push!(expr.args,quote
        Base.@__doc__ $CHESSCore.@reagent_symbols $labsymb $name $type $molecular_weight $density $pubchemid
        end
    )

    push!(expr.args,quote
        $labsymb
    end )

    esc(expr)
end





"""
    @spc_str(chemical)

String macro to easily recall [`Species`](@ref) identity values defined in lab modules that have
been registered with [`CHESSCore.register_lab`](@ref)

If the symbol is defined for a [`CHESSCore.Species`](@ref) in multiple modules, the symbol from the most
recently registred module will be used.

Example:

```julia
julia> spc"Na+"
Na+
```
The [`@spc_str`](@ref) macro is most useful for building [`Dissolution`](@ref) values:

```julia
julia> spc"Na+" + spc"Cl-"
```

See also: [`@rgt_str`](@ref) for looking up [`Reagent`](@ref)s instead.
"""
macro spc_str(chemical)
    # A bare Symbol lookup, not Meta.parse(chemical) -- charged chemical names routinely end in
    # `+`/`-` (Na+, Cl-), which Julia's parser treats as an incomplete binary expression rather than
    # part of an identifier. Symbol(str) has no such ambiguity for any string content. Compound
    # expression parsing (e.g. for speciesparse) is unaffected -- only this bare-lookup macro changes.
    sym = Symbol(chemical)
    labmods = [CHESSCore]
    for m in CHESSCore.labmodules
        # Find registered lab extension modules which are also loaded by
        # __module__ (required so that precompilation will work).
        if isdefined(__module__, nameof(m)) && getfield(__module__, nameof(m)) === m
            push!(labmods, m)
        end
    end
    esc(lookup_named_value(labmods, sym, spcstr_check_bool))
end

"""
    @rgt_str(reagent)

String macro to easily recall [`Reagent`](@ref)s defined in lab modules that have been registered
with [`CHESSCore.register_lab`](@ref) — mirrors [`@spc_str`](@ref), targeting `Reagent` instead of
`Species`.

Example:

```julia
julia> rgt"water"
water

julia> 1u"mL" * rgt"water"
```
"""
macro rgt_str(reagent)
    # Bare Symbol lookup -- see the comment in @spc_str for why this doesn't use Meta.parse.
    sym = Symbol(reagent)
    labmods = [CHESSCore]
    for m in CHESSCore.labmodules
        if isdefined(__module__, nameof(m)) && getfield(__module__, nameof(m)) === m
            push!(labmods, m)
        end
    end
    esc(lookup_named_value(labmods, sym, rgtstr_check_bool))
end


macro reagent_symbols(labsymb,name,type,molecular_weight,density,pubchemid)
    ls= Symbol(labsymb)
    ln = Meta.quot(ls)
    docstr= """
            $labsymb

        The $type reagent $name with [`PubChem ID`](https://pubchem.ncbi.nlm.nih.gov) $pubchemid

        Molecular Weight: $molecular_weight\\
        Density: $density

        See also: [`$type`](@ref)
        """
    cprops = :($molecular_weight,$density,$pubchemid)
    esc(quote

        $(chemprops_expr(__module__,ln,cprops))
        const global $ls = $type($name,$molecular_weight,$density,$pubchemid)
        CHESSCore.set_dissolution!($ls,CHESSCore.Dissolution(Dict(CHESSCore.Species($name,0,$molecular_weight)=>1)))
        @doc $docstr $ls
    end)
end

"""
    @reagent_formula labname name type formula density pubchemid

Define a new reagent whose [`dissolution`](@ref) is set from an explicit [`Dissolution`](@ref) (built from
[`Species`](@ref) values via `+`/`*`), rather than a separately-specified molecular weight. No
`molecular_weight` is stored directly -- [`molecular_weight`](@ref) derives it on demand from the
registered dissolution, so there's only ever one number, not a baked-in copy that could drift from
the stoichiometry. Use this when a reagent's real stoichiometry matters (e.g. an ionic solid); use
[`@reagent`](@ref) for the simpler common case.

Registers the dissolution immediately (like [`@reagent`](@ref) does for its own default identity
dissolution) -- safe for direct/interactive use in a single running session (a script, a notebook, a
REPL), but **not** safe for reagents defined inside a precompiled package's top-level code: mutating
`dissolutions` (owned by CHESSCore) as a side effect of a *dependent* package's own
precompilation isn't guaranteed to survive into a fresh session loading that package's precompiled
cache (Julia's module-initialization guidance is that such state belongs in `__init__`, which runs on
every load, not just once at compile time). A lab-constants package with real, non-default
[`Species`](@ref) formulas to register (e.g. ionic salts) should instead register them explicitly
from its own `__init__()`, via [`set_dissolution!`](@ref) called on a [`Dissolution`](@ref)
built with `+`/`*` -- see `CHESSLabConstants/src/chemicals/electrolytes.jl` for a worked example of this
pattern.

Example:
```julia
julia> @reagent_formula NaCl "sodium chloride" Solid (spc"Na+"+spc"Cl-") missing missing
NaCl

julia> molecular_weight(NaCl) # derived: sum of each species' molecular_weight × its coefficient
```

See also: [`@reagent`](@ref), [`Dissolution`](@ref), [`set_dissolution!`](@ref)
"""
macro reagent_formula(labsymb,name,type,formula,density,pubchemid)
    ls = Symbol(labsymb)
    esc(quote
        local d = $formula
        const global $ls = $type($name,missing,$density,$pubchemid)
        CHESSCore.set_dissolution!($ls,d)
        $ls
    end)
end




function chemprops_expr(m::Module,n,chemprops)
    if m === CHESSCore
        :($(_chemprops(CHESSCore))[$n]= $chemprops)
    else
        # We add the chemical properties to dictionaries in both CHESSCore and the module `m` so that the factor is available in both
        quote
            $(_chemprops(m))[$n]=$chemprops
            $(_chemprops(CHESSCore))[$n]=$chemprops
        end
    end
end





# see Unitful.jl

"""
    reagentparse(str; reagent_context=CHESSCore)

Non-macro equivalent of [`@rgt_str`](@ref) — parses `str` as a [`Reagent`](@ref) expression, looked
up against `reagent_context` (a `Module` or list of `Module`s).
"""
function reagentparse(str; reagent_context=CHESSCore)
    ex = Meta.parse(str)
    eval(lookup_named_value(reagent_context, ex, rgtstr_check_bool))
end

"""
    speciesparse(str; species_context=CHESSCore)

Non-macro equivalent of [`@spc_str`](@ref) — parses `str` as a [`Species`](@ref) expression, looked
up against `species_context` (a `Module` or list of `Module`s).
"""
function speciesparse(str; species_context=CHESSCore)
    ex = Meta.parse(str)
    eval(lookup_named_value(species_context, ex, spcstr_check_bool))
end
const allowed_funcs = [:*, :/, :^, :sqrt, :√, :+, :-, ://]

"""
    lookup_named_value(labmods, ex, check::Function)

Shared lookup machinery behind [`@spc_str`](@ref), [`@rgt_str`](@ref), [`@org_str`](@ref), and
[`@loc_str`](@ref): resolve a bare symbol (or an arithmetic expression/tuple of symbols) against a
list of modules, using `check(value)` to decide whether a candidate binding is of the desired kind.
Falls back to searching all globally registered `labmodules` for a helpful "did you mean"
suggestion (Levenshtein distance) when nothing matches.
"""
function lookup_named_value(labmods, ex::Expr, check::Function)
    if ex.head == :call
        ex.args[1] in allowed_funcs ||
            throw(ArgumentError(
                  """$(ex.args[1]) is not a valid function call when parsing this expression.
                   Only the following functions are allowed: $allowed_funcs"""))
        for i=2:length(ex.args)
            if typeof(ex.args[i])==Symbol || typeof(ex.args[i])==Expr
                ex.args[i]=lookup_named_value(labmods, ex.args[i], check)
            end
        end
        return ex
    elseif ex.head == :tuple
        for i=1:length(ex.args)
            if typeof(ex.args[i])==Symbol
                ex.args[i]=lookup_named_value(labmods, ex.args[i], check)
            else
                throw(ArgumentError("Only use symbols inside the tuple."))
            end
        end
        return ex
    else
        throw(ArgumentError("Expr head $(ex.head) must equal :call or :tuple"))
    end
end

const _super_digits = Dict('0'=>'⁰','1'=>'¹','2'=>'²','3'=>'³','4'=>'⁴','5'=>'⁵','6'=>'⁶','7'=>'⁷','8'=>'⁸','9'=>'⁹')
const _super_sign = Dict('+'=>'⁺','-'=>'⁻')

"""
    _charge_symbol_candidates(sym::Symbol)

Generate plausible canonical-superscript-charge spellings of `sym`'s plain-ASCII form (e.g. `:Na+`
-> `[:Na⁺]`; `:Ca2+` -> `[:Ca⁺, :Ca²⁺]`; `Symbol("SO4 2-")` -> `[:SO4⁻, :SO4²⁻]`), superscripting a
trailing ASCII `+`/`-` and, progressively, 0/1/2 trailing digits before it. Internal whitespace is
stripped first (CHESSCore's registered names never contain spaces, even though some display `name`
strings do, e.g. `"SO4 2-"`). Returns `Symbol[]` if `sym` doesn't end in an ASCII `+`/`-` at all.
Candidates are tried in order (fewest digits superscripted first) by
[`lookup_named_value`](@ref), which only accepts one that resolves to an actual registered binding
-- this is what resolves the ambiguity between a charge-magnitude digit (`Ca2+` -> `Ca²⁺`) and a
formula digit that happens to precede the sign (`H2PO4-` -> `H2PO4⁻`, not `H2PO⁴⁻`).
"""
function _charge_symbol_candidates(sym::Symbol)
    s = replace(String(sym), " "=>"")
    isempty(s) && return Symbol[]
    haskey(_super_sign,s[end]) || return Symbol[]
    supersign = _super_sign[s[end]]
    body = s[1:end-1]
    candidates = [Symbol(body*supersign)]
    digits_taken = ""
    while !isempty(body) && isdigit(body[end]) && length(digits_taken) < 2
        digits_taken = body[end]*digits_taken
        body = body[1:end-1]
        push!(candidates, Symbol(body*join(_super_digits[c] for c in digits_taken)*supersign))
    end
    return candidates
end

function lookup_named_value(labmods, sym::Symbol, check::Function)
    has_value = m->(isdefined(m,sym) && check(getfield(m, sym)))
    inds = findall(has_value, labmods)
    if isempty(inds)
        for cand in _charge_symbol_candidates(sym)
            cand_has_value = m->(isdefined(m,cand) && check(getfield(m, cand)))
            cand_inds = findall(cand_has_value, labmods)
            if !isempty(cand_inds)
                sym = cand
                has_value = cand_has_value
                inds = cand_inds
                break
            end
        end
    end
    if isempty(inds)
        # Check whether the value exists in the global list to give an improved
        # error message.
        hintidx = findfirst(has_value, labmodules)
        if hintidx !== nothing
            hintmod = labmodules[hintidx]
            throw(ArgumentError(
                """Symbol `$sym` was found in the globally registered lab module $hintmod
                   but was not in the provided list of lab modules $(join(labmods, ", ")).

                   (Consider `using $hintmod` in your module?)"""))
        else
            all_vals = vcat(map(x->filter(y-> !_is_generated_name(y) && check(getfield(x,y)),names(x;all=true)),labmods)...)
            idxs=findall(String(sym),String.(all_vals),StringDistances.Levenshtein();min_score=0.5)
            max_return = 4
            outlen=min(length(idxs),max_return)
            idxs=idxs[1:outlen]
            ch=String.(all_vals[idxs])
            stmt="~no suggestions available~"
            if outlen > 1
                stmt = string("Did you mean: ",join(ch[1:(end-1)],", ",),", or ",ch[end],"?")
            elseif outlen == 1
                stmt = string("Did you mean: $(ch[1])?")
            end
            throw(ArgumentError("""Symbol $sym could not be found in lab modules $labmods

            $stmt
            """))
        end
    end

    m = labmods[inds[end]]
    u = getfield(m, sym)

    any(u != u1 for u1 in getfield.(labmods[inds[1:(end-1)]], sym)) &&
        @warn """Symbol $sym was found in multiple registered lab modules.
                 We will use the one from $m."""
    return u
end

lookup_named_value(unitmod::Module, ex::Symbol, check::Function) = lookup_named_value([unitmod], ex, check)

lookup_named_value(unitmods, literal::Number, check::Function) = literal

spcstr_check_bool(::Species) =true
spcstr_check_bool(::Any) =false

rgtstr_check_bool(::Reagent) =true
rgtstr_check_bool(::Any) =false

# `names(m; all=true)` also lists compiler-generated bindings (e.g. Julia 1.13 adds `#139#val`
# globals holding documented constants such as `H⁺`). Their names start with `#`, so they can never
# be written in code and must be skipped by every scan that maps values back to names.
_is_generated_name(n::Symbol) = startswith(string(n),'#')

"""
    symbol(x; context=vcat([CHESSCore],CHESSCore.labmodules))

Return the `Symbol` that `x` is bound to somewhere in `context` (a `Module` or list of `Module`s,
default: CHESSCore plus every module registered via [`CHESSCore.register_lab`](@ref)) — the reverse of
looking a value up via [`@spc_str`](@ref)/[`@rgt_str`](@ref)/[`@org_str`](@ref). This is the
reliable way to get back the identifier you'd use to reference `x` in code; [`name`](@ref) is a
separate, display-oriented string not guaranteed to correspond to any actual binding (e.g. `H⁺` is
bound under `:H⁺`, but `name(H⁺) == "H+"`). Throws `ArgumentError` if no matching binding is found
(common for ephemeral values, e.g. `Species` values built on the fly by [`dissolution`](@ref)'s default
branch, which were never bound to a constant at all).
"""
function symbol(x; context=vcat([CHESSCore],CHESSCore.labmodules))
    mods = context isa Module ? [context] : context
    for m in mods
        for n in names(m; all=true)
            _is_generated_name(n) && continue
            isdefined(m,n) || continue
            v = getfield(m,n)
            v isa typeof(x) && v == x && return n
        end
    end
    throw(ArgumentError("No symbol found for value of type $(typeof(x)) in the given context"))
end




"""
    convert(desired_unit, current_unit, ingredient::Union{Reagent,Species})

[Unitful.uconvert](https://painterqubits.github.io/Unitful.jl/stable/conversion/#Unitful.uconvert) wrapper to convert a quantity from a molar quantity to a mass quantity and vice-versa, for either a [`Reagent`](@ref) or a [`Species`](@ref).

`convert` accesses the stored `molecular_weight` to make the conversion using the [Unitful.uconvert](https://painterqubits.github.io/Unitful.jl/stable/conversion/#Unitful.uconvert) function.
"""
function convert(y::Unitful.MassUnits,x::Unitful.Amount,ingredient::Union{Reagent,Species})
    ismissing(molecular_weight(ingredient)) ? error("$(ingredient)'s molecular weight is unknown") : return uconvert(y,x *molecular_weight(ingredient))
end

function convert(y::Unitful.AmountUnits,x::Unitful.Mass,ingredient::Union{Reagent,Species})
    ismissing(molecular_weight(ingredient)) ? error("$(ingredient)'s molecular weight is unknown") : return uconvert(y,x / molecular_weight(ingredient))
end

function convert(y::Unitful.DensityUnits,x::Unitful.Molarity,ingredient::Union{Reagent,Species})
    ismissing(molecular_weight(ingredient)) ? error("$(ingredient)'s molecular weight is unknown") : return uconvert(y,x *molecular_weight(ingredient))
end

function convert(y::Unitful.MolarityUnits,x::Unitful.Density,ingredient::Union{Reagent,Species})
    ismissing(molecular_weight(ingredient)) ? error("$(ingredient)'s molecular weight is unknown") : return uconvert(y,x /molecular_weight(ingredient))
end
