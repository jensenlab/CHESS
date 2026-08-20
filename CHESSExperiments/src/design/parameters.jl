"""
    struct ParameterKind

A named, typed, registrable key into an [`Experiment`](@ref)'s free-form `metadata` -- mirrors
[`QCMethod`](@ref)'s registry (itself mirroring `CHESSCore.Attribute`/`Read`/`LocationKind`
kind-registries). Lets a package (RunMaps, CHESSQC, ...) require e.g. `:positive_controls::Int`
with a default and a validator, without `Experiment` needing to know about that key in advance. Any
`metadata` key that isn't registered is still just a raw `Dict` lookup -- registration is opt-in
exactness, not a schema the whole `metadata` dict must conform to.

Fields:
- `name`: the key into `metadata` this kind governs.
- `type`: the expected Julia type of `metadata[name]`, checked only when the key is actually present
  -- `default` is returned as-is when absent, with no type check against it (so e.g. a `DataFrame`-typed
  parameter can still default to `nothing`, meaning "not set yet").
- `default`: value returned by [`get_parameter`](@ref) when `name` is absent from `metadata`;
  `missing` means the parameter is required (absence is an error).
- `validator`: optional `value -> Bool` predicate checked (only against a present value) after the type
  check; `nothing` skips it.
"""
struct ParameterKind
    name::Symbol
    type::Type
    default::Any
    validator::Union{Function,Nothing}
end

const parameter_registry = Dict{Symbol,ParameterKind}()

"""
    register_parameter!(name::Symbol, type::Type; default=missing, validator=nothing) -> ParameterKind

Register a [`ParameterKind`](@ref) under `name`, making it resolvable via [`get_parameter`](@ref).
Raises [`DuplicateRegistrationError`](@ref) if `name` is already registered.
"""
function register_parameter!(name::Symbol, type::Type; default = missing, validator::Union{Function,Nothing} = nothing)
    haskey(parameter_registry, name) && throw(DuplicateRegistrationError("Parameter :$name is already registered"))
    kind = ParameterKind(name, type, default, validator)
    parameter_registry[name] = kind
    return kind
end

"""
    get_parameter(experiment::Experiment, name::Symbol)

Look up `experiment.metadata[name]`. If present, type-checked against the registered
[`ParameterKind`](@ref) for `name` and validated if a `validator` was registered. If absent, returns
`kind.default` as-is (no type/validator check against the default -- it's allowed to be a sentinel like
`nothing` that isn't an instance of `type`), or errors if the parameter is required (`default ===
missing`).
"""
function get_parameter(experiment::Experiment, name::Symbol)
    haskey(parameter_registry, name) || throw(KeyError(name))
    kind = parameter_registry[name]
    if haskey(experiment.metadata, name)
        value = experiment.metadata[name]
        value isa kind.type || throw(ArgumentError("Parameter :$name expected a $(kind.type), got a $(typeof(value))"))
        isnothing(kind.validator) || kind.validator(value) || throw(ArgumentError("Parameter :$name failed validation: $value"))
        return value
    else
        kind.default === missing && throw(ArgumentError("Parameter :$name is required and has no default; set it in metadata"))
        return kind.default
    end
end

"""
    with_parameter(experiment::Experiment, name::Symbol, value) -> Experiment

Return a new `Experiment` with `metadata[name] = value` set (copy-on-write; `experiment` itself is
unmodified). Does **not** require `name` to be pre-registered -- writes stay as flexible as a raw
`Dict`; only [`get_parameter`](@ref) reads enforce the registry.
"""
function with_parameter(experiment::Experiment, name::Symbol, value)
    md = copy(experiment.metadata)
    md[name] = value
    return Experiment(experiment.design, md)
end

# Built-in parameters CHESSExperiments itself owns. Registered here (after register_parameter! is
# defined, using LAYOUT_COLUMNS from experiment.jl, included earlier) rather than at the top of
# experiment.jl -- registering into this package's own registry during its own precompilation is fine
# regardless of which file it happens in (unlike a *different* package registering into an
# already-precompiled foreign registry, e.g. CHESSQC's QCMethods, which does need __init__).
register_parameter!(:name, String)
register_parameter!(:layout, DataFrame; default = nothing, validator = df -> isempty(setdiff(LAYOUT_COLUMNS, Symbol.(names(df)))))

"""
    layout(experiment::Experiment)

Convenience accessor for `get_parameter(experiment, :layout)`.
"""
layout(experiment::Experiment) = get_parameter(experiment, :layout)
