# Acid/base equilibrium (AcidBaseSystem) data -- registers weak acid/base families against reagents
# already defined in solids.jl. Independent of (and additional to) those reagents' CompositionRules
# in electrolytes.jl, which continue to answer the separate question of complete-dissociation mass
# bookkeeping; this file answers "how does this reagent's dissolved chemistry actually speciate as a
# function of pH." See CHESSCore/src/stocks/AcidBase.jl for the AcidBaseSystem type and solver.
#
# pKa values are thermodynamic (25°C, infinite-dilution) constants -- ionic strength corrections are
# applied at solve time (see CHESSCore.activity_coefficient), not baked in here. Sourced from the CRC
# Handbook of Chemistry and Physics (acid dissociation constants table) unless noted otherwise.
#
# Like electrolytes.jl's set_composition! calls, these set_acid_base_system! calls are wrapped in a
# function invoked from CHESSLabConstants's own __init__ rather than running at top-level here, for
# the same precompilation-safety reason (acid_base_systems is a global Dict owned by CHESSCore).

# New Chemical endpoints not already defined in ions.jl (H2PO4⁻/HPO4²⁻/HCO3⁻/CO3²⁻ already exist there)
@chemical H3PO4 "H3PO4" 0 97.994u"g/mol" # PubChem CID 1004
@chemical PO4³⁻ "PO4 3-" -3 94.971u"g/mol" # PubChem CID 1061
@chemical H2CO3 "H2CO3" 0 62.025u"g/mol" # PubChem CID 767

# Organic acid conjugate-base endpoints. Each acid's fully-protonated (neutral, as-weighed) reference
# state deliberately reuses `name(reagent)`/`molecular_weight(reagent)` exactly -- this makes it
# identical (by Chemical's value equality) to the identity Chemical composition(::Reagent)'s default
# fallback already produces for a reagent with no registered CompositionRule, so none of these acids
# need a CompositionRule registration of their own: `recipe()` already reports their moles under
# exactly the Chemical that appears as a species in their AcidBaseSystem below.
@chemical Citrate³⁻ "Citrate3-" -3 187.09u"g/mol"
@chemical HCitrate²⁻ "HCitrate2-" -2 188.09u"g/mol"
@chemical H2Citrate⁻ "H2Citrate-" -1 189.10u"g/mol"
@chemical Lactate⁻ "Lactate-" -1 89.07u"g/mol" # PubChem CID 107689 (distinct from the "Lactic Acid" reagent's own PubChem entry)
@chemical Oxalate²⁻ "Oxalate2-" -2 88.02u"g/mol" # PubChem CID 971 shares parent; ion CID 71081
@chemical HOxalate⁻ "HOxalate-" -1 89.02u"g/mol"
@chemical Formate⁻ "Formate-" -1 45.02u"g/mol" # PubChem CID 283
@chemical Malate²⁻ "Malate2-" -2 132.08u"g/mol" # PubChem CID 222656
@chemical HMalate⁻ "HMalate-" -1 133.08u"g/mol"
@chemical Tetrahydroxyborate⁻ "B(OH)4-" -1 78.84u"g/mol" # B(OH)3 + H2O - H+
@chemical Propionate⁻ "Propionate-" -1 73.07u"g/mol" # PubChem CID 104745
@chemical Shikimate⁻ "Shikimate-" -1 173.14u"g/mol"
@chemical HAlphaKetoglutarate⁻ "HAlphaKetoglutarate-" -1 145.09u"g/mol"
@chemical AlphaKetoglutarate²⁻ "AlphaKetoglutarate2-" -2 144.08u"g/mol" # PubChem CID 51 shares parent; ion CID 51056

