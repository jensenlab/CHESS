# Chemical identities for the ions that appear in this lab's electrolyte salts (see solids.jl's
# @reagent_formula definitions) and acid/base equilibria (see pKa_data.jl). Included before solids.jl
# so those `@reagent_formula` calls can reference these constants directly.
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

"""
    _register_ion_parameters!()

Register Truesdell-Jones (extended Debye-Hückel) ion-size (`å`, Ångströms) and empirical `b`
parameters for this lab's well-characterized inorganic ions -- see `CHESSCore.set_ion_parameters!`.
Values fetched directly from the raw `wateq4f.dat` PHREEQC thermodynamic database
(https://raw.githubusercontent.com/usgs-coupled/phreeqc3/master/database/wateq4f.dat, `-gamma å b`
lines in the `SOLUTION_SPECIES` block for each ion's own reaction), not estimated or guessed. Any ion
not registered here (e.g. `NH4⁺`, which has no `-gamma` line in that database) falls back to Davies
(see `CHESSCore.activity_coefficient`'s docstring for that limitation) rather than an invented value.
Wrapped in a function called from `__init__`, matching every other cross-package registration in this
package (see `_register_electrolyte_compositions!`/`_register_acid_base_systems!` for why this can't
run at plain top-level include time).
"""
function _register_ion_parameters!()
    CHESSCore.set_ion_parameters!(Na⁺,4.0,0.075)
    CHESSCore.set_ion_parameters!(K⁺,3.5,0.015)
    CHESSCore.set_ion_parameters!(Ca²⁺,5.0,0.165)
    CHESSCore.set_ion_parameters!(Mg²⁺,5.5,0.2)
    CHESSCore.set_ion_parameters!(Fe²⁺,6.0,0.0)
    CHESSCore.set_ion_parameters!(Fe³⁺,9.0,0.0)
    CHESSCore.set_ion_parameters!(Cl⁻,3.5,0.015)
    CHESSCore.set_ion_parameters!(NO3⁻,3.0,0.0)
    CHESSCore.set_ion_parameters!(SO4²⁻,5.0,-0.04)
    CHESSCore.set_ion_parameters!(CO3²⁻,5.4,0.0)
    CHESSCore.set_ion_parameters!(HCO3⁻,5.4,0.0)
    return nothing
end
