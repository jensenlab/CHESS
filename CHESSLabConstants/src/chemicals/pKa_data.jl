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

# Tier-1 audit pass: amino acid endpoints. Each reagent's identity Chemical is the neutral zwitterion
# (matches stored MW in every case, verified) -- new endpoints are identity MW ± 1.008 g/mol per
# proton, chained outward. See the cluster comments in _register_acid_base_systems! below for each
# chain's shape/pKa citations.
@chemical AlanineCation "Alanine(cation)" 1 90.098u"g/mol"
@chemical AlanineAnion "Alanine(anion)" -1 88.082u"g/mol"
@chemical ValineCation "Valine(cation)" 1 118.158u"g/mol"
@chemical ValineAnion "Valine(anion)" -1 116.142u"g/mol"
@chemical LeucineCation "Leucine(cation)" 1 132.178u"g/mol"
@chemical LeucineAnion "Leucine(anion)" -1 130.162u"g/mol"
@chemical IsoleucineCation "Isoleucine(cation)" 1 132.178u"g/mol"
@chemical IsoleucineAnion "Isoleucine(anion)" -1 130.162u"g/mol"
@chemical GlycineCation "Glycine(cation)" 1 76.078u"g/mol"
@chemical GlycineAnion "Glycine(anion)" -1 74.062u"g/mol"
@chemical ProlineCation "Proline(cation)" 1 116.138u"g/mol"
@chemical ProlineAnion "Proline(anion)" -1 114.122u"g/mol"
@chemical SerineCation "Serine(cation)" 1 106.098u"g/mol"
@chemical SerineAnion "Serine(anion)" -1 104.082u"g/mol"
@chemical ThreonineCation "Threonine(cation)" 1 120.128u"g/mol"
@chemical ThreonineAnion "Threonine(anion)" -1 118.112u"g/mol"
@chemical MethionineCation "Methionine(cation)" 1 150.218u"g/mol"
@chemical MethionineAnion "Methionine(anion)" -1 148.202u"g/mol"
@chemical PhenylalanineCation "Phenylalanine(cation)" 1 166.198u"g/mol"
@chemical PhenylalanineAnion "Phenylalanine(anion)" -1 164.182u"g/mol"
@chemical TryptophanCation "Tryptophan(cation)" 1 205.228u"g/mol"
@chemical TryptophanAnion "Tryptophan(anion)" -1 203.212u"g/mol"
@chemical AsparagineCation "Asparagine(cation)" 1 133.128u"g/mol"
@chemical AsparagineAnion "Asparagine(anion)" -1 131.112u"g/mol"
@chemical GlutamineCation "Glutamine(cation)" 1 147.148u"g/mol"
@chemical GlutamineAnion "Glutamine(anion)" -1 145.132u"g/mol"
@chemical CitrulineCation "Citruline(cation)" 1 176.198u"g/mol"
@chemical CitrulineAnion "Citruline(anion)" -1 174.182u"g/mol"

@chemical HistidineDication "Histidine(dication)" 2 157.166u"g/mol" # imidazole side chain is basic, like lysine/arginine/ornithine's -- see the registration below
@chemical HistidineCation "Histidine(cation)" 1 156.158u"g/mol"
@chemical HistidineAnion "Histidine(anion)" -1 154.142u"g/mol"
@chemical CysteineCation "Cysteine(cation)" 1 122.168u"g/mol"
@chemical CysteineZwitterion "Cysteine(zwitterion)" 0 121.16u"g/mol" # the reagent itself is now the HCl monohydrate salt (see electrolytes.jl), not this state -- kept explicit for the chain
@chemical CysteineAnion "Cysteine(anion)" -1 120.152u"g/mol"
@chemical CysteineDianion "Cysteine(dianion)" -2 119.144u"g/mol"
@chemical TyrosineCation "Tyrosine(cation)" 1 182.198u"g/mol"
@chemical TyrosineAnion "Tyrosine(anion)" -1 180.182u"g/mol"
@chemical TyrosineDianion "Tyrosine(dianion)" -2 179.174u"g/mol"

