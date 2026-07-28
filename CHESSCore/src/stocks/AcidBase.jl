
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
(dimensionless mol/L value, i.e. already `ustrip`ped), valid to roughly 0.5-1 mol/L: `log10(γ) =
-0.509 z² (√I/(1+√I) - 0.3I)` at 25°C. `γ` is always `1.0` for a neutral species (`z==0`), matching the
convention that activity corrections only apply to charged species.
"""
function activity_coefficient(z::Integer,ionic_strength::Real)
    z==0 && return 1.0
    I = ionic_strength
    sqrtI = sqrt(I)
    log_gamma = -0.509*z^2*(sqrtI/(1+sqrtI) - 0.3*I)
    return exp10(log_gamma)
end

"""
    _alpha_fractions(pKa::Vector{Float64}, pH::Real)

The equilibrium mole fraction of each species in an [`AcidBaseSystem`](@ref) (fully-protonated first)
at the given `pH`, computed in log10-space for numerical stability across wide pKa spans (e.g.
phosphoric acid's pKa1≈2.1 to pKa3≈12.4). Returns a `Vector{Float64}` of length `length(pKa)+1`
summing to `1.0`.
"""
function _alpha_fractions(pKa::Vector{Float64},pH::Real)
    n = length(pKa)
    logbeta = Vector{Float64}(undef,n+1)
    logbeta[1] = 0.0
    for j in 1:n
        logbeta[j+1] = logbeta[j] + (pH-pKa[j])
    end
    m = maximum(logbeta)
    weights = exp10.(logbeta.-m)
    s = sum(weights)
    return weights./s
end

"""
    _conditional_pKa(sys::AcidBaseSystem, gammas::Dict{Int,Float64})

Convert `sys`'s thermodynamic (activity-basis) `pKa`s to concentration-basis "conditional" pKa's using
the current Davies activity coefficients `gammas` (keyed by absolute charge magnitude). The
thermodynamic constant is `Kaⱼ = {H⁺}{speciesⱼ₊₁}/{speciesⱼ} = γ(H⁺)[H⁺]·γ(zⱼ-1)[speciesⱼ₊₁] /
(γ(zⱼ)[speciesⱼ])`; solving for the concentration-basis `Ka'ⱼ = [H⁺][speciesⱼ₊₁]/[speciesⱼ]` gives
`Ka'ⱼ = Kaⱼ·γ(zⱼ)/(γ(H⁺)·γ(zⱼ-1))`, i.e. `pKa'ⱼ = pKaⱼ + log10(γ(H⁺)·γ(zⱼ-1)/γ(zⱼ))`. Since higher
charge magnitudes are destabilized more strongly by ionic strength (Davies' `z²` dependence), this
correctly shifts equilibrium toward the more-deprotonated (higher-magnitude-charge) state as ionic
strength rises -- the standard "salt effect" promoting dissociation, not suppressing it.
"""
function _conditional_pKa(sys::AcidBaseSystem,gammas::Dict{Int,Float64})
    z0 = charge(sys.species[1])
    n = length(sys.pKa)
    out = Vector{Float64}(undef,n)
    g(z) = get(gammas,abs(z),1.0)
    gH = g(1)
    for j in 1:n
        zj = z0-(j-1)
        zj1 = zj-1
        out[j] = sys.pKa[j] + log10(gH*g(zj1)/g(zj))
    end
    return out
end

"""
    struct AnalyticalSpecies

An [`AcidBaseSystem`](@ref) family together with its total analytical concentration in a particular
[`Stock`](@ref) (the sum, across every protonation state already present in the stock's
[`recipe`](@ref), divided by [`volume_estimate`](@ref)) -- the mass-balance input to the equilibrium
solver. Built by [`_analytical_species`](@ref).
"""
struct AnalyticalSpecies
    system::AcidBaseSystem
    total_concentration::Unitful.Molarity
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
of `(charge, concentration)` pairs for every other charged [`Chemical`](@ref) in the recipe --
excluding [`H⁺`](@ref)/[`OH⁻`](@ref) themselves (handled as the solver's own pH-dependent unknowns) and
any chemical that's part of a family (handled via that family's speciation instead).
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
    strong_ions = Tuple{Int,Unitful.Molarity}[]
    for (chem,moles) in r.amounts
        (chem==H⁺ || chem==OH⁻) && continue
        chem in family_chemicals && continue
        charge(chem)==0 && continue
        push!(strong_ions,(charge(chem),moles/vol))
    end
    return families,strong_ions
end

"""
    _charge_balance_residual(pH, families, pKa_eff, strong_net, Kw_eff)

The generalized electroneutrality condition `pH` is root-found against: `[H⁺] - [OH⁻] +
Σ_families C_total·(z₀ - Σⱼ(j-1)·αⱼ(pH)) + strong_net`, all as dimensionless mol/L values. Reduces
algebraically to CHESSCore's original strong-electrolyte-only `net_hydrogen_ion_concentration` when
`families` is empty (see [`pH`](@ref)'s fast path, which uses that exact original formula directly
rather than this general one).
"""
function _charge_balance_residual(pH::Real,families::Vector{AnalyticalSpecies},pKa_eff::Dict{AcidBaseSystem,Vector{Float64}},strong_net::Float64,Kw_eff::Float64)
    Hp = exp10(-pH)
    OHm = Kw_eff/Hp
    total = Hp-OHm+strong_net
    for fam in families
        alphas = _alpha_fractions(pKa_eff[fam.system],pH)
        z0 = charge(fam.system.species[1])
        weighted = sum((j-1)*alphas[j] for j in eachindex(alphas))
        Ctot = ustrip(u"mol/L",fam.total_concentration)
        total += Ctot*(z0-weighted)
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
    _ionic_strength(pH, families, strong_ions, gamma1, pKa_eff)

Ionic strength `I = 0.5·Σcᵢzᵢ²` at the given `pH`, over every charged species actually present: `[H⁺]`,
`[OH⁻]` (using the activity-corrected `Kw` implied by `gamma1`, the current γ for singly-charged ions),
every strong ion, and every family state (via `pKa_eff`, so this stays self-consistent with whatever
pKa's were actually used to solve for `pH`).
"""
function _ionic_strength(pH::Real,families::Vector{AnalyticalSpecies},strong_ions::Vector{Tuple{Int,Unitful.Molarity}},gamma1::Float64,pKa_eff::Dict{AcidBaseSystem,Vector{Float64}})
    Hp = exp10(-pH)
    Kw_eff = Kw/(gamma1^2)
    OHm = Kw_eff/Hp
    I = 0.5*(Hp+OHm)
    for (z,c) in strong_ions
        I += 0.5*ustrip(u"mol/L",c)*z^2
    end
    for fam in families
        alphas = _alpha_fractions(pKa_eff[fam.system],pH)
        z0 = charge(fam.system.species[1])
        Ctot = ustrip(u"mol/L",fam.total_concentration)
        for (j,a) in enumerate(alphas)
            zj = z0-(j-1)
            I += 0.5*Ctot*a*zj^2
        end
    end
    return I
end

"""
    _solve_ph(families, strong_ions; ionic_strength_correction=true)

Shared solver core behind [`pH`](@ref) and [`speciation`](@ref): root-finds pH via
[`_bisect_pH`](@ref), then, if `ionic_strength_correction`, iterates the self-consistent
activity-coefficient loop (recompute ionic strength from the current speciation, recompute Davies
`γ`'s, recompute conditional pKa's/Kw, re-solve -- typically converging within a handful of
iterations) until `γ` stabilizes or a small iteration cap is hit (in which case a warning is emitted
and the best estimate so far is returned, rather than erroring). Returns `(pH, pKa_eff)` -- the second
so callers needing per-species fractions (`speciation`) can report ones consistent with the pH actually
solved for.
"""
function _solve_ph(families::Vector{AnalyticalSpecies},strong_ions::Vector{Tuple{Int,Unitful.Molarity}};ionic_strength_correction::Bool=true)
    strong_net = sum((ustrip(u"mol/L",z*c) for (z,c) in strong_ions);init=0.0)
    gammas = Dict{Int,Float64}(1=>1.0,2=>1.0,3=>1.0)
    pH_est = 7.0
    pKa_eff = Dict{AcidBaseSystem,Vector{Float64}}(fam.system=>fam.system.pKa for fam in families)
    maxiter = ionic_strength_correction ? 10 : 1
    converged = !ionic_strength_correction
    for _ in 1:maxiter
        pKa_eff = Dict{AcidBaseSystem,Vector{Float64}}(fam.system=>_conditional_pKa(fam.system,gammas) for fam in families)
        Kw_eff = Kw/(gammas[1]^2)
        pH_est = _bisect_pH(pH->_charge_balance_residual(pH,families,pKa_eff,strong_net,Kw_eff))
        ionic_strength_correction || break
        I = _ionic_strength(pH_est,families,strong_ions,gammas[1],pKa_eff)
        new_gammas = Dict(z=>activity_coefficient(z,I) for z in keys(gammas))
        if maximum(abs(log10(new_gammas[z])-log10(gammas[z])) for z in keys(gammas)) < 1e-6
            gammas = new_gammas
            converged = true
            break
        end
        gammas = new_gammas
    end
    converged || @warn "pH: ionic-strength self-consistency loop did not converge; returning the best estimate found"
    return pH_est,pKa_eff
end

"""
    pH(families::Vector{AnalyticalSpecies}, strong_ions; ionic_strength_correction=true)

The general, low-level entry point behind [`pH(::Stock)`](@ref): root-finds the solution pH of an
arbitrary mixture of acid/base `families` (each an [`AnalyticalSpecies`](@ref)) plus `strong_ions` (a
list of `(charge, concentration)` pairs for fully-dissociated strong electrolytes). Set
`ionic_strength_correction=false` to get the ideal/infinite-dilution pH instead (no Davies activity
correction).
"""
function pH(families::Vector{AnalyticalSpecies},strong_ions::Vector{<:Tuple{<:Integer,<:Unitful.Molarity}};ionic_strength_correction::Bool=true)
    isempty(families) && return _pH_strong_electrolyte_only(sum((z*c for (z,c) in strong_ions);init=0.0u"mol/L"))
    p,_ = _solve_ph(families,convert(Vector{Tuple{Int,Unitful.Molarity}},strong_ions);ionic_strength_correction)
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
        concs = fam.total_concentration.*alphas
        push!(results,SpeciationResult(fam.system,alphas,concs))
    end
    return results
end
