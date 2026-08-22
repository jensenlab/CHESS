"""
    abstract type Factor

A named, registrable description of a design-matrix column (a "factor"). Two concrete subtypes
distinguish domain *shape* -- [`CategoricalFactor`](@ref) (a fixed or registry-backed set of levels)
and [`ContinuousFactor`](@ref) (a numeric quantity) -- independent of `destination`, which answers a
different question: where a resolved value ends up.

`destination` values in use:
- `:reagent` (`ContinuousFactor` only) -- feeds `Stock`-building (see [`resolve_stock`](@ref)).
- `:organism` (`CategoricalFactor` only) -- promotes the row's `Stock` to a `Culture`, and is also
  recorded per-well (`:well_conditions`) since Pourfecto doesn't schedule inoculation.
- `:condition` (either subtype) -- a plain recorded value (e.g. temperature, atmosphere), never a
  `CHESSCore.Attribute` -- recorded per-plate (`:plate_conditions`).

`destination` is deliberately just a `Symbol`, not a closed enum -- new destinations can be added
without a package release, the same way unregistered `metadata` keys work for [`ParameterKind`](@ref).

`blocking` is orthogonal to both the type (Categorical/Continuous) and `destination` -- a temperature
factor and an atmosphere factor can both be blocking despite differing on both other axes. Two design
rows differing in any blocking factor's value must never be scheduled onto the same physical plate.
"""
abstract type Factor end

"""
    RESERVED_DESIGN_COLUMNS

Design columns recognized directly by the scheduling machinery, never resolved as a reagent or a
registered `Factor` -- the same "fixed, recognized schema" status `LAYOUT_COLUMNS` has for `:layout`.
- `:control_role`: `missing`/absent = an ordinary sample row; a `Symbol` (`:positive`/`:negative`/
  `:blank`/open-ended) = this row is a control template (see `expand_control_templates`).
- `:duplicates`: `missing`/`1` = one physical well (no extra copies); `N` = `N` total physical wells
  for this row (the row's own well plus `N-1` extra duplicates), aggregated back into one data point
  downstream by `CHESSProcessing`. Applies to any row, sample or control alike.
"""
const RESERVED_DESIGN_COLUMNS = (:control_role, :duplicates)

"""
    struct CategoricalFactor <: Factor

- `levels`: a stored zero-argument closure returning the currently-valid set of values -- e.g.
  `() -> (:aerobic, :anaerobic)` for a closed, static vocabulary, or `() -> keys(some_registry)` for
  an open, growing one (organism, backed by `CHESSLabConstants`). One field/type serves both cases;
  the difference is entirely in what the closure captures.
"""
struct CategoricalFactor <: Factor
    name::Symbol
    levels::Function
    blocking::Bool
    destination::Symbol
    function CategoricalFactor(name::Symbol, levels::Function, blocking::Bool, destination::Symbol)
        destination in (:organism, :condition) ||
            throw(ArgumentError("CategoricalFactor destination must be :organism or :condition, got :$destination"))
        return new(name, levels, blocking, destination)
    end
end

CategoricalFactor(name::Symbol; levels::Function, blocking::Bool = false, destination::Symbol) =
    CategoricalFactor(name, levels, blocking, destination)

"""
    struct ContinuousFactor <: Factor

A numeric factor -- most commonly a reagent quantity (`destination = :reagent`), resolved via
[`resolve_stock`](@ref) rather than a stored resolve function (see that docstring for why reagent
factors need no per-factor registration at all).
"""
struct ContinuousFactor <: Factor
    name::Symbol
    blocking::Bool
    destination::Symbol
    function ContinuousFactor(name::Symbol, blocking::Bool, destination::Symbol)
        destination in (:reagent, :condition) ||
            throw(ArgumentError("ContinuousFactor destination must be :reagent or :condition, got :$destination"))
        return new(name, blocking, destination)
    end
end

ContinuousFactor(name::Symbol; blocking::Bool = false, destination::Symbol) =
    ContinuousFactor(name, blocking, destination)

"""
    is_blocking(f::Factor) -> Bool

Whether two design rows differing in `f`'s value must never share a physical plate.
"""
is_blocking(f::Factor) = f.blocking

"""
    destination(f::Factor) -> Symbol

Where a resolved value for `f` ends up -- `:reagent`, `:organism`, or `:condition`.
"""
destination(f::Factor) = f.destination

"""
    factor_levels(f::CategoricalFactor) -> Any

Call `f`'s stored `levels` closure to get the currently-valid set of values. Named `factor_levels`,
not `levels`, to avoid colliding with `DataFrames`/`DataAPI`/`Missings`' own exported `levels`
(categorical-array levels) -- both would otherwise be ambiguous under a single `using`.
"""
factor_levels(f::CategoricalFactor) = f.levels()

const factor_registry = Dict{Symbol,Factor}()

"""
    register_factor!(f::Factor) -> Factor

Register `f` under `f.name`, making it resolvable via [`get_factor`](@ref). Raises
[`DuplicateRegistrationError`](@ref) if `f.name` is already registered.
"""
function register_factor!(f::Factor)
    haskey(factor_registry, f.name) && throw(DuplicateRegistrationError("Factor :$(f.name) is already registered"))
    factor_registry[f.name] = f
    return f
end

"""
    get_factor(name::Symbol) -> Factor

Look up the registered `Factor` for `name`. Throws `KeyError` if `name` isn't registered.
"""
function get_factor(name::Symbol)
    haskey(factor_registry, name) || throw(KeyError(name))
    return factor_registry[name]
end