@chemical LysineDication "Lysine(dication)" 2 148.206u"g/mol"
@chemical LysineCation "Lysine(cation)" 1 147.198u"g/mol"
@chemical LysineZwitterion "Lysine(zwitterion)" 0 146.19u"g/mol" # the reagent itself is now the HCl salt (see electrolytes.jl), not this state -- kept explicit for the chain
@chemical LysineAnion "Lysine(anion)" -1 145.182u"g/mol"
@chemical ArginineDication "Arginine(dication)" 2 176.216u"g/mol"
@chemical ArginineCation "Arginine(cation)" 1 175.208u"g/mol"
@chemical ArginineAnion "Arginine(anion)" -1 173.192u"g/mol"
@chemical OrnithineDication "Ornithine(dication)" 2 134.176u"g/mol"
@chemical OrnithineCation "Ornithine(cation)" 1 133.168u"g/mol"
@chemical OrnithineAnion "Ornithine(anion)" -1 131.152u"g/mol"

# cystine (cysteine's disulfide dimer, symmetric, no thiol) -- approximate macroscopic pKa's, see
# comment at its registration below.
@chemical CystineDication "Cystine(dication)" 2 242.316u"g/mol"
@chemical CystineCation "Cystine(cation)" 1 241.308u"g/mol"
@chemical CystineAnion "Cystine(anion)" -1 239.292u"g/mol"
@chemical CystineDianion "Cystine(dianion)" -2 238.284u"g/mol"

# Tier-1: common acids. pyruvate/butyrate/tartrate turned out to be real sodium salts (confirmed
# against the lab's actual stocklist, Reagent_StockList.xlsx -- see electrolytes.jl), so their
# reagent's own identity is charged (the anion/dianion), not neutral: `_identity(reagent)` always
# constructs charge 0 (matching composition()'s own default fallback), so it cannot be used for
# these three -- each instead gets an explicit, correctly-charged Chemical matching the stored MW
# exactly (their CompositionRule, registered in electrolytes.jl, adds the real Na+ counter-ion).
# ascorbate, by contrast, is the plain free acid (also confirmed against the stocklist -- both
# catalog lines there are "L-ASCORBIC ACID") once its stored name/MW/PubChem CID are corrected, so
# it uses the ordinary `_identity(ascorbate)` trick like citric_acid/lactic_acid, no CompositionRule.
@chemical EDTAAnion "EDTA(anion)" -1 291.232u"g/mol"
@chemical EDTADianion "EDTA(dianion)" -2 290.224u"g/mol"
@chemical EDTATrianion "EDTA(trianion)" -3 289.216u"g/mol"
@chemical EDTATetraanion "EDTA(tetraanion)" -4 288.208u"g/mol"
@chemical AscorbateAnion "Ascorbate(anion)" -1 175.12u"g/mol"
@chemical AscorbateDianion "Ascorbate(dianion)" -2 174.112u"g/mol"
@chemical PyruvicAcid "Pyruvic acid" 0 88.058u"g/mol" # neutral acid
@chemical PyruvateAnion "Pyruvate(anion)" -1 87.05u"g/mol" # == pyruvate's stored MW, now correctly charged
@chemical ButyricAcid "Butyric acid" 0 88.108u"g/mol" # neutral acid
@chemical ButyrateAnion "Butyrate(anion)" -1 87.1u"g/mol" # == butyrate's stored MW, now correctly charged
@chemical TartaricAcid "Tartaric acid" 0 150.086u"g/mol" # neutral diacid
@chemical TartrateMonoanion "Tartrate(monoanion)" -1 149.078u"g/mol"
@chemical TartrateDianion "Tartrate(dianion)" -2 148.07u"g/mol" # == tartrate's stored MW, now correctly charged
@chemical BiotinAnion "Biotin(anion)" -1 243.302u"g/mol"
@chemical LipoateAnion "Lipoate(anion)" -1 205.292u"g/mol"

