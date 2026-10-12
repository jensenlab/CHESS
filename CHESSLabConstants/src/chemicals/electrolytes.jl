# Dissolutions for reagents whose products include a species defined in pKa_data.jl (the conjugate-base
# and cation endpoints of the acid/base chains), which is included after solids.jl and so cannot be
# referenced in a `@reagent` line. Every other reagent with a Dissolution (the electrolyte salts, HCl, NaOH,
# the ammonium salts and the hydrates) gives it inline in its `@reagent` line in solids.jl, built from the
# ion Species in ions.jl, e.g. `(Na⁺+Cl⁻)`. Hydrates list their waters of hydration as an explicit H2O
# product, so the derived weight matches the hydrate. molecular_weight(::Reagent) derives from the
# Dissolution, so these reagents are defined in solids.jl with `missing` chemistry.
#
# `set_dissolution!` mutates CHESSCore's single global `dissolutions` Dict directly, and state written
# there while this package precompiles is not saved with it, so these calls are wrapped in a function
# invoked from CHESSLabConstants's own __init__ instead of running at top-level here. (`@reagent` with a
# formula or Dissolution argument also keeps the dissolution in this module's own registry, which
# `register_lab` merges, so it does not need this arrangement.)
function _register_electrolyte_dissolutions!()
    # lysine is really L-Lysine monohydrochloride (Sigma/Thermo L5626, PubChem CID 69568) -- the
    # cation is already defined in pKa_data.jl as the acid/base chain's own protonated endpoint.
    set_dissolution!(lysine,(LysineCation+Cl⁻))

    set_dissolution!(sodium_citrate_dihydrate,(3*Na⁺+Citrate³⁻+2*H2O))
    # cysteine is really L-Cysteine hydrochloride monohydrate (Thermo Fisher BP376, PubChem CID
    # 23462) -- the cation is already defined in pKa_data.jl as the acid/base chain's own
    # protonated endpoint.
    set_dissolution!(cysteine,(CysteineCation+Cl⁻+H2O))

    # Tetracycline family HCl salts -- their stored molecular_weight is the salt mass, not the free
    # base (confirmed by exact arithmetic; see pKa_data.jl's comment above their Species
    # definitions). Complete dissociation into the protonated tetracycline cation + Cl-, exactly like
    # the ammonium salts in solids.jl; the cation's own further acid/base equilibrium is registered
    # separately via AcidBaseSystem in pKa_data.jl.
    set_dissolution!(tetracycline,(TetracyclineCation+Cl⁻))
    set_dissolution!(doxycycline,(DoxycyclineCation+Cl⁻))
    set_dissolution!(chlortetracycline,(ChlortetracyclineCation+Cl⁻))
    set_dissolution!(minocycline,(MinocyclineCation+Cl⁻))

    # pyruvate/butyrate/tartrate are real sodium salts, confirmed against the lab's actual stocklist
    # (Reagent_StockList.xlsx: Sigma P5280 "Pyruvic Acid Sodium", Sigma 303410 "Sodium butyrate",
    # catalog AAA1618730 "Sodium L-(+) Tartrate" dihydrate) -- not bare ions with no counter-ion.
    # ascorbate turned out to be the plain free acid (both stocklist catalog lines are "L-ASCORBIC
    # ACID"), so it needs no Dissolution at all -- see its corrected molecular_weight/name in
    # solids.jl and its AcidBaseSystem registration in pKa_data.jl.
    set_dissolution!(sodium_pyruvate,(Na⁺+PyruvateAnion))
    set_dissolution!(sodium_butyrate,(Na⁺+ButyrateAnion))
    set_dissolution!(tartrate,(2*Na⁺+TartrateDianion+2*H2O)) # dihydrate
    return nothing
end