# Zwitterion endpoints (amino acids: aspartic_acid, glutamic_acid; and PABA, a weakly basic aromatic
# amine + carboxylic acid). The reagent's own stored/derived molecular_weight is the *neutral* form in
# every case (the species actually weighed out) -- consistent with the trick above, that neutral state
# is one of AcidBaseSystem's own `species` entries (not necessarily `species[1]`, since the
# fully-protonated *cation* carries a real net charge here), so again no CompositionRule registration
# is needed.
@chemical AspartateCation "Aspartate(cation)" 1 134.11u"g/mol" # L-aspartic acid + H+
@chemical AspartateAnion "Aspartate(anion)" -1 132.09u"g/mol" # L-aspartic acid - H+
@chemical AspartateDianion "Aspartate(dianion)" -2 131.08u"g/mol"
@chemical GlutamateCation "Glutamate(cation)" 1 148.14u"g/mol" # L-glutamic acid + H+
@chemical GlutamateAnion "Glutamate(anion)" -1 146.12u"g/mol" # L-glutamic acid - H+
@chemical GlutamateDianion "Glutamate(dianion)" -2 145.11u"g/mol"
@chemical PABACation "PABA(cation)" 1 138.15u"g/mol" # 4-aminobenzoic acid + H+ (protonated anilinium)
@chemical PABAAnion "PABA(anion)" -1 136.13u"g/mol" # 4-aminobenzoic acid - H+ (deprotonated COOH)

# MOPS (a Good's buffer) is weighed out as its zwitterion (protonated morpholinium + sulfonate, net
# charge 0 -- the reagent's own default identity, same trick as above). Its sulfonic acid group is a
# strong acid (pKa ≈ -1) and is always fully deprotonated in any realistic aqueous solution, so it's
# not modeled as an equilibrium step at all (same reasoning as HCl/NaOH staying CompositionRule-only) --
# only the morpholinium's own deprotonation (pKa ≈ 7.20, 25°C) is registered.
@chemical MOPS⁻ "MOPS-" -1 208.25u"g/mol" # PubChem CID 70807 shares parent; deprotonated morpholine