# Tier-1: antibiotics. Sulfonamides/fluoroquinolones/most penicillins reuse the identity trick
# (neutral zwitterion or free acid, matches stored MW) exactly like the amino acids/organic acids
# above. The tetracycline family is the exception: their stored molecular_weight is the *HCl salt*
# mass (confirmed by exact arithmetic, e.g. tetracycline free base 444.43 + HCl 36.46 = 480.89 ≈
# stored 480.9 -- true even for chlortetracycline/doxycycline, whose display names don't say
# "hydrochloride" but whose masses confirm it), so none of their chain states reuse the reagent's own
# identity at all -- see their CompositionRule registration in electrolytes.jl and the fresh
# free-base-derived Chemicals below.
@chemical SulfadiazineCation "Sulfadiazine(cation)" 1 251.288u"g/mol"
@chemical SulfadiazineAnion "Sulfadiazine(anion)" -1 249.272u"g/mol"
@chemical SulfamethazineCation "Sulfamethazine(cation)" 1 279.338u"g/mol"
@chemical SulfamethazineAnion "Sulfamethazine(anion)" -1 277.322u"g/mol"
@chemical SulfathiazoleCation "Sulfathiazole(cation)" 1 256.308u"g/mol"
@chemical SulfathiazoleAnion "Sulfathiazole(anion)" -1 254.292u"g/mol"
@chemical CiprofloxacinCation "Ciprofloxacin(cation)" 1 332.348u"g/mol"
@chemical CiprofloxacinAnion "Ciprofloxacin(anion)" -1 330.332u"g/mol"
@chemical OfloxacinCation "Ofloxacin(cation)" 1 362.408u"g/mol"
@chemical OfloxacinAnion "Ofloxacin(anion)" -1 360.392u"g/mol"
@chemical PenicillinGAnion "PenicillinG(anion)" -1 333.392u"g/mol"
@chemical AmpicillinCation "Ampicillin(cation)" 1 350.408u"g/mol"
@chemical AmpicillinAnion "Ampicillin(anion)" -1 348.392u"g/mol"
@chemical AmoxicillinCation "Amoxicillin(cation)" 1 366.408u"g/mol"
@chemical AmoxicillinAnion "Amoxicillin(anion)" -1 364.392u"g/mol"
@chemical AmoxicillinDianion "Amoxicillin(dianion)" -2 363.384u"g/mol"
@chemical CarbenicillinAnion "Carbenicillin(anion)" -1 377.392u"g/mol"
@chemical OxacillinAnion "Oxacillin(anion)" -1 400.392u"g/mol"

# Tetracycline family (free-base MW anchors, not the reagents' own stored HCl-salt MW): tetracycline
# and doxycycline share the same molecular formula (444.43 g/mol free base); chlortetracycline is
# 478.89 (its own chlorine substituent, separate from the HCl salt's counter-ion); minocycline is
# 457.48. Each gets its own 4-state cation/zwitterion/anion/dianion chain.
@chemical TetracyclineCation "Tetracycline(cation)" 1 445.438u"g/mol"
@chemical TetracyclineZwitterion "Tetracycline(zwitterion)" 0 444.430u"g/mol"
@chemical TetracyclineAnion "Tetracycline(anion)" -1 443.422u"g/mol"
@chemical TetracyclineDianion "Tetracycline(dianion)" -2 442.414u"g/mol"
@chemical DoxycyclineCation "Doxycycline(cation)" 1 445.438u"g/mol"
@chemical DoxycyclineZwitterion "Doxycycline(zwitterion)" 0 444.430u"g/mol"
@chemical DoxycyclineAnion "Doxycycline(anion)" -1 443.422u"g/mol"
@chemical DoxycyclineDianion "Doxycycline(dianion)" -2 442.414u"g/mol"
@chemical ChlortetracyclineCation "Chlortetracycline(cation)" 1 479.898u"g/mol"
@chemical ChlortetracyclineZwitterion "Chlortetracycline(zwitterion)" 0 478.890u"g/mol"
@chemical ChlortetracyclineAnion "Chlortetracycline(anion)" -1 477.882u"g/mol"
@chemical ChlortetracyclineDianion "Chlortetracycline(dianion)" -2 476.874u"g/mol"
@chemical MinocyclineCation "Minocycline(cation)" 1 458.488u"g/mol"
@chemical MinocyclineZwitterion "Minocycline(zwitterion)" 0 457.480u"g/mol"
@chemical MinocyclineAnion "Minocycline(anion)" -1 456.472u"g/mol"
@chemical MinocyclineDianion "Minocycline(dianion)" -2 455.464u"g/mol"

@chemical CycloserineCation "Cycloserine(cation)" 1 103.098u"g/mol"
@chemical CycloserineAnion "Cycloserine(anion)" -1 101.082u"g/mol"
@chemical ErythromycinCation "Erythromycin(cation)" 1 734.908u"g/mol"
@chemical LincomycinCation "Lincomycin(cation)" 1 407.508u"g/mol"

