# Real ionic dissociation chemistry for the metal-cation salts (plus HCl/NaOH and the ammonium salts)
# already defined in solids.jl. molecular_weight(::Reagent) derives its result from a reagent's
# registered CompositionRule once one exists (see CHESSCore/src/stocks/Chemicals.jl), overriding the
# stored value -- so hydrates register their waters of hydration as an explicit H2O product (they
# really are released into solution) to keep the derived weight matching the correct hydrate value,
# not silently dropping to the anhydrous one. Every rule below (hydrate or not) was hand-verified
# against the reagent's already-stored molecular weight before being added.
#
# Every ion's molecular weight was fetched from PubChem via register_chemical! (see chemical_utils.jl)
# -- the CID cited in each comment is what to pass register_chemical! to reproduce/refresh it.

# cations
@chemical Na⁺ "Na+" 1 22.9897693u"g/mol" # PubChem CID 923
@chemical K⁺ "K+" 1 39.0983u"g/mol" # PubChem CID 813
@chemical NH4⁺ "NH4+" 1 18.039u"g/mol" # PubChem CID 223
@chemical Ca²⁺ "Ca2+" 2 40.08u"g/mol" # PubChem CID 271
@chemical Mg²⁺ "Mg2+" 2 24.305u"g/mol" # PubChem CID 888
@chemical Fe²⁺ "Fe2+" 2 55.84u"g/mol" # PubChem CID 27284
@chemical Fe³⁺ "Fe3+" 3 55.84u"g/mol" # PubChem CID 29936
@chemical Co²⁺ "Co2+" 2 58.93319u"g/mol" # PubChem CID 104729
@chemical Cu²⁺ "Cu2+" 2 63.55u"g/mol" # PubChem CID 27099
@chemical Mn²⁺ "Mn2+" 2 54.93804u"g/mol" # PubChem CID 27854
@chemical Ni²⁺ "Ni2+" 2 58.693u"g/mol" # PubChem CID 934
@chemical Zn²⁺ "Zn2+" 2 65.4u"g/mol" # PubChem CID 32051
@chemical Al³⁺ "Al3+" 3 26.981538u"g/mol" # PubChem CID 104727
@chemical Ag⁺ "Ag+" 1 107.868u"g/mol" # PubChem CID 104755
@chemical Sn²⁺ "Sn2+" 2 118.71u"g/mol" # PubChem CID 104883

# anions
@chemical Cl⁻ "Cl-" -1 35.45u"g/mol" # PubChem CID 312
@chemical NO3⁻ "NO3-" -1 62.005u"g/mol" # PubChem CID 943
@chemical SO4²⁻ "SO4 2-" -2 96.07u"g/mol" # PubChem CID 1117
@chemical CO3²⁻ "CO3 2-" -2 60.009u"g/mol" # PubChem CID 19660
@chemical HCO3⁻ "HCO3-" -1 61.017u"g/mol" # PubChem CID 769
@chemical Cr2O7²⁻ "Cr2O7 2-" -2 215.99u"g/mol" # PubChem CID 24503
@chemical MoO4²⁻ "MoO4 2-" -2 159.95u"g/mol" # PubChem CID 24621
@chemical SeO3²⁻ "SeO3 2-" -2 126.97u"g/mol" # PubChem CID 1090
@chemical WO4²⁻ "WO4 2-" -2 247.84u"g/mol" # PubChem CID 24465
@chemical F⁻ "F-" -1 18.9984u"g/mol" # PubChem CID 28179
@chemical HPO4²⁻ "HPO4 2-" -2 95.979u"g/mol" # PubChem CID 3681305
@chemical H2PO4⁻ "H2PO4-" -1 96.987u"g/mol" # PubChem CID 1003
@chemical OAc⁻ "Acetate" -1 59.04u"g/mol" # PubChem CID 175
@chemical C4H4O4²⁻ "Succinate" -2 116.07u"g/mol" # PubChem CID 160419

# hydration water -- reuses `water`'s existing PubChem CID (962), already in liquids.jl
@chemical H2O "H2O" 0 18.015u"g/mol"

