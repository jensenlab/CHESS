
"""
    const Kw

The thermodynamic (activity-basis) autoionization constant of water at 25°C, `1.0e-14`. Used by
[`pH`](@ref)'s general equilibrium solver; corrected for ionic strength (via [`activity_coefficient`](@ref))
exactly like any other equilibrium constant when `ionic_strength_correction=true`.
"""
const Kw = 1.0e-14

"""
    struct AcidBaseSystem

A linear "conjugate family" of [`Chemical`](@ref) protonation states, from fully-protonated to
fully-deprotonated -- e.g. phosphoric acid's `[H3PO4, H2PO4⁻, HPO4²⁻, PO4³⁻]`, or a monoprotic acid's
`[HA, A⁻]`. `pKa[i]` is the equilibrium constant (as a p-value) linking `species[i] ⇌ species[i+1] +
H⁺`.

This same linear-chain shape represents zwitterions too (e.g. an amino acid's `[cation, zwitterion,
anion]`) -- nothing about the type assumes the fully-protonated reference state is neutral; only that
each successive state carries exactly one fewer positive charge, which the constructor verifies
against each [`Chemical`](@ref)'s own registered `charge`.

Registered against a [`Reagent`](@ref) via [`set_acid_base_system!`](@ref) -- independent of (and
additional to) that reagent's [`CompositionRule`](@ref), which continues to answer the separate
question of complete-dissociation mass bookkeeping (`molecular_weight`/`recipe`). A `Reagent` may have
both, neither, or just one.
"""
struct AcidBaseSystem
    species::Vector{Chemical}
    pKa::Vector{Float64}
    function AcidBaseSystem(species::Vector{Chemical},pKa::Vector{Float64})
        length(species) >= 2 || throw(ArgumentError("AcidBaseSystem needs at least 2 species (1 equilibrium step)"))
        length(pKa) == length(species)-1 || throw(ArgumentError(
            "AcidBaseSystem needs exactly length(species)-1 pKa values, got $(length(pKa)) for $(length(species)) species"))
        for i in 1:length(pKa)
            charge(species[i+1]) == charge(species[i])-1 || throw(ArgumentError(
                "AcidBaseSystem species must decrease in charge by exactly 1 at each step: $(species[i]) (charge $(charge(species[i]))) -> $(species[i+1]) (charge $(charge(species[i+1])))"))
        end
        new(species,pKa)
    end
end

Base.:(==)(a::AcidBaseSystem,b::AcidBaseSystem) = a.species==b.species && a.pKa==b.pKa
Base.hash(a::AcidBaseSystem,h::UInt) = hash(a.species,hash(a.pKa,h))

"""
    const acid_base_systems

Registry mapping a specific [`Reagent`](@ref) *value* to its [`AcidBaseSystem`](@ref) -- mirrors
[`composition_rules`](@ref) (a per-value, not per-type, registry, for the same reason: individual
reagents are themselves named values of a small set of types). Prefer [`set_acid_base_system!`](@ref)
over mutating this directly. Absence (see [`acid_base_system`](@ref)) means "inert with respect to
proton transfer," not an error -- the overwhelming majority of reagents (salts, sugars, antibiotics,
...) are exactly that.
"""
const acid_base_systems = Dict{Reagent,AcidBaseSystem}()

"""
    set_acid_base_system!(r::Reagent,sys::AcidBaseSystem)

Register that `r` participates in acid/base equilibrium according to `sys` once dissolved -- see
[`acid_base_system`](@ref), [`pH`](@ref).
"""
function set_acid_base_system!(r::Reagent,sys::AcidBaseSystem)
    acid_base_systems[r]=sys
    return nothing
end

"""
    acid_base_system(r::Reagent)

Return the [`AcidBaseSystem`](@ref) registered for `r`, or `nothing` if `r` is inert with respect to
proton transfer (the default for any reagent not registered via [`set_acid_base_system!`](@ref)).
"""
acid_base_system(r::Reagent) = get(acid_base_systems,r,nothing)

