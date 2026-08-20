"""
    abstract type QCMethod

A named, registrable QC/correction method (e.g. `CHESSQC`'s GP-based spatial correction). Concrete
subtypes are defined by whichever package implements the method (`CHESSQC` and friends); this package
only owns the registry, mirroring `CHESSCore.register_lab`/`@attribute`/`@read`'s pattern of a
global, name-keyed registry that any package can add to without the defining package needing to know
about it in advance. This is the same split as `CHESSCore` (generic kind registries) vs.
`CHESSLabConstants` (concrete registered kinds, plus the heavier domain-specific dependencies) --
`CHESSExperiments` stays agnostic and dependency-light; the actual algorithms, and packages like
`GaussianProcesses`/`Optim` they need, live in the package that implements them.

The registry is deliberately kept generic enough (name => type) that a future registry of entire named
experiment workflows (e.g. "kinetic growth assay" — a design template + QC pipeline + expected data
shape bundled together) can reuse the same mechanism once there's real workflow experience to draw the
abstraction from; that type doesn't exist yet.
"""
abstract type QCMethod end

const qc_method_registry = Dict{Symbol,Type{<:QCMethod}}()

"""
    register_qc_method!(name::Symbol, ::Type{T}) where {T<:QCMethod}

Register a concrete `QCMethod` subtype under `name`, making it resolvable via [`qc_method`](@ref).
Raises [`DuplicateRegistrationError`](@ref) if `name` is already registered.
"""
function register_qc_method!(name::Symbol, ::Type{T}) where {T<:QCMethod}
    haskey(qc_method_registry, name) && throw(DuplicateRegistrationError("QC method :$name is already registered to $(qc_method_registry[name])"))
    qc_method_registry[name] = T
    return T
end

"""
    qc_method(name::Symbol) -> Type{<:QCMethod}

Look up a registered `QCMethod` subtype by name.
"""
qc_method(name::Symbol) = qc_method_registry[name]

"""
    qc_methods() -> Vector{Symbol}

Names of every currently registered `QCMethod`.
"""
qc_methods() = collect(keys(qc_method_registry))