function _register_acid_base_systems!()
    # Phosphoric acid family: H3PO4 ⇌ H2PO4⁻ ⇌ HPO4²⁻ ⇌ PO4³⁻ -- pKa1/pKa2/pKa3 = 2.148/7.198/12.375
    # (CRC Handbook, 25°C). Shared across all four phosphate salts -- same conjugate family regardless
    # of counter-ion (K⁺ vs Na⁺, already handled by each reagent's own CompositionRule).
    phosphoric_acid_system = AcidBaseSystem([H3PO4,H2PO4⁻,HPO4²⁻,PO4³⁻],[2.148,7.198,12.375])
    set_acid_base_system!(potassium_phosphate_mono,phosphoric_acid_system)
    set_acid_base_system!(potassium_phosphate_di,phosphoric_acid_system)
    set_acid_base_system!(sodium_phosphate_mono,phosphoric_acid_system)
    set_acid_base_system!(sodium_phosphate_di,phosphoric_acid_system)

    # Carbonic acid family: H2CO3 ⇌ HCO3⁻ ⇌ CO3²⁻ -- pKa1/pKa2 = 6.352/10.329 (CRC Handbook, 25°C).
    # pKa1 here is the *apparent* constant that folds in dissolved CO2(aq)/H2CO3 partitioning (the
    # true H2CO3-only pKa is much lower, ~3.6, but essentially all "H2CO3" in aqueous solution is
    # actually dissolved CO2 -- the apparent constant is what's practically relevant and is the
    # standard convention used here).
    carbonic_acid_system = AcidBaseSystem([H2CO3,HCO3⁻,CO3²⁻],[6.352,10.329])
    set_acid_base_system!(sodium_bicarbonate,carbonic_acid_system)
    set_acid_base_system!(sodium_carbonate,carbonic_acid_system)

    # Organic acids -- each fully-protonated (neutral) reference state is built from the reagent's own
    # name/molecular_weight, so it's `==` to what composition(reagent) already returns by default (see
    # the comment above the Chemical definitions).
    _identity(r::Reagent) = CHESSCore.Chemical(name(r),0,molecular_weight(r))

    set_acid_base_system!(citric_acid,AcidBaseSystem(
        [_identity(citric_acid),H2Citrate⁻,HCitrate²⁻,Citrate³⁻],[3.13,4.76,6.40]))
    set_acid_base_system!(lactic_acid,AcidBaseSystem(
        [_identity(lactic_acid),Lactate⁻],[3.86]))
    set_acid_base_system!(oxalic_acid,AcidBaseSystem(
        [_identity(oxalic_acid),HOxalate⁻,Oxalate²⁻],[1.25,4.14]))
    set_acid_base_system!(formic_acid,AcidBaseSystem(
        [_identity(formic_acid),Formate⁻],[3.75]))
    set_acid_base_system!(malic_acid,AcidBaseSystem(
        [_identity(malic_acid),HMalate⁻,Malate²⁻],[3.40,5.20]))
    # boric acid's mechanism is actually Lewis-acid hydroxide addition (B(OH)3 + H2O ⇌ B(OH)4⁻ + H+),
    # not proton donation -- conventionally modeled with an apparent pKa, as here.
    set_acid_base_system!(boric_acid,AcidBaseSystem(
        [_identity(boric_acid),Tetrahydroxyborate⁻],[9.24]))
    set_acid_base_system!(propionic_acid,AcidBaseSystem(
        [_identity(propionic_acid),Propionate⁻],[4.87]))
    # reuses the existing OAc⁻ ion constant (ions.jl) already shared with the sodium acetate salts'
    # CompositionRules -- same conjugate species, whether reached via complete salt dissociation or
    # partial acid equilibrium.
    set_acid_base_system!(acetic_acid,AcidBaseSystem(
        [_identity(acetic_acid),OAc⁻],[4.76]))
    # shikimic acid has 3 hydroxyls in addition to its one carboxylic acid group; only the carboxylic
    # acid is significantly acidic in the physiological/lab pH range modeled here. pKa is a
    # commonly-cited predicted value (ACD/Labs-style estimate, ~4.15) rather than a directly measured
    # CRC Handbook entry -- flagged here as lower-confidence than the CRC-sourced values above.
    set_acid_base_system!(shikimic_acid,AcidBaseSystem(
        [_identity(shikimic_acid),Shikimate⁻],[4.15]))
    # alpha-ketoglutaric (2-oxoglutaric) acid: literature pKa1 varies somewhat across sources
    # (roughly 1.8-2.5) due to the adjacent keto group; values here are representative, not a single
    # universally-agreed constant.
    set_acid_base_system!(alpha_ketoglutaric_acid,AcidBaseSystem(
        [_identity(alpha_ketoglutaric_acid),HAlphaKetoglutarate⁻,AlphaKetoglutarate²⁻],[1.85,4.68]))

    # Zwitterions: aspartic_acid/glutamic_acid (amino acids -- carboxylic + carboxylic + amine pKa's)
    # and paba (carboxylic + weakly basic aromatic amine pKa). Each chain runs
    # cation -> [reagent's own neutral identity, wherever it falls] -> ... -> most-deprotonated anion;
    # AcidBaseSystem's linear-chain shape needs no special-casing for this (see its docstring) -- only
    # the extra pKa data was needed, per the earlier scoping discussion. folic_acid/fusidic_acid remain
    # deliberately unregistered: their literature pKa's are more complex/uncertain (multiple
    # overlapping functional groups without a clean consensus value) -- a documented scope boundary,
    # not an oversight.
    set_acid_base_system!(aspartic_acid,AcidBaseSystem(
        [AspartateCation,_identity(aspartic_acid),AspartateAnion,AspartateDianion],[1.99,3.90,9.90]))
    set_acid_base_system!(glutamic_acid,AcidBaseSystem(
        [GlutamateCation,_identity(glutamic_acid),GlutamateAnion,GlutamateDianion],[2.19,4.25,9.67]))
    set_acid_base_system!(paba,AcidBaseSystem(
        [PABACation,_identity(paba),PABAAnion],[2.5,4.85]))

    set_acid_base_system!(mops,AcidBaseSystem([_identity(mops),MOPS⁻],[7.20]))
    return nothing
end