"""
    activity_coefficient(z::Integer, ionic_strength::Real)

The Davies-equation activity coefficient for an ion of charge `z` at the given `ionic_strength`
(dimensionless mol/L value, i.e. already `ustrip`ped): `log10(γ) = -0.509 z² (√I/(1+√I) - 0.3I)` at
25°C. `γ` is always `1.0` for a neutral species (`z==0`), matching the convention that activity
corrections only apply to charged species.

Reliability is charge-dependent, not just concentration-dependent: because of the `z²` term, a
divalent ion receives 4x the correction of a monovalent ion at the same ionic strength, and a
trivalent ion 9x -- so Davies degrades for `|z|≥2` well within the ~0.1-0.5 mol/L range it's
nominally reliable for monovalent ions (a well-documented limitation of Davies specifically, not an
implementation quirk here). [`pH(::Stock)`](@ref) surfaces this via a warning (see
[`_check_davies_reliability`](@ref)) rather than silently returning a number that may be off by a full
pH unit or more for polyvalent systems at moderate-to-high concentration -- confirmed empirically
against real measurements (bicarbonate/succinate-heavy stocks in CHESSLabConstants's empirical
measurement library, `CHESSLabConstants/test/empirical_measurements.jl`).
"""
function activity_coefficient(z::Integer,ionic_strength::Real)
    z==0 && return 1.0
    I = ionic_strength
    sqrtI = sqrt(I)
    log_gamma = -0.509*z^2*(sqrtI/(1+sqrtI) - 0.3*I)
    return exp10(log_gamma)
end

"""
    const ion_parameters

Registry mapping a specific [`Chemical`](@ref) *value* to its Truesdell-Jones (extended Debye-Hückel)
ion-size parameter `å` (Ångströms) and empirical `b` parameter, as `(å,b)`. Prefer
[`set_ion_parameters!`](@ref) over mutating this directly. Absence means "no citable per-species
parameter" -- [`_activity_coefficient`](@ref) falls back to [`activity_coefficient`](@ref) (Davies) for
any `Chemical` not registered here, exactly like [`acid_base_systems`](@ref)'s absence-means-inert
convention.
"""
const ion_parameters = Dict{Chemical,Tuple{Float64,Float64}}()

"""
    set_ion_parameters!(chem::Chemical, a::Float64, b::Float64)

Register `chem`'s Truesdell-Jones ion-size parameter `a` (å, Ångströms) and empirical `b` parameter --
see [`ion_parameters`](@ref), [`_activity_coefficient`](@ref).
"""
function set_ion_parameters!(chem::Chemical,a::Float64,b::Float64)
    ion_parameters[chem] = (a,b)
    return nothing
end

# H⁺/OH⁻ are universal to every pH solve (not lab-specific), so their real, citable Truesdell-Jones
# parameters are registered here at the CHESSCore level rather than left for a lab module. Source:
# wateq4f.dat (PHREEQC thermodynamic database), SOLUTION_SPECIES block, H+ and OH- primary/derived
# master species -gamma lines (fetched directly from
# https://raw.githubusercontent.com/usgs-coupled/phreeqc3/master/database/wateq4f.dat and verified).
set_ion_parameters!(H⁺,9.0,0.0)
set_ion_parameters!(OH⁻,3.5,0.0)

"""
    _activity_coefficient(chem::Chemical, z::Integer, I::Real)

Per-species activity coefficient at ionic strength `I` (dimensionless mol/L): Truesdell-Jones
(`log10(γ) = -A z² √I/(1+B å √I) + b I`, standard extended-Debye-Hückel constants `A=0.5085`,
`B=0.3281` at 25°C) using `chem`'s registered `(å,b)` from [`ion_parameters`](@ref) if present, else
[`activity_coefficient`](@ref) (Davies) as the documented-less-reliable fallback for any species
without a citable literature parameter (most custom organic `Chemical`s -- amino acid states,
antibiotics, etc. -- fall back this way; only the well-characterized inorganic ions a lab module
registers get the upgrade).
"""
function _activity_coefficient(chem::Chemical,z::Integer,I::Real)
    z==0 && return 1.0
    p = get(ion_parameters,chem,nothing)
    p === nothing && return activity_coefficient(z,I)
    a,b = p
    sqrtI = sqrt(I)
    A,B = 0.5085,0.3281
    log_gamma = -A*z^2*sqrtI/(1+B*a*sqrtI) + b*I
    return exp10(log_gamma)
end

"""
    _beta_products(pKa::Vector{Float64}, pH::Real)

The equilibrium concentration ratio `[speciesⱼ]/[species₁]` for each species in an
[`AcidBaseSystem`](@ref) (`beta[1]=1.0` for `species₁` itself), computed in log10-space for numerical
stability across wide pKa spans (e.g. phosphoric acid's pKa1≈2.1 to pKa3≈12.4). Unnormalized -- see
[`_alpha_fractions`](@ref) for the normalized (sum-to-1) mole-fraction version used when `species₁`'s
concentration isn't itself fixed; this unnormalized form is what an [`OpenSystemSpecies`](@ref) needs,
since there `[species₁]` (not the family total) is the fixed quantity.
"""
function _beta_products(pKa::Vector{Float64},pH::Real)
    n = length(pKa)
    logbeta = Vector{Float64}(undef,n+1)
    logbeta[1] = 0.0
    for j in 1:n
        logbeta[j+1] = logbeta[j] + (pH-pKa[j])
    end
    return exp10.(logbeta)