# Tier-1: miscellaneous simple bases.
@chemical PromethazineCation "Promethazine(cation)" 1 285.408u"g/mol"
@chemical CarnitineCation "Carnitine(cation)" 1 162.208u"g/mol" # the quaternary N is permanently +1; only the carboxyl equilibrates
@chemical TaurineAnion "Taurine(anion)" -1 124.142u"g/mol" # sulfonate stays fully deprotonated, MOPS-style; only the amine equilibrates
@chemical AgmatineDication "Agmatine(dication)" 2 132.206u"g/mol"
@chemical AgmatineCation "Agmatine(cation)" 1 131.198u"g/mol"
@chemical AmitroleCation "Amitrole(cation)" 1 85.088u"g/mol"
@chemical BenzamidineCation "Benzamidine(cation)" 1 121.158u"g/mol"
@chemical GuanidineCation "Guanidine(cation)" 1 60.078u"g/mol"

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
    # partial acid equilibrium. Registered against the sodium acetate salts too (shared AcidBaseSystem
    # instance, same pattern as the phosphate/carbonate families) -- without this, OAc⁻ contributed by
    # sodium_acetate_anhydrous/trihydrate was wrongly treated as an inert strong ion instead of the
    # genuine weak base it is (found while diagnosing a real reported pH discrepancy).
    acetic_acid_system = AcidBaseSystem([_identity(acetic_acid),OAc⁻],[4.76])
    set_acid_base_system!(acetic_acid,acetic_acid_system)
    set_acid_base_system!(sodium_acetate_anhydrous,acetic_acid_system)
    set_acid_base_system!(sodium_acetate_trihydrate,acetic_acid_system)
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

    # --- Tier-1 audit pass -------------------------------------------------------------------

    # Cluster A: amino acids. Simple pair (alpha-COOH, alpha-NH3+), chain [cation,identity,anion]:
    set_acid_base_system!(alanine,AcidBaseSystem([AlanineCation,_identity(alanine),AlanineAnion],[2.34,9.69]))
    set_acid_base_system!(valine,AcidBaseSystem([ValineCation,_identity(valine),ValineAnion],[2.32,9.62]))
    set_acid_base_system!(leucine,AcidBaseSystem([LeucineCation,_identity(leucine),LeucineAnion],[2.36,9.60]))
    set_acid_base_system!(isoleucine,AcidBaseSystem([IsoleucineCation,_identity(isoleucine),IsoleucineAnion],[2.36,9.68]))
    set_acid_base_system!(glycine,AcidBaseSystem([GlycineCation,_identity(glycine),GlycineAnion],[2.34,9.60]))
    set_acid_base_system!(proline,AcidBaseSystem([ProlineCation,_identity(proline),ProlineAnion],[1.99,10.60]))
    set_acid_base_system!(serine,AcidBaseSystem([SerineCation,_identity(serine),SerineAnion],[2.21,9.15]))
    set_acid_base_system!(threonine,AcidBaseSystem([ThreonineCation,_identity(threonine),ThreonineAnion],[2.09,9.10]))
    set_acid_base_system!(methionine,AcidBaseSystem([MethionineCation,_identity(methionine),MethionineAnion],[2.28,9.21]))
    set_acid_base_system!(phenylalanine,AcidBaseSystem([PhenylalanineCation,_identity(phenylalanine),PhenylalanineAnion],[1.83,9.13]))
    set_acid_base_system!(tryptophan,AcidBaseSystem([TryptophanCation,_identity(tryptophan),TryptophanAnion],[2.38,9.39]))
    set_acid_base_system!(asparagine,AcidBaseSystem([AsparagineCation,_identity(asparagine),AsparagineAnion],[2.02,8.80]))
    set_acid_base_system!(glutamine,AcidBaseSystem([GlutamineCation,_identity(glutamine),GlutamineAnion],[2.17,9.13]))
    set_acid_base_system!(citruline,AcidBaseSystem([CitrulineCation,_identity(citruline),CitrulineAnion],[2.43,9.41]))

    # extra acidic/neutral side-chain group -- chain [cation,identity,anion,dianion]:
    # cysteine's reagent identity is now the HCl monohydrate salt (see electrolytes.jl), not the
    # zwitterion, so the zwitterion state uses its own explicit Chemical rather than _identity
    set_acid_base_system!(cysteine,AcidBaseSystem(
        [CysteineCation,CysteineZwitterion,CysteineAnion,CysteineDianion],[1.96,8.3,10.28]))
    set_acid_base_system!(tyrosine,AcidBaseSystem(
        [TyrosineCation,_identity(tyrosine),TyrosineAnion,TyrosineDianion],[2.2,9.11,10.07]))

    # extra basic side-chain group -- chain [dication,cation,identity,anion]:
    # histidine's imidazole side chain is basic (protonated imidazolium at low pH, like an amine),
    # not acidic -- it belongs here, not in the "extra acidic" group above. pKa2 (imidazole) is
    # physiologically important, sitting right in typical media pH.
    set_acid_base_system!(histidine,AcidBaseSystem(
        [HistidineDication,HistidineCation,_identity(histidine),HistidineAnion],[1.80,6.04,9.33]))
    # lysine's reagent identity is now the HCl salt (see electrolytes.jl), not the zwitterion, so
    # the zwitterion state uses its own explicit Chemical rather than _identity
    set_acid_base_system!(lysine,AcidBaseSystem(
        [LysineDication,LysineCation,LysineZwitterion,LysineAnion],[2.18,8.95,10.5]))
    set_acid_base_system!(arginine,AcidBaseSystem(
        [ArginineDication,ArginineCation,_identity(arginine),ArginineAnion],[2.17,9.04,12.48]))
    set_acid_base_system!(ornithine,AcidBaseSystem(
        [OrnithineDication,OrnithineCation,_identity(ornithine),OrnithineAnion],[1.94,8.65,10.76]))

    # cystine (cysteine's disulfide dimer, symmetric, no thiol) -- approximate macroscopic pKa's,
    # lower-confidence than the values above (the true microscopic picture is more complex due to the
    # molecule's symmetry), same treatment as shikimic_acid/alpha_ketoglutaric_acid.
    set_acid_base_system!(cystine,AcidBaseSystem(
        [CystineDication,CystineCation,_identity(cystine),CystineAnion,CystineDianion],[1.0,2.1,7.9,9.9]))

    # Cluster B: common acids.
    # EDTA: 4 of its 6 ionizable protons (2 carboxyls + 2 amines) are well-established/commonly
    # tabulated; the remaining 2 carboxyl pKa's are very low and not well-resolved/agreed upon in the
    # literature, so this is a documented simplification (same spirit as boric acid's).
    set_acid_base_system!(edta,AcidBaseSystem(
        [_identity(edta),EDTAAnion,EDTADianion,EDTATrianion,EDTATetraanion],[2.0,2.68,6.11,10.17]))
    # ascorbate is the plain free acid (identity = neutral, matches composition()'s default):
    set_acid_base_system!(ascorbate,AcidBaseSystem([_identity(ascorbate),AscorbateAnion,AscorbateDianion],[4.1,11.6]))
    # pyruvate/butyrate/tartrate: identity is a real, charged salt component (see the Chemical
    # definitions' comment above) -- chains are built around that fact, not the assumption that
    # identity is the neutral acid.
    set_acid_base_system!(sodium_pyruvate,AcidBaseSystem([PyruvicAcid,PyruvateAnion],[2.5]))
    set_acid_base_system!(sodium_butyrate,AcidBaseSystem([ButyricAcid,ButyrateAnion],[4.82]))
    set_acid_base_system!(tartrate,AcidBaseSystem([TartaricAcid,TartrateMonoanion,TartrateDianion],[3.0,4.4]))
    set_acid_base_system!(biotin,AcidBaseSystem([_identity(biotin),BiotinAnion],[4.5]))
    # literature range ≈4.7-5.4; representative value, not a single universally-agreed constant.
    set_acid_base_system!(lipoic_acid,AcidBaseSystem([_identity(lipoic_acid),LipoateAnion],[4.8]))

    # Cluster C: antibiotics.
    # Sulfonamides (aniline-type amine + acidic sulfonamide N-H, same family as paba):
    set_acid_base_system!(sulfadiazine,AcidBaseSystem([SulfadiazineCation,_identity(sulfadiazine),SulfadiazineAnion],[1.6,6.5]))
    set_acid_base_system!(sulfamethazine,AcidBaseSystem([SulfamethazineCation,_identity(sulfamethazine),SulfamethazineAnion],[2.3,7.4]))
    set_acid_base_system!(sulfathiazole,AcidBaseSystem([SulfathiazoleCation,_identity(sulfathiazole),SulfathiazoleAnion],[2.1,7.2]))
    # Fluoroquinolones (carboxyl + piperazine amine zwitterions):
    set_acid_base_system!(ciprofloxacin,AcidBaseSystem([CiprofloxacinCation,_identity(ciprofloxacin),CiprofloxacinAnion],[6.1,8.7]))
    set_acid_base_system!(ofloxacin,AcidBaseSystem([OfloxacinCation,_identity(ofloxacin),OfloxacinAnion],[6.1,8.7])) # representative, same class as ciprofloxacin
    # Penicillins:
    set_acid_base_system!(penicillin_g,AcidBaseSystem([_identity(penicillin_g),PenicillinGAnion],[2.75]))
    set_acid_base_system!(ampicillin,AcidBaseSystem([AmpicillinCation,_identity(ampicillin),AmpicillinAnion],[2.5,7.3]))
    set_acid_base_system!(amoxicillin,AcidBaseSystem([AmoxicillinCation,_identity(amoxicillin),AmoxicillinAnion,AmoxicillinDianion],[2.4,7.4,9.6]))
    # carbenicillin/oxacillin each technically have a second, less-relevant ionizable group; simplified
    # to a single representative carboxyl pKa here, same spirit as boric_acid/shikimic_acid.
    set_acid_base_system!(carbenicillin,AcidBaseSystem([_identity(carbenicillin),CarbenicillinAnion],[2.6]))
    set_acid_base_system!(oxacillin,AcidBaseSystem([_identity(oxacillin),OxacillinAnion],[2.7]))
    # Tetracyclines: stored molecular_weight is the HCl salt mass (see Chemical comment above), so
    # none of these 4 chain states reuse the reagent's own identity -- their CompositionRule
    # (salt -> cation + Cl-) is registered in electrolytes.jl instead. Representative 3-pKa triad
    # (real values vary slightly by derivative).
    tetracycline_pKa = [3.3,7.7,9.7]
    set_acid_base_system!(tetracycline,AcidBaseSystem(
        [TetracyclineCation,TetracyclineZwitterion,TetracyclineAnion,TetracyclineDianion],tetracycline_pKa))
    set_acid_base_system!(doxycycline,AcidBaseSystem(
        [DoxycyclineCation,DoxycyclineZwitterion,DoxycyclineAnion,DoxycyclineDianion],tetracycline_pKa))
    set_acid_base_system!(chlortetracycline,AcidBaseSystem(
        [ChlortetracyclineCation,ChlortetracyclineZwitterion,ChlortetracyclineAnion,ChlortetracyclineDianion],tetracycline_pKa))
    set_acid_base_system!(minocycline,AcidBaseSystem(
        [MinocyclineCation,MinocyclineZwitterion,MinocyclineAnion,MinocyclineDianion],tetracycline_pKa))
    # amino-acid-analog zwitterion:
    set_acid_base_system!(cycloserine,AcidBaseSystem([CycloserineCation,_identity(cycloserine),CycloserineAnion],[4.5,7.4]))
    # simple monoprotic bases (no acid group at all):
    set_acid_base_system!(erythromycin,AcidBaseSystem([ErythromycinCation,_identity(erythromycin)],[8.8]))
    set_acid_base_system!(lincomycin,AcidBaseSystem([LincomycinCation,_identity(lincomycin)],[7.6]))

    # Cluster D: miscellaneous simple bases.
    set_acid_base_system!(promethazine,AcidBaseSystem([PromethazineCation,_identity(promethazine)],[9.1]))
    set_acid_base_system!(carnitine,AcidBaseSystem([CarnitineCation,_identity(carnitine)],[3.8]))
    set_acid_base_system!(taurine,AcidBaseSystem([_identity(taurine),TaurineAnion],[9.06]))
    set_acid_base_system!(agmatine,AcidBaseSystem([AgmatineDication,AgmatineCation,_identity(agmatine)],[9.4,12.5]))
    set_acid_base_system!(amitrole,AcidBaseSystem([AmitroleCation,_identity(amitrole)],[4.2]))
    set_acid_base_system!(benzamadine,AcidBaseSystem([BenzamidineCation,_identity(benzamadine)],[11.6]))
    set_acid_base_system!(guanidine,AcidBaseSystem([GuanidineCation,_identity(guanidine)],[13.6]))

    return nothing
end
