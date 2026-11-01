# Species identities for the ions that appear in this lab's electrolyte salts (see solids.jl's
# Dissolution definitions) and acid/base equilibria (see pKa_data.jl). Included before solids.jl
# so reagent definitions there can reference these constants directly.
#
# Each ion is defined by its elemental formula and charge; its molecular weight derives from atomic
# masses. The last argument of each `@species` is the PubChem ID of the ion.

# cations
@species Na⁺ "Na+" 1 "Na" 923
@species K⁺ "K+" 1 "K" 813
@species NH4⁺ "NH4+" 1 "NH4" 223
@species Ca²⁺ "Ca2+" 2 "Ca" 271
@species Mg²⁺ "Mg2+" 2 "Mg" 888
@species Fe²⁺ "Fe2+" 2 "Fe" 27284
@species Fe³⁺ "Fe3+" 3 "Fe" 29936
@species Co²⁺ "Co2+" 2 "Co" 104729
@species Cu²⁺ "Cu2+" 2 "Cu" 27099
@species Mn²⁺ "Mn2+" 2 "Mn" 27854
@species Ni²⁺ "Ni2+" 2 "Ni" 934
@species Zn²⁺ "Zn2+" 2 "Zn" 32051
@species Al³⁺ "Al3+" 3 "Al" 104727
@species Ag⁺ "Ag+" 1 "Ag" 104755
@species Sn²⁺ "Sn2+" 2 "Sn" 104883
@species Choline⁺ "Choline+" 1 "C5H14NO" 305

# anions
@species Cl⁻ "Cl-" -1 "Cl" 312
@species NO3⁻ "NO3-" -1 "NO3" 943
@species SO4²⁻ "SO4 2-" -2 "SO4" 1117
@species HSO4⁻ "HSO4-" -1 "HSO4" 61778
@species CO3²⁻ "CO3 2-" -2 "CO3" 19660
@species HCO3⁻ "HCO3-" -1 "HCO3" 769
@species Cr2O7²⁻ "Cr2O7 2-" -2 "Cr2O7" 24503
@species MoO4²⁻ "MoO4 2-" -2 "MoO4" 24621
@species SeO3²⁻ "SeO3 2-" -2 "SeO3" 1090
@species WO4²⁻ "WO4 2-" -2 "WO4" 24465
@species F⁻ "F-" -1 "F" 28179
@species HPO4²⁻ "HPO4 2-" -2 "HPO4" 3681305
@species H2PO4⁻ "H2PO4-" -1 "H2PO4" 1003
@species OAc⁻ "Acetate" -1 "C2H3O2" 175
@species C4H4O4²⁻ "Succinate" -2 "C4H4O4" 160419

# hydration water
@species H2O "H2O" 0 "H2O" 962

"""
    _register_ion_parameters!()

Register Truesdell-Jones (extended Debye-Hückel) ion-size (`å`, Ångströms) and empirical `b`
parameters for this lab's well-characterized inorganic ions -- see `CHESSCore.set_ion_parameters!`.
Values fetched directly from the raw `wateq4f.dat` PHREEQC thermodynamic database
(https://raw.githubusercontent.com/usgs-coupled/phreeqc3/master/database/wateq4f.dat, `-gamma å b`
lines in the `SOLUTION_SPECIES` block for each ion's own reaction), not estimated or guessed. The
species a reaction defines is the first one on its right-hand side (e.g. `H+ + PO4-3 = HPO4-2`
defines `HPO4-2`). Where `wateq4f.dat` and `phreeqc.dat` disagree (`PO4³⁻`: 5.0 vs 4.0 Å; `Zn²⁺`: 6.0
vs 5.0 Å) the `wateq4f.dat` value is used, for consistency with the rest of this set. The one value
not taken from `wateq4f.dat` is `NH4⁺`, which has no `-gamma` line there; it comes from `phreeqc.dat`
(the `NO3- + 10 H+ + 8 e- = NH4+ + 3 H2O` reaction, also `2.5 0` in `minteq.v4.dat`). Any ion not
registered here (every organic species, plus e.g. `Co²⁺`, `Ni²⁺`, which have no free-ion entry in
these databases) falls back to Davies (see `CHESSCore.activity_coefficient`'s docstring for that
limitation) rather than an invented value.
Wrapped in a function called from `__init__`, matching every other cross-package registration in this
package (see `_register_electrolyte_dissolutions!`/`_register_acid_base_systems!` for why this can't
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
    CHESSCore.set_ion_parameters!(PO4³⁻,5.0,0.0)    # wateq4f.dat (phreeqc.dat: 4.0 0)
    CHESSCore.set_ion_parameters!(HPO4²⁻,5.0,0.0)
    CHESSCore.set_ion_parameters!(H2PO4⁻,5.4,0.0)
    CHESSCore.set_ion_parameters!(HSO4⁻,4.5,0.0)    # wateq4f.dat only
    CHESSCore.set_ion_parameters!(F⁻,3.5,0.0)
    CHESSCore.set_ion_parameters!(Al³⁺,9.0,0.0)
    CHESSCore.set_ion_parameters!(Mn²⁺,6.0,0.0)
    CHESSCore.set_ion_parameters!(Cu²⁺,6.0,0.0)
    CHESSCore.set_ion_parameters!(Zn²⁺,6.0,0.0)    # wateq4f.dat (phreeqc.dat: 5.0 0)
    CHESSCore.set_ion_parameters!(NH4⁺,2.5,0.0)    # phreeqc.dat / minteq.v4.dat; no wateq4f.dat line
    return nothing
end