end

"""
    _alpha_fractions(pKa::Vector{Float64}, pH::Real)

The equilibrium mole fraction of each species in an [`AcidBaseSystem`](@ref) (fully-protonated first)
at the given `pH` -- [`_beta_products`](@ref) normalized to sum to `1.0`. Returns a `Vector{Float64}`
of length `length(pKa)+1`.
"""
function _alpha_fractions(pKa::Vector{Float64},pH::Real)
    beta = _beta_products(pKa,pH)
    return beta./sum(beta)
end

"""
    _conditional_pKa(sys::AcidBaseSystem, gammas::Dict{Chemical,Float64})

Convert `sys`'s thermodynamic (activity-basis) `pKa`s to concentration-basis "conditional" pKa's using
the current per-species activity coefficients `gammas` (keyed by `Chemical` identity -- see
[`_activity_coefficient`](@ref); real Truesdell-Jones values where registered, Davies fallback
otherwise). The thermodynamic constant is `Kaⱼ = {H⁺}{speciesⱼ₊₁}/{speciesⱼ} =
γ(H⁺)[H⁺]·γ(speciesⱼ₊₁)[speciesⱼ₊₁] / (γ(speciesⱼ)[speciesⱼ])`; solving for the concentration-basis
`Ka'ⱼ = [H⁺][speciesⱼ₊₁]/[speciesⱼ]` gives `Ka'ⱼ = Kaⱼ·γ(speciesⱼ)/(γ(H⁺)·γ(speciesⱼ₊₁))`, i.e.
`pKa'ⱼ = pKaⱼ + log10(γ(H⁺)·γ(speciesⱼ₊₁)/γ(speciesⱼ))`. Keying by species identity (not just charge
magnitude) means two same-charge species with different registered ion-size parameters get correctly
different shifts here, rather than being forced to share one value.
"""
function _conditional_pKa(sys::AcidBaseSystem,gammas::Dict{Chemical,Float64})
    n = length(sys.pKa)
    out = Vector{Float64}(undef,n)
    gH = gammas[H⁺]
    for j in 1:n
        out[j] = sys.pKa[j] + log10(gH*gammas[sys.species[j+1]]/gammas[sys.species[j]])
    end
    return out
end

"""
    abstract type AbstractAnalyticalSpecies

Common supertype for the equilibrium solver's per-family inputs -- an [`AnalyticalSpecies`](@ref)
(fixed total concentration, the mass-balance case; every family a [`Stock`](@ref)'s own recipe
produces) or an [`OpenSystemSpecies`](@ref) (fixed free-species concentration, an open-system boundary
condition like atmospheric CO2 -- see [`pH`](@ref)'s `water_correction` keyword). Both are consumed
identically by [`_species_concentrations`](@ref), which dispatches on the concrete type.
"""
abstract type AbstractAnalyticalSpecies end

"""
    struct AnalyticalSpecies

An [`AcidBaseSystem`](@ref) family together with its total analytical concentration in a particular
[`Stock`](@ref) (the sum, across every protonation state already present in the stock's
[`recipe`](@ref), divided by [`volume_estimate`](@ref)) -- the mass-balance input to the equilibrium
solver. Built by [`_analytical_species`](@ref).
"""
struct AnalyticalSpecies <: AbstractAnalyticalSpecies
    system::AcidBaseSystem
    total_concentration::Unitful.Molarity
end

"""
    struct OpenSystemSpecies

An [`AcidBaseSystem`](@ref) family held at a fixed *free-species* concentration (`system.species[1]`)
rather than a fixed total -- the correct model for a species in equilibrium with an external reservoir
at constant activity/partial pressure (e.g. dissolved atmospheric CO2, whose [CO2(aq)] is set by
Henry's law regardless of how much HCO3⁻/CO3²⁻ the solution's pH happens to pull it into). Unlike
[`AnalyticalSpecies`](@ref), the family's *total* concentration is not fixed -- it grows with pH as
more of the conjugate base forms, which is exactly the physics a fixed-total dose gets wrong for
poorly-buffered basic solutions (see [`pH`](@ref)'s `water_correction` keyword docs). Registered as
the default correction via [`set_default_water_correction!`](@ref).
"""
struct OpenSystemSpecies <: AbstractAnalyticalSpecies
    system::AcidBaseSystem
    free_concentration::Unitful.Molarity
