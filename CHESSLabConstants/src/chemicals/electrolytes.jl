# Real ionic dissociation chemistry for the electrolyte salts (plus HCl/NaOH and the ammonium salts)
# defined in solids.jl, expressed as Formula algebra over the cited ion Chemicals in ions.jl rather
# than raw Dict literals -- e.g. `Na⁺+Cl⁻` instead of `Dict(Na⁺=>1,Cl⁻=>1)`. molecular_weight(::Reagent)
# derives its result from a reagent's registered CompositionRule once one exists (see
# CHESSCore/src/stocks/Chemicals.jl), overriding the reagent's own stored value -- these reagents are
# therefore defined in solids.jl with `missing` molecular_weight, so the Formula below (built entirely
# from PubChem-cited ion Chemicals) is the *only* source of truth for their molecular weight, with no
# separately-cached, independently-driftable compound-level number. Hydrates register their waters of
# hydration as an explicit H2O product (they really are released into solution) to keep the derived
# weight matching the correct hydrate value.
#
# `set_composition!` mutates CHESSCore's single global `composition_rules` Dict directly -- like
# occupancy_rules (see locations/occupancy_rules.jl), there is no per-module registry for it to survive
# precompilation through, so these calls are wrapped in a function invoked from CHESSLabConstants's own
# __init__ instead of running at top-level here (see `@reagent_formula`'s docstring in CHESSCore for why
# registering directly at the reagent's own definition site isn't safe for a precompiled package).
function _register_electrolyte_compositions!()
    # anhydrous salts (no water-of-hydration term needed)
    set_composition!(HCl,CompositionRule((CHESSCore.H⁺+Cl⁻).composition))
    set_composition!(NaOH,CompositionRule((Na⁺+CHESSCore.OH⁻).composition))
    set_composition!(sodium_chloride,CompositionRule((Na⁺+Cl⁻).composition))
    set_composition!(potassium_chloride,CompositionRule((K⁺+Cl⁻).composition))
    # iron_chloride/nickel_chloride/sodium_selenite: checked 2026-08-14 against the lab's actual
    # stocklist (Reagent_StockList.xlsx) and/or stored-density self-consistency -- confirmed genuinely
    # anhydrous (nickel_chloride: Sigma N6136-100G "anhydrous"; sodium_selenite: Sigma 71950-100G
    # "ANHYDROUS"; iron_chloride: not in the stocklist, but its stored density matches the anhydrous
    # reference value cleanly, unlike the hydrates fixed below).
    set_composition!(iron_chloride,CompositionRule((Fe³⁺+3*Cl⁻).composition))
    set_composition!(nickel_chloride,CompositionRule((Ni²⁺+2*Cl⁻).composition))
    set_composition!(sodium_selenite,CompositionRule((2*Na⁺+SeO3²⁻).composition))
    set_composition!(silver_nitrate,CompositionRule((Ag⁺+NO3⁻).composition))
    set_composition!(sodium_bicarbonate,CompositionRule((Na⁺+HCO3⁻).composition))
    set_composition!(sodium_carbonate,CompositionRule((2*Na⁺+CO3²⁻).composition))
    set_composition!(tin_fluoride,CompositionRule((Sn²⁺+2*F⁻).composition))
    set_composition!(zinc_chloride,CompositionRule((Zn²⁺+2*Cl⁻).composition))
    set_composition!(zinc_sulfate,CompositionRule((Zn²⁺+SO4²⁻).composition))
    set_composition!(sodium_acetate_anhydrous,CompositionRule((Na⁺+OAc⁻).composition))
    set_composition!(potassium_phosphate_di,CompositionRule((2*K⁺+HPO4²⁻).composition))
    set_composition!(potassium_phosphate_mono,CompositionRule((K⁺+H2PO4⁻).composition))
    set_composition!(ammonium_chloride,CompositionRule((NH4⁺+Cl⁻).composition))
    set_composition!(ammonium_nitrate,CompositionRule((NH4⁺+NO3⁻).composition))
    set_composition!(ammonium_sulfate,CompositionRule((2*NH4⁺+SO4²⁻).composition))
    # lysine is really L-Lysine monohydrochloride (Sigma/Thermo L5626, PubChem CID 69568) -- the
    # cation is already defined in pKa_data.jl as the acid/base chain's own protonated endpoint.
    set_composition!(lysine,CompositionRule((LysineCation+Cl⁻).composition))

    # hydrates -- waters of hydration included so derived molecular_weight still matches the stored value
    set_composition!(calcium_chloride,CompositionRule((Ca²⁺+2*Cl⁻+2*H2O).composition)) # dihydrate
    # cobalt_chloride/copper_chloride/copper_sulfate/potassium_aluminum_sulfate: fixed 2026-08-14 --
    # each was registered anhydrous, but its own stored density matched a hydrate's (not the
    # anhydrous form's) real density; see solids.jl for the per-reagent evidence.
    set_composition!(cobalt_chloride,CompositionRule((Co²⁺+2*Cl⁻+6*H2O).composition)) # hexahydrate
    set_composition!(copper_chloride,CompositionRule((Cu²⁺+2*Cl⁻+2*H2O).composition)) # dihydrate
    set_composition!(copper_sulfate,CompositionRule((Cu²⁺+SO4²⁻+5*H2O).composition)) # pentahydrate
    set_composition!(potassium_aluminum_sulfate,CompositionRule((K⁺+Al³⁺+2*SO4²⁻+12*H2O).composition)) # dodecahydrate
    # cobalt_nitrate/sodium_dichromate/sodium_molybdate/sodium_tungstate: fixed 2026-08-14 -- each was
    # registered anhydrous, corrected against the lab's actual purchase records (Reagent_StockList.xlsx:
    # Sigma 230375-100G "COBALT(II) NITRATE HEXAHYDRATE"; Sigma 398063-100G "Sodium dichromate
    # dihydrate"; catalog 243655-100G "Sodium molybdate dihydrate"; Sigma 223336-100G "SODIUM TUNGSTATE
    # DIHYDRATE"). See solids.jl for each reagent's density evidence.
    set_composition!(cobalt_nitrate,CompositionRule((Co²⁺+2*NO3⁻+6*H2O).composition)) # hexahydrate
    set_composition!(sodium_dichromate,CompositionRule((2*Na⁺+Cr2O7²⁻+2*H2O).composition)) # dihydrate
    set_composition!(sodium_molybdate,CompositionRule((2*Na⁺+MoO4²⁻+2*H2O).composition)) # dihydrate
    set_composition!(sodium_tungstate,CompositionRule((2*Na⁺+WO4²⁻+2*H2O).composition)) # dihydrate
    set_composition!(magnesium_sulfate,CompositionRule((Mg²⁺+SO4²⁻+7*H2O).composition)) # heptahydrate
    set_composition!(manganese_chloride,CompositionRule((Mn²⁺+2*Cl⁻+4*H2O).composition)) # tetrahydrate
    set_composition!(manganese_sulfate,CompositionRule((Mn²⁺+SO4²⁻+H2O).composition)) # monohydrate
    set_composition!(iron_sulfate,CompositionRule((Fe²⁺+SO4²⁻+7*H2O).composition)) # heptahydrate
    set_composition!(iron_nitrate,CompositionRule((Fe³⁺+3*NO3⁻+9*H2O).composition)) # nonahydrate
    set_composition!(sodium_acetate_trihydrate,CompositionRule((Na⁺+OAc⁻+3*H2O).composition))
    set_composition!(sodium_citrate_dihydrate,CompositionRule((3*Na⁺+Citrate³⁻+2*H2O).composition))
    set_composition!(sodium_phosphate_di,CompositionRule((2*Na⁺+HPO4²⁻+7*H2O).composition)) # heptahydrate
    set_composition!(sodium_phosphate_mono,CompositionRule((Na⁺+H2PO4⁻+H2O).composition)) # monohydrate
    set_composition!(sodium_succinate_hexahydrate,CompositionRule((2*Na⁺+C4H4O4²⁻+6*H2O).composition))
    # cysteine is really L-Cysteine hydrochloride monohydrate (Thermo Fisher BP376, PubChem CID
    # 23462) -- the cation is already defined in pKa_data.jl as the acid/base chain's own
    # protonated endpoint.
    set_composition!(cysteine,CompositionRule((CysteineCation+Cl⁻+H2O).composition))

    # Tetracycline family HCl salts -- their stored molecular_weight is the salt mass, not the free
    # base (confirmed by exact arithmetic; see pKa_data.jl's comment above their Chemical
    # definitions). Complete dissociation into the protonated tetracycline cation + Cl-, exactly like
    # the ammonium salts above; the cation's own further acid/base equilibrium is registered
    # separately via AcidBaseSystem in pKa_data.jl.
    set_composition!(tetracycline,CompositionRule((TetracyclineCation+Cl⁻).composition))
    set_composition!(doxycycline,CompositionRule((DoxycyclineCation+Cl⁻).composition))
    set_composition!(chlortetracycline,CompositionRule((ChlortetracyclineCation+Cl⁻).composition))
    set_composition!(minocycline,CompositionRule((MinocyclineCation+Cl⁻).composition))

    # pyruvate/butyrate/tartrate are real sodium salts, confirmed against the lab's actual stocklist
    # (Reagent_StockList.xlsx: Sigma P5280 "Pyruvic Acid Sodium", Sigma 303410 "Sodium butyrate",
    # catalog AAA1618730 "Sodium L-(+) Tartrate" dihydrate) -- not bare ions with no counter-ion.
    # ascorbate turned out to be the plain free acid (both stocklist catalog lines are "L-ASCORBIC
    # ACID"), so it needs no CompositionRule at all -- see its corrected molecular_weight/name in
    # solids.jl and its AcidBaseSystem registration in pKa_data.jl.
    set_composition!(sodium_pyruvate,CompositionRule((Na⁺+PyruvateAnion).composition))
    set_composition!(sodium_butyrate,CompositionRule((Na⁺+ButyrateAnion).composition))
    set_composition!(tartrate,CompositionRule((2*Na⁺+TartrateDianion+2*H2O).composition)) # dihydrate
    return nothing
end
