# Real ionic dissociation chemistry for the electrolyte salts (plus HCl/NaOH and the ammonium salts)
# defined in solids.jl, expressed as Dissolution algebra over the cited ion Species in ions.jl rather
# than raw Dict literals -- e.g. `Na⁺+Cl⁻` instead of `Dict(Na⁺=>1,Cl⁻=>1)`. molecular_weight(::Reagent)
# derives its result from a reagent's registered Dissolution once one exists (see
# CHESSCore/src/stocks/Chemicals.jl), overriding the reagent's own stored value -- these reagents are
# therefore defined in solids.jl with `missing` molecular_weight, so the Dissolution below (built entirely
# from PubChem-cited ion Species) is the *only* source of truth for their molecular weight, with no
# separately-cached, independently-driftable compound-level number. Hydrates register their waters of
# hydration as an explicit H2O product (they really are released into solution) to keep the derived
# weight matching the correct hydrate value.
#
# `set_dissolution!` mutates CHESSCore's single global `dissolutions` Dict directly, and state written
# there while this package precompiles is not saved with it, so these calls are wrapped in a function
# invoked from CHESSLabConstants's own __init__ instead of running at top-level here. (`@reagent` with a
# formula or Dissolution argument also keeps the dissolution in this module's own registry, which
# `register_lab` merges, so it does not need this arrangement.)
function _register_electrolyte_dissolutions!()
    # anhydrous salts (no water-of-hydration term needed)
    set_dissolution!(HCl,(CHESSCore.H⁺+Cl⁻))
    set_dissolution!(NaOH,(Na⁺+CHESSCore.OH⁻))
    set_dissolution!(sodium_chloride,(Na⁺+Cl⁻))
    set_dissolution!(potassium_chloride,(K⁺+Cl⁻))
    # iron_chloride/nickel_chloride/sodium_selenite: checked 2026-08-14 against the lab's actual
    # stocklist (Reagent_StockList.xlsx) and/or stored-density self-consistency -- confirmed genuinely
    # anhydrous (nickel_chloride: Sigma N6136-100G "anhydrous"; sodium_selenite: Sigma 71950-100G
    # "ANHYDROUS"; iron_chloride: not in the stocklist, but its stored density matches the anhydrous
    # reference value cleanly, unlike the hydrates fixed below).
    set_dissolution!(iron_chloride,(Fe³⁺+3*Cl⁻))
    set_dissolution!(nickel_chloride,(Ni²⁺+2*Cl⁻))
    set_dissolution!(sodium_selenite,(2*Na⁺+SeO3²⁻))
    set_dissolution!(silver_nitrate,(Ag⁺+NO3⁻))
    set_dissolution!(sodium_bicarbonate,(Na⁺+HCO3⁻))
    set_dissolution!(sodium_carbonate,(2*Na⁺+CO3²⁻))
    set_dissolution!(tin_fluoride,(Sn²⁺+2*F⁻))
    # zinc_chloride: checked 2026-08-14 against the lab's stocklist (Sigma Z0152-100G, plain "ZINC
    # CHLORIDE CELL CULTURE", no hydrate noted) -- confirmed anhydrous, unlike zinc_sulfate below.
    set_dissolution!(zinc_chloride,(Zn²⁺+2*Cl⁻))
    set_dissolution!(sodium_acetate_anhydrous,(Na⁺+OAc⁻))
    set_dissolution!(potassium_phosphate_di,(2*K⁺+HPO4²⁻))
    set_dissolution!(potassium_phosphate_mono,(K⁺+H2PO4⁻))
    set_dissolution!(ammonium_chloride,(NH4⁺+Cl⁻))
    set_dissolution!(ammonium_nitrate,(NH4⁺+NO3⁻))
    set_dissolution!(ammonium_sulfate,(2*NH4⁺+SO4²⁻))
    # lysine is really L-Lysine monohydrochloride (Sigma/Thermo L5626, PubChem CID 69568) -- the
    # cation is already defined in pKa_data.jl as the acid/base chain's own protonated endpoint.
    set_dissolution!(lysine,(LysineCation+Cl⁻))

    # hydrates -- waters of hydration included so derived molecular_weight still matches the stored value
    set_dissolution!(calcium_chloride,(Ca²⁺+2*Cl⁻+2*H2O)) # dihydrate
    # cobalt_chloride/copper_chloride/copper_sulfate/potassium_aluminum_sulfate: fixed 2026-08-14 --
    # each was registered anhydrous, but its own stored density matched a hydrate's (not the
    # anhydrous form's) real density; see solids.jl for the per-reagent evidence.
    set_dissolution!(cobalt_chloride,(Co²⁺+2*Cl⁻+6*H2O)) # hexahydrate
    set_dissolution!(copper_chloride,(Cu²⁺+2*Cl⁻+2*H2O)) # dihydrate
    set_dissolution!(copper_sulfate,(Cu²⁺+SO4²⁻+5*H2O)) # pentahydrate
    set_dissolution!(potassium_aluminum_sulfate,(K⁺+Al³⁺+2*SO4²⁻+12*H2O)) # dodecahydrate
    # cobalt_nitrate/sodium_dichromate/sodium_molybdate/sodium_tungstate: fixed 2026-08-14 -- each was
    # registered anhydrous, corrected against the lab's actual purchase records (Reagent_StockList.xlsx:
    # Sigma 230375-100G "COBALT(II) NITRATE HEXAHYDRATE"; Sigma 398063-100G "Sodium dichromate
    # dihydrate"; catalog 243655-100G "Sodium molybdate dihydrate"; Sigma 223336-100G "SODIUM TUNGSTATE
    # DIHYDRATE"). See solids.jl for each reagent's density evidence.
    set_dissolution!(cobalt_nitrate,(Co²⁺+2*NO3⁻+6*H2O)) # hexahydrate
    set_dissolution!(sodium_dichromate,(2*Na⁺+Cr2O7²⁻+2*H2O)) # dihydrate
    set_dissolution!(sodium_molybdate,(2*Na⁺+MoO4²⁻+2*H2O)) # dihydrate
    set_dissolution!(sodium_tungstate,(2*Na⁺+WO4²⁻+2*H2O)) # dihydrate
    # zinc_sulfate: fixed 2026-08-14 -- was registered anhydrous, but its stored density matched the
    # heptahydrate's (not the anhydrous form's) real density, and the lab's own purchase record
    # confirms "ZINC SULFATE HEPTAHYDRATE" (Sigma Z0251-100G). See solids.jl for the density evidence.
    set_dissolution!(zinc_sulfate,(Zn²⁺+SO4²⁻+7*H2O)) # heptahydrate
    set_dissolution!(magnesium_sulfate,(Mg²⁺+SO4²⁻+7*H2O)) # heptahydrate
    set_dissolution!(manganese_chloride,(Mn²⁺+2*Cl⁻+4*H2O)) # tetrahydrate
    set_dissolution!(manganese_sulfate,(Mn²⁺+SO4²⁻+H2O)) # monohydrate
    set_dissolution!(iron_sulfate,(Fe²⁺+SO4²⁻+7*H2O)) # heptahydrate
    set_dissolution!(iron_nitrate,(Fe³⁺+3*NO3⁻+9*H2O)) # nonahydrate
    set_dissolution!(sodium_acetate_trihydrate,(Na⁺+OAc⁻+3*H2O))
    set_dissolution!(sodium_citrate_dihydrate,(3*Na⁺+Citrate³⁻+2*H2O))
    set_dissolution!(sodium_phosphate_di,(2*Na⁺+HPO4²⁻+7*H2O)) # heptahydrate
    set_dissolution!(sodium_phosphate_di_anhydrous,(2*Na⁺+HPO4²⁻)) # anhydrous (e.g. Sigma S9763)
    set_dissolution!(sodium_phosphate_mono,(Na⁺+H2PO4⁻+H2O)) # monohydrate
    set_dissolution!(sodium_succinate_hexahydrate,(2*Na⁺+C4H4O4²⁻+6*H2O))
    # cysteine is really L-Cysteine hydrochloride monohydrate (Thermo Fisher BP376, PubChem CID
    # 23462) -- the cation is already defined in pKa_data.jl as the acid/base chain's own
    # protonated endpoint.
    set_dissolution!(cysteine,(CysteineCation+Cl⁻+H2O))

    # Tetracycline family HCl salts -- their stored molecular_weight is the salt mass, not the free
    # base (confirmed by exact arithmetic; see pKa_data.jl's comment above their Species
    # definitions). Complete dissociation into the protonated tetracycline cation + Cl-, exactly like
    # the ammonium salts above; the cation's own further acid/base equilibrium is registered
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