end

"""
    _species_concentrations(fam::AbstractAnalyticalSpecies, pH::Real, pKa_eff::Dict{AcidBaseSystem,Vector{Float64}})

The concentration of every species in `fam.system` at the given `pH`, as a plain `Vector{Float64}`
(mol/L, dimensionless): `total_concentration .* alphas` for a fixed-total [`AnalyticalSpecies`](@ref),
or `free_concentration .* betas` for a fixed-free-species [`OpenSystemSpecies`](@ref) -- the shared
interface [`_charge_balance_residual`](@ref)/[`_ionic_strength`](@ref)/[`speciation`](@ref) consume so
neither needs to branch on which kind of family it's looking at.
"""
function _species_concentrations(fam::AnalyticalSpecies,pH::Real,pKa_eff::Dict{AcidBaseSystem,Vector{Float64}})
    return ustrip(u"mol/L",fam.total_concentration).*_alpha_fractions(pKa_eff[fam.system],pH)
end
function _species_concentrations(fam::OpenSystemSpecies,pH::Real,pKa_eff::Dict{AcidBaseSystem,Vector{Float64}})
    return ustrip(u"mol/L",fam.free_concentration).*_beta_products(pKa_eff[fam.system],pH)
end

"""
    const default_water_correction

Holds the [`OpenSystemSpecies`](@ref) used by [`pH(::Stock)`](@ref)'s `water_correction=true` when no
`water_correction_source` is given -- `nothing` until a lab module registers one via
[`set_default_water_correction!`](@ref) (e.g. CHESSLabConstants's atmospheric-CO2 correction). Mirrors
[`acid_base_systems`](@ref) in spirit, but there's exactly one relevant default here rather than a
per-reagent registry.
"""
const default_water_correction = Ref{Union{Nothing,OpenSystemSpecies}}(nothing)

"""
    set_default_water_correction!(spec::OpenSystemSpecies)

Register `spec` as the default open-system correction [`pH(::Stock)`](@ref) applies when
`water_correction=true` and no `water_correction_source` is passed explicitly.
"""
function set_default_water_correction!(spec::OpenSystemSpecies)
    default_water_correction[] = spec
    return nothing
end

"""
    struct SpeciationResult

Per-family diagnostic output of [`speciation`](@ref): `fractions[i]` and `concentrations[i]`
correspond to `system.species[i]` at the solved pH.
"""
struct SpeciationResult
    system::AcidBaseSystem
    fractions::Vector{Float64}
    concentrations::Vector{Unitful.Molarity}
end

"""
    _analytical_species(s::Stock)

Partition `s`'s [`recipe`](@ref) into the equilibrium solver's inputs: one [`AnalyticalSpecies`](@ref)
per distinct [`AcidBaseSystem`](@ref) registered on any reagent actually present in `s` (deduplicated,
since e.g. potassium and sodium phosphate salts share the same phosphate `AcidBaseSystem`), and a list
of `(chemical, concentration)` pairs for every other charged [`Chemical`](@ref) in the recipe --
excluding [`H⁺`](@ref)/[`OH⁻`](@ref) themselves (handled as the solver's own pH-dependent unknowns) and
any chemical that's part of a family (handled via that family's speciation instead). Carrying the
`Chemical` itself (not just its charge) lets the activity-correction machinery look up per-species
Truesdell-Jones parameters (see [`_activity_coefficient`](@ref)) rather than only a shared
per-charge-magnitude value.
"""
function _analytical_species(s::Stock)
    r = recipe(s)
    vol = volume_estimate(s)
    systems = Set{AcidBaseSystem}()
    for reagent in Iterators.flatten((reagents(solids(s)),reagents(liquids(s))))
        sys = acid_base_system(reagent)
        sys === nothing || push!(systems,sys)
    end
    families = AnalyticalSpecies[]
    family_chemicals = Set{Chemical}()
    for sys in systems
        total = sum((molar_amount(r,chem) for chem in sys.species);init=0u"mol") / vol
        push!(families,AnalyticalSpecies(sys,total))
        union!(family_chemicals,sys.species)
    end
    strong_ions = Tuple{Chemical,Unitful.Molarity}[]
    for (chem,moles) in r.amounts
        (chem==H⁺ || chem==OH⁻) && continue
        chem in family_chemicals && continue
        charge(chem)==0 && continue
        push!(strong_ions,(chem,moles/vol))
    end
    return families,strong_ions