# set_composition! mutates CHESSCore's single global `composition_rules` Dict directly -- like
# occupancy_rules (see locations/occupancy_rules.jl), there is no per-module registry for it to survive
# precompilation through, so these calls are wrapped in a function invoked from CHESSLabConstants's own
# __init__ instead of running at top-level here.
function _register_dissociation_rules!()
    # anhydrous salts (no water-of-hydration term needed)
    set_composition!(HCl,CompositionRule(Dict(CHESSCore.H⁺=>1,Cl⁻=>1)))
    set_composition!(NaOH,CompositionRule(Dict(Na⁺=>1,CHESSCore.OH⁻=>1)))
    set_composition!(sodium_chloride,CompositionRule(Dict(Na⁺=>1,Cl⁻=>1)))
    set_composition!(cobalt_chloride,CompositionRule(Dict(Co²⁺=>1,Cl⁻=>2)))
    set_composition!(cobalt_nitrate,CompositionRule(Dict(Co²⁺=>1,NO3⁻=>2)))
    set_composition!(copper_chloride,CompositionRule(Dict(Cu²⁺=>1,Cl⁻=>2)))
    set_composition!(copper_sulfate,CompositionRule(Dict(Cu²⁺=>1,SO4²⁻=>1)))
    set_composition!(iron_chloride,CompositionRule(Dict(Fe³⁺=>1,Cl⁻=>3)))
    set_composition!(nickel_chloride,CompositionRule(Dict(Ni²⁺=>1,Cl⁻=>2)))
    set_composition!(potassium_aluminum_sulfate,CompositionRule(Dict(K⁺=>1,Al³⁺=>1,SO4²⁻=>2)))
    set_composition!(silver_nitrate,CompositionRule(Dict(Ag⁺=>1,NO3⁻=>1)))
    set_composition!(sodium_bicarbonate,CompositionRule(Dict(Na⁺=>1,HCO3⁻=>1)))
    set_composition!(sodium_carbonate,CompositionRule(Dict(Na⁺=>2,CO3²⁻=>1)))
    set_composition!(sodium_dichromate,CompositionRule(Dict(Na⁺=>2,Cr2O7²⁻=>1)))
    set_composition!(sodium_molybdate,CompositionRule(Dict(Na⁺=>2,MoO4²⁻=>1)))
    set_composition!(sodium_selenite,CompositionRule(Dict(Na⁺=>2,SeO3²⁻=>1)))
    set_composition!(sodium_tungstate,CompositionRule(Dict(Na⁺=>2,WO4²⁻=>1)))
    set_composition!(tin_fluoride,CompositionRule(Dict(Sn²⁺=>1,F⁻=>2)))
    set_composition!(zinc_chloride,CompositionRule(Dict(Zn²⁺=>1,Cl⁻=>2)))
    set_composition!(zinc_sulfate,CompositionRule(Dict(Zn²⁺=>1,SO4²⁻=>1)))
    set_composition!(sodium_acetate_anhydrous,CompositionRule(Dict(Na⁺=>1,OAc⁻=>1)))
    set_composition!(potassium_phosphate_di,CompositionRule(Dict(K⁺=>2,HPO4²⁻=>1)))
    set_composition!(potassium_phosphate_mono,CompositionRule(Dict(K⁺=>1,H2PO4⁻=>1)))
    set_composition!(ammonium_chloride,CompositionRule(Dict(NH4⁺=>1,Cl⁻=>1)))
    set_composition!(ammonium_nitrate,CompositionRule(Dict(NH4⁺=>1,NO3⁻=>1)))
    set_composition!(ammonium_sulfate,CompositionRule(Dict(NH4⁺=>2,SO4²⁻=>1)))

    # hydrates -- waters of hydration included so derived molecular_weight still matches the stored value
    set_composition!(calcium_chloride,CompositionRule(Dict(Ca²⁺=>1,Cl⁻=>2,H2O=>2))) # dihydrate
    set_composition!(magnesium_sulfate,CompositionRule(Dict(Mg²⁺=>1,SO4²⁻=>1,H2O=>7))) # heptahydrate
    set_composition!(manganese_chloride,CompositionRule(Dict(Mn²⁺=>1,Cl⁻=>2,H2O=>4))) # tetrahydrate
    set_composition!(manganese_sulfate,CompositionRule(Dict(Mn²⁺=>1,SO4²⁻=>1,H2O=>1))) # monohydrate
    set_composition!(iron_sulfate,CompositionRule(Dict(Fe²⁺=>1,SO4²⁻=>1,H2O=>7))) # heptahydrate
    set_composition!(iron_nitrate,CompositionRule(Dict(Fe³⁺=>1,NO3⁻=>3,H2O=>9))) # nonahydrate
    set_composition!(sodium_acetate_trihydrate,CompositionRule(Dict(Na⁺=>1,OAc⁻=>1,H2O=>3)))
    set_composition!(sodium_phosphate_di,CompositionRule(Dict(Na⁺=>2,HPO4²⁻=>1,H2O=>7))) # heptahydrate
    set_composition!(sodium_phosphate_mono,CompositionRule(Dict(Na⁺=>1,H2PO4⁻=>1,H2O=>1))) # monohydrate
    set_composition!(sodium_succinate_hexahydrate,CompositionRule(Dict(Na⁺=>2,C4H4O4²⁻=>1,H2O=>6)))
    return nothing
end