end

"""
    _charge_balance_residual(pH, families, pKa_eff, strong_net, Kw_eff)

The generalized electroneutrality condition `pH` is root-found against: `[H⁺] - [OH⁻] +
Σ_families Σⱼ [speciesⱼ](pH)·chargeⱼ + strong_net`, all as dimensionless mol/L values -- computed via
[`_species_concentrations`](@ref), so this works identically for a fixed-total [`AnalyticalSpecies`](@ref)
family and a fixed-free-species [`OpenSystemSpecies`](@ref) one. Reduces algebraically to CHESSCore's
original strong-electrolyte-only `net_hydrogen_ion_concentration` when `families` is empty (see
[`pH`](@ref)'s fast path, which uses that exact original formula directly rather than this general one).
"""
function _charge_balance_residual(pH::Real,families::Vector{<:AbstractAnalyticalSpecies},pKa_eff::Dict{AcidBaseSystem,Vector{Float64}},strong_net::Float64,Kw_eff::Float64)
    Hp = exp10(-pH)
    OHm = Kw_eff/Hp
    total = Hp-OHm+strong_net
    for fam in families
        concs = _species_concentrations(fam,pH,pKa_eff)
        charges = charge.(fam.system.species)
        total += sum(concs.*charges)
    end
    return total
end

"""
    _bisect_pH(f; lo=-2.0, hi=16.0, tol=1e-9, maxiter=200)

Small self-contained bisection root-finder for [`pH`](@ref)'s charge-balance objective `f` (a
monotonically decreasing function of pH, bounded on `[lo,hi]`) -- deliberately not Newton's method
(no derivative needed, guaranteed convergence given a valid bracket, no divergence risk with
near-degenerate pKa's) and deliberately not a dependency on Roots.jl (this objective's shape doesn't
need it). Emits a warning and returns a boundary estimate if `f` doesn't change sign across
`[lo,hi]` (an extreme edge case), rather than erroring.
"""
function _bisect_pH(f;lo::Float64=-2.0,hi::Float64=16.0,tol::Float64=1e-9,maxiter::Int=200)
    flo,fhi = f(lo),f(hi)
    if sign(flo)==sign(fhi)
        @warn "pH: charge-balance residual doesn't change sign over [$lo,$hi]; returning a boundary estimate"
        return abs(flo)<abs(fhi) ? lo : hi
    end
    for _ in 1:maxiter
        (hi-lo)<tol && break
        mid = (lo+hi)/2
        fm = f(mid)
        if sign(fm)==sign(flo)
            lo,flo = mid,fm
        else
            hi,fhi = mid,fm
        end
    end
    return (lo+hi)/2
end

"""
    _ionic_strength(pH, families, strong_ions, gammas, pKa_eff)

Ionic strength `I = 0.5·Σcᵢzᵢ²` at the given `pH`, over every charged species actually present: `[H⁺]`,
`[OH⁻]` (using the activity-corrected `Kw_eff = Kw/(γ(H⁺)·γ(OH⁻))` -- each its own per-species γ from
`gammas`, not one shared value, since H⁺ and OH⁻ are different species with different real ion-size
parameters), every strong ion, and every family state (via `pKa_eff`, so this stays self-consistent
with whatever pKa's were actually used to solve for `pH`).
"""
function _ionic_strength(pH::Real,families::Vector{<:AbstractAnalyticalSpecies},strong_ions::Vector{Tuple{Chemical,Unitful.Molarity}},gammas::Dict{Chemical,Float64},pKa_eff::Dict{AcidBaseSystem,Vector{Float64}})
    Hp = exp10(-pH)
    Kw_eff = Kw/(gammas[H⁺]*gammas[OH⁻])
    OHm = Kw_eff/Hp
    I = 0.5*(Hp+OHm)
    for (chem,c) in strong_ions
        z = charge(chem)
        I += 0.5*ustrip(u"mol/L",c)*z^2
    end
    for fam in families
        concs = _species_concentrations(fam,pH,pKa_eff)
        charges = charge.(fam.system.species)
        I += 0.5*sum(concs.*charges.^2)
    end
    return I
end

"""
    _check_davies_reliability(pH::Real, I::Float64, families, strong_ions, pKa_eff)

Warn if `I` exceeds a charge-scaled threshold (`0.5/z²`, following directly from Davies' own `z²`
correction term -- an approximation of where the correction becomes unreliable, not a literature-cited
cutoff) for the highest charge magnitude *materially and still-Davies-corrected* present -- i.e. a
species contributing more than 1% of the total ionic strength `I` at the solved `pH` (via
[`_species_concentrations`](@ref), not just appearing somewhere in a family's chain definition) AND
with no registered [`ion_parameters`](@ref) (real Truesdell-Jones species -- e.g. CO3²⁻, Ca²⁺ once a lab
module registers them -- are exempt, since they no longer use Davies at all). This distinction matters
for e.g. the carbonic acid family: its chain includes CO3²⁻, but at near-neutral pH that species'
actual concentration is negligible, and checking chain membership alone would false-positive on every
`water_correction=true` call regardless of whether CO3²⁻ is actually present in any meaningful amount.
A no-op when everything materially present is monovalent, neutral, or already using real
Truesdell-Jones parameters.
"""
function _check_davies_reliability(pH::Real,I::Float64,families::Vector{<:AbstractAnalyticalSpecies},strong_ions::Vector{Tuple{Chemical,Unitful.Molarity}},pKa_eff::Dict{AcidBaseSystem,Vector{Float64}})
    I <= 0 && return nothing
    max_z = 0
    for (chem,c) in strong_ions
        z = charge(chem)
        haskey(ion_parameters,chem) && continue
        contribution = 0.5*ustrip(u"mol/L",c)*z^2
        contribution > 0.01*I && (max_z = max(max_z,abs(z)))
    end
    for fam in families
        concs = _species_concentrations(fam,pH,pKa_eff)
        for (c,sp) in zip(concs,fam.system.species)
            haskey(ion_parameters,sp) && continue
            z = charge(sp)
            contribution = 0.5*c*z^2
            contribution > 0.01*I && (max_z = max(max_z,abs(z)))
        end
    end
    max_z <= 1 && return nothing
    threshold = 0.5/max_z^2
    I > threshold && @warn "pH: ionic strength ($(round(I,digits=3)) mol/L) with a species of charge magnitude $max_z present (no registered Truesdell-Jones parameter) exceeds Davies' reliable range (approximately $(round(threshold,digits=3)) mol/L here) -- the ionic-strength correction may be substantially overcorrecting; compare against ionic_strength_correction=false"
    return nothing
end

"""
    _relevant_chemicals(families, strong_ions)

Every distinct [`Chemical`](@ref) whose activity coefficient the solver needs each iteration: `H⁺`,
`OH⁻`, every species across every family's chain (including neutral ones, which always resolve to
`γ=1.0` -- see [`_activity_coefficient`](@ref)), and every strong-ion chemical.
"""
function _relevant_chemicals(families::Vector{<:AbstractAnalyticalSpecies},strong_ions::Vector{Tuple{Chemical,Unitful.Molarity}})
    chems = Set{Chemical}((H⁺,OH⁻))
    for fam in families
        union!(chems,fam.system.species)
    end
    for (chem,_) in strong_ions
        push!(chems,chem)
    end
    return chems
end

"""
    _solve_ph(families, strong_ions; ionic_strength_correction=true)

Shared solver core behind [`pH`](@ref) and [`speciation`](@ref): root-finds pH via
[`_bisect_pH`](@ref), then, if `ionic_strength_correction`, iterates the self-consistent
activity-coefficient loop (recompute ionic strength from the current speciation, recompute each
species' `γ` -- Truesdell-Jones or Davies, per [`_activity_coefficient`](@ref) -- recompute
conditional pKa's/Kw, re-solve -- typically converging within a handful of iterations) until `γ`
stabilizes or a small iteration cap is hit (in which case a warning is emitted and the best estimate
so far is returned, rather than erroring). Returns `(pH, pKa_eff)` -- the second so callers needing
per-species fractions (`speciation`) can report ones consistent with the pH actually solved for.
"""
function _solve_ph(families::Vector{<:AbstractAnalyticalSpecies},strong_ions::Vector{Tuple{Chemical,Unitful.Molarity}};ionic_strength_correction::Bool=true)
    strong_net = sum((ustrip(u"mol/L",charge(chem)*c) for (chem,c) in strong_ions);init=0.0)
    chems = _relevant_chemicals(families,strong_ions)
    gammas = Dict{Chemical,Float64}(chem=>1.0 for chem in chems)
    pH_est = 7.0
    pKa_eff = Dict{AcidBaseSystem,Vector{Float64}}(fam.system=>fam.system.pKa for fam in families)
    maxiter = ionic_strength_correction ? 10 : 1
    converged = !ionic_strength_correction
    I = 0.0
    for _ in 1:maxiter
        pKa_eff = Dict{AcidBaseSystem,Vector{Float64}}(fam.system=>_conditional_pKa(fam.system,gammas) for fam in families)
        Kw_eff = Kw/(gammas[H⁺]*gammas[OH⁻])
        pH_est = _bisect_pH(pH->_charge_balance_residual(pH,families,pKa_eff,strong_net,Kw_eff))
        ionic_strength_correction || break
        I = _ionic_strength(pH_est,families,strong_ions,gammas,pKa_eff)
        new_gammas = Dict(chem=>_activity_coefficient(chem,charge(chem),I) for chem in chems)
        if maximum(abs(log10(new_gammas[chem])-log10(gammas[chem])) for chem in chems) < 1e-6
            gammas = new_gammas
            converged = true
            break
        end
        gammas = new_gammas
    end
    converged || @warn "pH: ionic-strength self-consistency loop did not converge; returning the best estimate found"
    ionic_strength_correction && _check_davies_reliability(pH_est,I,families,strong_ions,pKa_eff)
    return pH_est,pKa_eff
end

"""
    pH(families::Vector{<:AbstractAnalyticalSpecies}, strong_ions; ionic_strength_correction=true)

The general, low-level entry point behind [`pH(::Stock)`](@ref): root-finds the solution pH of an
arbitrary mixture of acid/base `families` (each an [`AnalyticalSpecies`](@ref) or
[`OpenSystemSpecies`](@ref)) plus `strong_ions` (a list of `(chemical, concentration)` pairs for
fully-dissociated strong electrolytes -- carrying the [`Chemical`](@ref) itself, not just its charge,
so per-species activity parameters can be looked up; see [`_activity_coefficient`](@ref)). Set
`ionic_strength_correction=false` to get the ideal/infinite-dilution pH instead (no activity
correction).
"""
function pH(families::Vector{<:AbstractAnalyticalSpecies},strong_ions::Vector{<:Tuple{Chemical,<:Unitful.Molarity}};ionic_strength_correction::Bool=true)
    isempty(families) && return _pH_strong_electrolyte_only(sum((charge(chem)*c for (chem,c) in strong_ions);init=0.0u"mol/L"))
    p,_ = _solve_ph(families,convert(Vector{Tuple{Chemical,Unitful.Molarity}},strong_ions);ionic_strength_correction)
    return p
end

"""
    _pH_strong_electrolyte_only(net_conc)

CHESSCore's original strong-electrolyte-only pH formula (`net_conc` = net H⁺-minus-OH⁻ molar
concentration): `7.0` if zero, `-log10(net_conc)` if net H⁺, `14 - (-log10(-net_conc))` if net OH⁻.
[`pH(::Stock)`](@ref)'s dedicated fast path when no acid/base family is present, so the common
strong-electrolyte case is guaranteed bit-identical to the pre-equilibrium-solver behavior rather than
merely "solved and hoped to land in the same place."
"""
function _pH_strong_electrolyte_only(net_conc::Unitful.Molarity)
    conc = ustrip(uconvert(u"mol/L",net_conc))
    iszero(conc) && return 7.0
    conc>0 && return -log10(conc)
    return 14-(-log10(-conc))
end

"""
    speciation(s::Stock; ionic_strength_correction=true)

Per-family diagnostic breakdown of `s`'s acid/base equilibrium at its solved [`pH`](@ref): a
[`SpeciationResult`](@ref) for each distinct [`AcidBaseSystem`](@ref) present, giving the equilibrium
fraction and concentration of every protonation state. Returns an empty vector if `s` has no
registered acid/base families (pure strong-electrolyte stocks have nothing to speciate).
"""
function speciation(s::Stock;ionic_strength_correction::Bool=true)
    families,strong_ions = _analytical_species(s)
    isempty(families) && return SpeciationResult[]
    p,pKa_eff = _solve_ph(families,strong_ions;ionic_strength_correction)
    results = SpeciationResult[]
    for fam in families
        alphas = _alpha_fractions(pKa_eff[fam.system],p)
        concs = _species_concentrations(fam,p,pKa_eff).*u"mol/L"
        push!(results,SpeciationResult(fam.system,alphas,concs))
    end
    return results
end

"""
    _dose(r::Reagent, n::Unitful.Amount)

Build the `Stock` contribution of `n` moles of `r`, regardless of whether `r` is a [`Solid`](@ref)
(molar quantities are already supported directly, see `Stocks.jl`) or a [`Liquid`](@ref) (only
volume-constructible there, so `n` is converted to a volume via `molecular_weight`/[`density`](@ref)
first). Used by [`adjust_pH`](@ref) to titrate with either kind of reagent uniformly. Missing
`molecular_weight`/`density` surface the same errors `convert` already raises elsewhere; `Gas`
titrants aren't supported.
"""
_dose(r::Solid,n::Unitful.Amount) = n*r
_dose(r::Liquid,n::Unitful.Amount) = uconvert(u"mL",n*molecular_weight(r)/density(r))*r

"""
    _bracket_titrant(f; n0, growth=2.0, max_expand=60)

Expand outward from `f(0u"mol")` until `f` changes sign, establishing a bracket `(lo,hi)` (molar
amounts) for [`adjust_pH`](@ref)'s bisection -- mirrors [`_bisect_pH`](@ref)'s own
guaranteed-convergence-given-a-valid-bracket philosophy, but for "how much titrant" rather than "what
pH." Throws an error (not a warning) if no sign change is found within `max_expand` doublings, since
returning a stock that doesn't actually reach the target would be actively misleading, unlike
`_bisect_pH`'s own boundary-estimate fallback for an already-bounded pH range.
"""
function _bracket_titrant(f;n0::Unitful.Amount,growth::Float64=2.0,max_expand::Int=60)
    lo = 0.0u"mol"
    flo = f(lo)
    hi = n0
    fhi = f(hi)
    iter = 0
    while sign(fhi)==sign(flo) && iter<max_expand
        hi *= growth
        fhi = f(hi)
        iter += 1
    end
    sign(fhi)==sign(flo) && error(
        "adjust_pH: could not bracket the target pH within $max_expand doublings of the titrant amount (tried up to $hi) -- the target may be unreachable with this titrant")
    return lo,hi
end

"""
    adjust_pH(s::Stock, target_ph::Real, acid::Reagent, base::Reagent;
              ionic_strength_correction=true, tol=1e-4, max_iter=60) -> Stock

Return a new `Stock` -- `s` plus however much of `acid` or `base` is needed -- whose [`pH`](@ref) is
within `tol` of `target_ph` (must be in `[1,14]`). `s` itself is never modified: this falls out of
`Stock`'s existing immutable design (`+`/`*` always construct new values, see `Stocks.jl`), the same
way every other stock-combining operation in CHESSCore already works.

Compares `pH(s)` to `target_ph` to decide direction -- `acid` if `s` is currently more basic than the
target, `base` if more acidic -- then root-finds the required molar amount via an expanding bracket
(see [`_bracket_titrant`](@ref)) followed by bisection, re-evaluating `pH(s + n*titrant)` at each
trial `n` (through [`_dose`](@ref), so `acid`/`base` can be either a `Solid` or a `Liquid`). This
reuses `pH(::Stock)` exactly as-is for every evaluation, so it works for any registered acid/base
chemistry -- strong or weak titrant, buffered or unbuffered `s` -- with no separate solver logic.

If `s` is already within `tol` of `target_ph`, returns `s` unchanged (no titrant needed).

`ionic_strength_correction` is forwarded to every internal `pH` call, matching `pH(::Stock)`'s own
keyword. If `max_iter` bisection steps aren't enough to reach `tol`, emits a warning and returns the
best candidate found, matching the warn-and-degrade style used throughout this solver (e.g.
[`_bisect_pH`](@ref), [`_solve_ph`](@ref)) -- rather than erroring outright, since a slightly
off-target result is still useful.
"""
function adjust_pH(s::Stock,target_ph::Real,acid::Reagent,base::Reagent;
                    ionic_strength_correction::Bool=true,tol::Float64=1e-4,max_iter::Int=60)
    1<=target_ph<=14 || throw(ArgumentError("adjust_pH: target_ph must be in [1,14], got $target_ph"))

    current = pH(s;ionic_strength_correction)
    abs(current-target_ph) < tol && return s

    titrant = current>target_ph ? acid : base
    f(n::Unitful.Amount) = pH(s+_dose(titrant,n);ionic_strength_correction) - target_ph

    n0 = max(uconvert(u"mol",volume_estimate(s)*1u"mmol/L"),1e-9u"mol")
    lo,hi = _bracket_titrant(f;n0)
    flo = f(lo)

    converged = false
    mid = lo
    for _ in 1:max_iter
        mid = (lo+hi)/2
        fm = f(mid)
        abs(fm) < tol && (converged=true; break)
        if sign(fm)==sign(flo)
            lo = mid
        else
            hi = mid
        end
    end
    converged || @warn "adjust_pH: did not converge to within tol=$tol after $max_iter iterations; returning the best estimate found"
    return s+_dose(titrant,mid)
end
