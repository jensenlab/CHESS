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

# New Species endpoints not already defined in ions.jl (H2PO4⁻/HPO4²⁻/HCO3⁻/CO3²⁻ already exist there)
@species H3PO4 "H3PO4" 0 97.994u"g/mol" # PubChem CID 1004
@species PO4³⁻ "PO4 3-" -3 94.971u"g/mol" # PubChem CID 1061
@species H2CO3 "H2CO3" 0 62.025u"g/mol" # PubChem CID 767

# Organic acid conjugate-base endpoints. Each acid's fully-protonated (neutral, as-weighed) reference
# state deliberately reuses `name(reagent)`/`molecular_weight(reagent)` exactly -- this makes it
# identical (by Species's value equality) to the identity Species composition(::Reagent)'s default
# fallback already produces for a reagent with no registered CompositionRule, so none of these acids
# need a CompositionRule registration of their own: `recipe()` already reports their moles under
# exactly the Species that appears as a species in their AcidBaseSystem below.
@species Citrate³⁻ "Citrate3-" -3 187.09u"g/mol"
@species HCitrate²⁻ "HCitrate2-" -2 188.09u"g/mol"
@species H2Citrate⁻ "H2Citrate-" -1 189.10u"g/mol"
@species Lactate⁻ "Lactate-" -1 89.07u"g/mol" # PubChem CID 107689 (distinct from the "Lactic Acid" reagent's own PubChem entry)
@species Oxalate²⁻ "Oxalate2-" -2 88.02u"g/mol" # PubChem CID 971 shares parent; ion CID 71081
@species HOxalate⁻ "HOxalate-" -1 89.02u"g/mol"
@species Formate⁻ "Formate-" -1 45.02u"g/mol" # PubChem CID 283
@species Malate²⁻ "Malate2-" -2 132.08u"g/mol" # PubChem CID 222656
@species HMalate⁻ "HMalate-" -1 133.08u"g/mol"
@species Tetrahydroxyborate⁻ "B(OH)4-" -1 78.84u"g/mol" # B(OH)3 + H2O - H+
@species Propionate⁻ "Propionate-" -1 73.07u"g/mol" # PubChem CID 104745
@species Shikimate⁻ "Shikimate-" -1 173.14u"g/mol"
@species HAlphaKetoglutarate⁻ "HAlphaKetoglutarate-" -1 145.09u"g/mol"
@species AlphaKetoglutarate²⁻ "AlphaKetoglutarate2-" -2 144.08u"g/mol" # PubChem CID 51 shares parent; ion CID 51056

# Zwitterion endpoints (amino acids: aspartic_acid, glutamic_acid; and PABA, a weakly basic aromatic
# amine + carboxylic acid). The reagent's own stored/derived molecular_weight is the *neutral* form in
# every case (the species actually weighed out) -- consistent with the trick above, that neutral state
# is one of AcidBaseSystem's own `species` entries (not necessarily `species[1]`, since the
# fully-protonated *cation* carries a real net charge here), so again no CompositionRule registration
# is needed.
@species AspartateCation "Aspartate(cation)" 1 134.11u"g/mol" # L-aspartic acid + H+
@species AspartateAnion "Aspartate(anion)" -1 132.09u"g/mol" # L-aspartic acid - H+
@species AspartateDianion "Aspartate(dianion)" -2 131.08u"g/mol"
@species GlutamateCation "Glutamate(cation)" 1 148.14u"g/mol" # L-glutamic acid + H+
@species GlutamateAnion "Glutamate(anion)" -1 146.12u"g/mol" # L-glutamic acid - H+
@species GlutamateDianion "Glutamate(dianion)" -2 145.11u"g/mol"
@species PABACation "PABA(cation)" 1 138.15u"g/mol" # 4-aminobenzoic acid + H+ (protonated anilinium)
@species PABAAnion "PABA(anion)" -1 136.13u"g/mol" # 4-aminobenzoic acid - H+ (deprotonated COOH)

# MOPS (a Good's buffer) is weighed out as its zwitterion (protonated morpholinium + sulfonate, net
# charge 0 -- the reagent's own default identity, same trick as above). Its sulfonic acid group is a
# strong acid (pKa ≈ -1) and is always fully deprotonated in any realistic aqueous solution, so it's
# not modeled as an equilibrium step at all (same reasoning as HCl/NaOH staying CompositionRule-only) --
# only the morpholinium's own deprotonation (pKa ≈ 7.20, 25°C) is registered.
@species MOPS⁻ "MOPS-" -1 208.25u"g/mol" # PubChem CID 70807 shares parent; deprotonated morpholine

# Tier-1 audit pass: amino acid endpoints. Each reagent's identity Species is the neutral zwitterion
# (matches stored MW in every case, verified) -- new endpoints are identity MW ± 1.008 g/mol per
# proton, chained outward. See the cluster comments in _register_acid_base_systems! below for each
# chain's shape/pKa citations.
@species AlanineCation "Alanine(cation)" 1 90.098u"g/mol"
@species AlanineAnion "Alanine(anion)" -1 88.082u"g/mol"
@species ValineCation "Valine(cation)" 1 118.158u"g/mol"
@species ValineAnion "Valine(anion)" -1 116.142u"g/mol"
@species LeucineCation "Leucine(cation)" 1 132.178u"g/mol"
@species LeucineAnion "Leucine(anion)" -1 130.162u"g/mol"
@species IsoleucineCation "Isoleucine(cation)" 1 132.178u"g/mol"
@species IsoleucineAnion "Isoleucine(anion)" -1 130.162u"g/mol"
@species GlycineCation "Glycine(cation)" 1 76.078u"g/mol"
@species GlycineAnion "Glycine(anion)" -1 74.062u"g/mol"
@species ProlineCation "Proline(cation)" 1 116.138u"g/mol"
@species ProlineAnion "Proline(anion)" -1 114.122u"g/mol"
@species SerineCation "Serine(cation)" 1 106.098u"g/mol"
@species SerineAnion "Serine(anion)" -1 104.082u"g/mol"
@species ThreonineCation "Threonine(cation)" 1 120.128u"g/mol"
@species ThreonineAnion "Threonine(anion)" -1 118.112u"g/mol"
@species MethionineCation "Methionine(cation)" 1 150.218u"g/mol"
@species MethionineAnion "Methionine(anion)" -1 148.202u"g/mol"
@species PhenylalanineCation "Phenylalanine(cation)" 1 166.198u"g/mol"
@species PhenylalanineAnion "Phenylalanine(anion)" -1 164.182u"g/mol"
@species TryptophanCation "Tryptophan(cation)" 1 205.228u"g/mol"
@species TryptophanAnion "Tryptophan(anion)" -1 203.212u"g/mol"
@species AsparagineCation "Asparagine(cation)" 1 133.128u"g/mol"
@species AsparagineAnion "Asparagine(anion)" -1 131.112u"g/mol"
@species GlutamineCation "Glutamine(cation)" 1 147.148u"g/mol"
@species GlutamineAnion "Glutamine(anion)" -1 145.132u"g/mol"
@species CitrulineCation "Citruline(cation)" 1 176.198u"g/mol"
@species CitrulineAnion "Citruline(anion)" -1 174.182u"g/mol"

@species HistidineDication "Histidine(dication)" 2 157.166u"g/mol" # imidazole side chain is basic, like lysine/arginine/ornithine's -- see the registration below
@species HistidineCation "Histidine(cation)" 1 156.158u"g/mol"
@species HistidineAnion "Histidine(anion)" -1 154.142u"g/mol"
@species CysteineCation "Cysteine(cation)" 1 122.168u"g/mol"
@species CysteineZwitterion "Cysteine(zwitterion)" 0 121.16u"g/mol" # the reagent itself is now the HCl monohydrate salt (see electrolytes.jl), not this state -- kept explicit for the chain
@species CysteineAnion "Cysteine(anion)" -1 120.152u"g/mol"
@species CysteineDianion "Cysteine(dianion)" -2 119.144u"g/mol"
@species TyrosineCation "Tyrosine(cation)" 1 182.198u"g/mol"
@species TyrosineAnion "Tyrosine(anion)" -1 180.182u"g/mol"
@species TyrosineDianion "Tyrosine(dianion)" -2 179.174u"g/mol"

@species LysineDication "Lysine(dication)" 2 148.206u"g/mol"
@species LysineCation "Lysine(cation)" 1 147.198u"g/mol"
@species LysineZwitterion "Lysine(zwitterion)" 0 146.19u"g/mol" # the reagent itself is now the HCl salt (see electrolytes.jl), not this state -- kept explicit for the chain
@species LysineAnion "Lysine(anion)" -1 145.182u"g/mol"
@species ArginineDication "Arginine(dication)" 2 176.216u"g/mol"
@species ArginineCation "Arginine(cation)" 1 175.208u"g/mol"
@species ArginineAnion "Arginine(anion)" -1 173.192u"g/mol"
@species OrnithineDication "Ornithine(dication)" 2 134.176u"g/mol"
@species OrnithineCation "Ornithine(cation)" 1 133.168u"g/mol"
@species OrnithineAnion "Ornithine(anion)" -1 131.152u"g/mol"

# cystine (cysteine's disulfide dimer, symmetric, no thiol) -- approximate macroscopic pKa's, see
# comment at its registration below.
@species CystineDication "Cystine(dication)" 2 242.316u"g/mol"
@species CystineCation "Cystine(cation)" 1 241.308u"g/mol"
@species CystineAnion "Cystine(anion)" -1 239.292u"g/mol"
@species CystineDianion "Cystine(dianion)" -2 238.284u"g/mol"

# Tier-1: common acids. pyruvate/butyrate/tartrate turned out to be real sodium salts (confirmed
# against the lab's actual stocklist, Reagent_StockList.xlsx -- see electrolytes.jl), so their
# reagent's own identity is charged (the anion/dianion), not neutral: `_identity(reagent)` always
# constructs charge 0 (matching composition()'s own default fallback), so it cannot be used for
# these three -- each instead gets an explicit, correctly-charged Species matching the stored MW
# exactly (their CompositionRule, registered in electrolytes.jl, adds the real Na+ counter-ion).
# ascorbate, by contrast, is the plain free acid (also confirmed against the stocklist -- both
# catalog lines there are "L-ASCORBIC ACID") once its stored name/MW/PubChem CID are corrected, so
# it uses the ordinary `_identity(ascorbate)` trick like citric_acid/lactic_acid, no CompositionRule.
@species EDTAAnion "EDTA(anion)" -1 291.232u"g/mol"
@species EDTADianion "EDTA(dianion)" -2 290.224u"g/mol"
@species EDTATrianion "EDTA(trianion)" -3 289.216u"g/mol"
@species EDTATetraanion "EDTA(tetraanion)" -4 288.208u"g/mol"
@species AscorbateAnion "Ascorbate(anion)" -1 175.12u"g/mol"
@species AscorbateDianion "Ascorbate(dianion)" -2 174.112u"g/mol"
@species PyruvicAcid "Pyruvic acid" 0 88.058u"g/mol" # neutral acid
@species PyruvateAnion "Pyruvate(anion)" -1 87.05u"g/mol" # == pyruvate's stored MW, now correctly charged
@species ButyricAcid "Butyric acid" 0 88.108u"g/mol" # neutral acid
@species ButyrateAnion "Butyrate(anion)" -1 87.1u"g/mol" # == butyrate's stored MW, now correctly charged
@species TartaricAcid "Tartaric acid" 0 150.086u"g/mol" # neutral diacid
@species TartrateMonoanion "Tartrate(monoanion)" -1 149.078u"g/mol"
@species TartrateDianion "Tartrate(dianion)" -2 148.07u"g/mol" # == tartrate's stored MW, now correctly charged
@species BiotinAnion "Biotin(anion)" -1 243.302u"g/mol"
@species LipoateAnion "Lipoate(anion)" -1 205.292u"g/mol"

# Tier-1: antibiotics. Sulfonamides/fluoroquinolones/most penicillins reuse the identity trick
# (neutral zwitterion or free acid, matches stored MW) exactly like the amino acids/organic acids
# above. The tetracycline family is the exception: their stored molecular_weight is the *HCl salt*
# mass (confirmed by exact arithmetic, e.g. tetracycline free base 444.43 + HCl 36.46 = 480.89 ≈
# stored 480.9 -- true even for chlortetracycline/doxycycline, whose display names don't say
# "hydrochloride" but whose masses confirm it), so none of their chain states reuse the reagent's own
# identity at all -- see their CompositionRule registration in electrolytes.jl and the fresh
# free-base-derived Species below.
@species SulfadiazineCation "Sulfadiazine(cation)" 1 251.288u"g/mol"
@species SulfadiazineAnion "Sulfadiazine(anion)" -1 249.272u"g/mol"
@species SulfamethazineCation "Sulfamethazine(cation)" 1 279.338u"g/mol"
@species SulfamethazineAnion "Sulfamethazine(anion)" -1 277.322u"g/mol"
@species SulfathiazoleCation "Sulfathiazole(cation)" 1 256.308u"g/mol"
@species SulfathiazoleAnion "Sulfathiazole(anion)" -1 254.292u"g/mol"
@species CiprofloxacinCation "Ciprofloxacin(cation)" 1 332.348u"g/mol"
@species CiprofloxacinAnion "Ciprofloxacin(anion)" -1 330.332u"g/mol"
@species OfloxacinCation "Ofloxacin(cation)" 1 362.408u"g/mol"
@species OfloxacinAnion "Ofloxacin(anion)" -1 360.392u"g/mol"
@species PenicillinGAnion "PenicillinG(anion)" -1 333.392u"g/mol"
@species AmpicillinCation "Ampicillin(cation)" 1 350.408u"g/mol"
@species AmpicillinAnion "Ampicillin(anion)" -1 348.392u"g/mol"
@species AmoxicillinCation "Amoxicillin(cation)" 1 366.408u"g/mol"
@species AmoxicillinAnion "Amoxicillin(anion)" -1 364.392u"g/mol"
@species AmoxicillinDianion "Amoxicillin(dianion)" -2 363.384u"g/mol"
@species CarbenicillinAnion "Carbenicillin(anion)" -1 377.392u"g/mol"
@species OxacillinAnion "Oxacillin(anion)" -1 400.392u"g/mol"

# Tetracycline family (free-base MW anchors, not the reagents' own stored HCl-salt MW): tetracycline
# and doxycycline share the same molecular formula (444.43 g/mol free base); chlortetracycline is
# 478.89 (its own chlorine substituent, separate from the HCl salt's counter-ion); minocycline is
# 457.48. Each gets its own 4-state cation/zwitterion/anion/dianion chain.
@species TetracyclineCation "Tetracycline(cation)" 1 445.438u"g/mol"
@species TetracyclineZwitterion "Tetracycline(zwitterion)" 0 444.430u"g/mol"
@species TetracyclineAnion "Tetracycline(anion)" -1 443.422u"g/mol"
@species TetracyclineDianion "Tetracycline(dianion)" -2 442.414u"g/mol"
@species DoxycyclineCation "Doxycycline(cation)" 1 445.438u"g/mol"
@species DoxycyclineZwitterion "Doxycycline(zwitterion)" 0 444.430u"g/mol"
@species DoxycyclineAnion "Doxycycline(anion)" -1 443.422u"g/mol"
@species DoxycyclineDianion "Doxycycline(dianion)" -2 442.414u"g/mol"
@species ChlortetracyclineCation "Chlortetracycline(cation)" 1 479.898u"g/mol"
@species ChlortetracyclineZwitterion "Chlortetracycline(zwitterion)" 0 478.890u"g/mol"
@species ChlortetracyclineAnion "Chlortetracycline(anion)" -1 477.882u"g/mol"
@species ChlortetracyclineDianion "Chlortetracycline(dianion)" -2 476.874u"g/mol"
@species MinocyclineCation "Minocycline(cation)" 1 458.488u"g/mol"
@species MinocyclineZwitterion "Minocycline(zwitterion)" 0 457.480u"g/mol"
@species MinocyclineAnion "Minocycline(anion)" -1 456.472u"g/mol"
@species MinocyclineDianion "Minocycline(dianion)" -2 455.464u"g/mol"

@species CycloserineCation "Cycloserine(cation)" 1 103.098u"g/mol"
@species CycloserineAnion "Cycloserine(anion)" -1 101.082u"g/mol"
@species ErythromycinCation "Erythromycin(cation)" 1 734.908u"g/mol"
@species LincomycinCation "Lincomycin(cation)" 1 407.508u"g/mol"

# Tier-1: miscellaneous simple bases.
@species PromethazineCation "Promethazine(cation)" 1 285.408u"g/mol"
@species CarnitineCation "Carnitine(cation)" 1 162.208u"g/mol" # the quaternary N is permanently +1; only the carboxyl equilibrates
@species TaurineAnion "Taurine(anion)" -1 124.142u"g/mol" # sulfonate stays fully deprotonated, MOPS-style; only the amine equilibrates
@species AgmatineDication "Agmatine(dication)" 2 132.206u"g/mol"
@species AgmatineCation "Agmatine(cation)" 1 131.198u"g/mol"
@species AmitroleCation "Amitrole(cation)" 1 85.088u"g/mol"
@species BenzamidineCation "Benzamidine(cation)" 1 121.158u"g/mol"
@species GuanidineCation "Guanidine(cation)" 1 60.078u"g/mol"

# Metal-cation hydrolysis, and other salts audited on request. Fe³⁺ (registered on iron_chloride and
# iron_nitrate) is a classic hydrolyzing Lewis-acidic metal cation -- this is why FeCl3 solutions are
# well known to run distinctly acidic in practice. Only the first hydrolysis step is modeled (real
# solutions precipitate Fe(OH)3 rather than continuing as a clean aqueous equilibrium past that);
# same documented-simplification spirit as boric acid's apparent pKa. Fe²⁺ (iron_sulfate) hydrolyzes
# far more weakly (pKa≈9.5, standard reference value e.g. Baes & Mesmer) since its lower charge
# density polarizes coordinated water much less than Fe³⁺'s -- registered too, for completeness.
@species FeOH²⁺ "FeOH2+" 2 72.847u"g/mol" # Fe3+ + H2O - H+
@species FeOH⁺ "FeOH+" 1 72.847u"g/mol" # Fe2+ + H2O - H+ (same mass as FeOH2+, one less charge)

# Succinic acid: sodium_succinate_hexahydrate's own CompositionRule already dissociates to the fully
# deprotonated dianion (C4H4O4²⁻, already in ions.jl), same situation as pyruvate/butyrate/tartrate --
# these two new endpoints are the more-protonated states above it in the chain.
@species SuccinicAcid "Succinic acid" 0 118.086u"g/mol" # matches real succinic acid's MW (118.09) -- consistency check
@species SuccinateMonoanion "Succinate(monoanion)" -1 117.078u"g/mol"

# Ammonium: NH4⁺ (already in ions.jl, shared by ammonium_chloride/ammonium_nitrate/ammonium_sulfate)
# is one of the most well-established weak acids in aqueous chemistry (conjugate acid of ammonia).
@species NH3 "NH3" 0 17.031u"g/mol" # PubChem CID 222

# butyric_acid/succinic_acid/l_malic_acid/d_malic_acid are new free-acid reagents added alongside
# the existing sodium_butyrate/sodium_succinate_hexahydrate/malic_acid salts -- same conjugate
# chemistry, so they reuse the ButyricAcid/SuccinicAcid/HMalate-/Malate2- Species already defined
# above rather than duplicating them. Only ethanolamine/putrescine/hypoxanthine below are genuinely
# new conjugate endpoints.
@species EthanolamineCation "Ethanolamine(cation)" 1 62.092u"g/mol"
@species PutrescineDication "Putrescine(dication)" 2 90.166u"g/mol"
@species PutrescineCation "Putrescine(cation)" 1 89.158u"g/mol"
@species HypoxanthineAnion "Hypoxanthine(anion)" -1 135.10u"g/mol"

# Glutathione (reduced): 4 ionizable groups (gamma-Glu carboxyl, Gly carboxyl, Cys thiol, alpha-amino).
# pKa's are the well-established Rabenstein 1973 values (13C-NMR titration; widely cited in
# biochemistry references since), same [cation,identity,anion,dianion,trianion] chain shape as
# aspartic_acid/glutamic_acid above -- identity's net-neutral state is the physiological zwitterion
# (NH3+, gamma-COO-, SH, Gly-COOH), matching how _identity's charge-0/stored-MW convention is already
# used for those two-carboxyl amino acids.
@species GSHCation "Glutathione(cation)" 1 308.338u"g/mol"
@species GSHAnion "Glutathione(anion)" -1 306.322u"g/mol"
@species GSHDianion "Glutathione(dianion)" -2 305.314u"g/mol"
@species GSHTrianion "Glutathione(trianion)" -3 304.306u"g/mol"

function _register_acid_base_systems!()
    # Phosphoric acid family: H3PO4 ⇌ H2PO4⁻ ⇌ HPO4²⁻ ⇌ PO4³⁻ -- pKa1/pKa2/pKa3 = 2.148/7.198/12.375
    # (CRC Handbook, 25°C). Shared across all four phosphate salts -- same conjugate family regardless
    # of counter-ion (K⁺ vs Na⁺, already handled by each reagent's own CompositionRule).
    phosphoric_acid_system = AcidBaseSystem([H3PO4,H2PO4⁻,HPO4²⁻,PO4³⁻],[2.148,7.198,12.375])
    set_acid_base_system!(potassium_phosphate_mono,phosphoric_acid_system)
    set_acid_base_system!(potassium_phosphate_di,phosphoric_acid_system)
    set_acid_base_system!(sodium_phosphate_mono,phosphoric_acid_system)
    set_acid_base_system!(sodium_phosphate_di,phosphoric_acid_system)
    set_acid_base_system!(sodium_phosphate_di_anhydrous,phosphoric_acid_system)

    # Carbonic acid family: H2CO3 ⇌ HCO3⁻ ⇌ CO3²⁻ -- pKa1/pKa2 = 6.352/10.329 (CRC Handbook, 25°C).
    # pKa1 here is the *apparent* constant that folds in dissolved CO2(aq)/H2CO3 partitioning (the
    # true H2CO3-only pKa is much lower, ~3.6, but essentially all "H2CO3" in aqueous solution is
    # actually dissolved CO2 -- the apparent constant is what's practically relevant and is the
    # standard convention used here).
    carbonic_acid_system = AcidBaseSystem([H2CO3,HCO3⁻,CO3²⁻],[6.352,10.329])
    set_acid_base_system!(sodium_bicarbonate,carbonic_acid_system)
    set_acid_base_system!(sodium_carbonate,carbonic_acid_system)

    # Dissolved atmospheric CO2, registered as the default `pH(...;water_correction=true)` correction
    # (see CHESSCore.OpenSystemSpecies/set_default_water_correction! -- an open-system boundary
    # condition, fixed [CO2(aq)] rather than a fixed total dose, so it correctly absorbs more into
    # HCO3-/CO3(2-) as pH rises, unlike a naive fixed-mole-dose approach). Free [CO2(aq)] concentration
    # calibrated against an empirical measurement (2026): a 20 g/L NaCl solution (NaCl itself has no
    # acid/base chemistry of its own -- confirmed via composition/acid_base_system elsewhere in this
    # package -- so this measurement isolates the water's own background acidity, with enough ionic
    # strength for a stable probe reading) read pH 5.93. Solved (via bisection on the free
    # concentration, matching pH under this exact open-system model, ionic_strength_correction on) for
    # the value reproducing that exactly: 1.7005985e-6 mol/L. Recalibrated here (was 1.639648e-6) after
    # the Truesdell-Jones ion-parameter upgrade (see ions.jl's _register_ion_parameters!) gave Na+/Cl-
    # their own real activity coefficients instead of sharing Davies' one-per-charge value -- re-verify
    # numerically after any change to the activity model, rather than assume a stale constant still
    # reproduces the same measurement.
    CHESSCore.set_default_water_correction!(CHESSCore.OpenSystemSpecies(carbonic_acid_system,1.7005985e-6u"mol/L"))

    # Organic acids -- each fully-protonated (neutral) reference state is built from the reagent's own
    # name/molecular_weight, so it's `==` to what composition(reagent) already returns by default (see
    # the comment above the Species definitions).
    _identity(r::Reagent) = CHESSCore.Species(name(r),0,molecular_weight(r))

    citric_acid_system = AcidBaseSystem([_identity(citric_acid),H2Citrate⁻,HCitrate²⁻,Citrate³⁻],[3.13,4.76,6.40])
    set_acid_base_system!(citric_acid,citric_acid_system)
    # sodium_citrate_dihydrate is the same conjugate family from the fully-deprotonated end (its
    # CompositionRule, electrolytes.jl, already dissociates it straight to Citrate3-) -- shared
    # AcidBaseSystem instance, same pattern as acetic_acid/sodium_acetate below.
    set_acid_base_system!(sodium_citrate_dihydrate,citric_acid_system)
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
    # d_alanine: same conjugate acid/base chemistry as its DL/L stereoisomers (stereochemistry
    # doesn't affect pKa), reusing AlanineCation/AlanineAnion -- same pattern as l_malic_acid/
    # d_malic_acid reusing HMalate-/Malate2- above.
    set_acid_base_system!(d_alanine,AcidBaseSystem([AlanineCation,_identity(d_alanine),AlanineAnion],[2.34,9.69]))
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
    # zwitterion, so the zwitterion state uses its own explicit Species rather than _identity
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
    # the zwitterion state uses its own explicit Species rather than _identity
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
    # pyruvate/butyrate/tartrate: identity is a real, charged salt component (see the Species
    # definitions' comment above) -- chains are built around that fact, not the assumption that
    # identity is the neutral acid.
    set_acid_base_system!(sodium_pyruvate,AcidBaseSystem([PyruvicAcid,PyruvateAnion],[2.5]))
    set_acid_base_system!(sodium_butyrate,AcidBaseSystem([ButyricAcid,ButyrateAnion],[4.82]))
    set_acid_base_system!(tartrate,AcidBaseSystem([TartaricAcid,TartrateMonoanion,TartrateDianion],[3.0,4.4]))
    set_acid_base_system!(biotin,AcidBaseSystem([_identity(biotin),BiotinAnion],[4.5]))
    # literature range ≈4.7-5.4; representative value, not a single universally-agreed constant.
    set_acid_base_system!(lipoic_acid,AcidBaseSystem([_identity(lipoic_acid),LipoateAnion],[4.8]))

    # Free-acid counterparts of already-registered salts, reusing the same conjugate chain/pKa (see
    # the Species definitions' comment above) -- these reagents' identity is the plain neutral acid
    # (matches composition()'s default), unlike the pyruvate/butyrate/tartrate salts just above.
    set_acid_base_system!(butyric_acid,AcidBaseSystem([_identity(butyric_acid),ButyrateAnion],[4.82]))
    set_acid_base_system!(succinic_acid,AcidBaseSystem(
        [_identity(succinic_acid),SuccinateMonoanion,C4H4O4²⁻],[4.21,5.64]))
    set_acid_base_system!(l_malic_acid,AcidBaseSystem([_identity(l_malic_acid),HMalate⁻,Malate²⁻],[3.40,5.20]))
    set_acid_base_system!(d_malic_acid,AcidBaseSystem([_identity(d_malic_acid),HMalate⁻,Malate²⁻],[3.40,5.20]))
    # ethanolamine: conjugate acid pKa 9.50 (CRC Handbook), same [cation,identity] shape as ammonium.
    set_acid_base_system!(ethanolamine,AcidBaseSystem([EthanolamineCation,_identity(ethanolamine)],[9.50]))
    # putrescine (1,4-butanediamine): two amines, pKa1=9.35/pKa2=10.80 (CRC Handbook), same
    # low-then-high chain shape as agmatine above.
    set_acid_base_system!(putrescine,AcidBaseSystem(
        [PutrescineDication,PutrescineCation,_identity(putrescine)],[9.35,10.80]))
    # hypoxanthine: only the well-established acidic N-H deprotonation (pKa 8.94, CRC Handbook) is
    # registered; its weak ring-nitrogen basicity (pKa~2, low confidence/less consistently reported)
    # is left out, same documented-scope-boundary spirit as folic_acid/fusidic_acid.
    set_acid_base_system!(hypoxanthine,AcidBaseSystem([_identity(hypoxanthine),HypoxanthineAnion],[8.94]))
    # glutathione: Rabenstein (1973) J. Am. Chem. Soc. 95, 2797 -- gamma-Glu-COOH 2.05, Gly-COOH 3.53,
    # Cys-SH 8.66, alpha-NH3+ 9.42.
    set_acid_base_system!(glutathione,AcidBaseSystem(
        [GSHCation,_identity(glutathione),GSHAnion,GSHDianion,GSHTrianion],[2.05,3.53,8.66,9.42]))

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
    # Tetracyclines: stored molecular_weight is the HCl salt mass (see Species comment above), so
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

    # Requested audit: iron chloride, sodium succinate, ammonium sulfate (plus the salts sharing the
    # same ion, same shared-family pattern as phosphate/carbonate/acetic acid above).
    # Fe3+ hydrolysis, first step only (see the Species definitions' comment above):
    iron_hydrolysis_system = AcidBaseSystem([Fe³⁺,FeOH²⁺],[2.2])
    set_acid_base_system!(iron_chloride,iron_hydrolysis_system)
    set_acid_base_system!(iron_nitrate,iron_hydrolysis_system)
    # Fe2+ hydrolysis (much weaker than Fe3+'s, see the Species definitions' comment above):
    set_acid_base_system!(iron_sulfate,AcidBaseSystem([Fe²⁺,FeOH⁺],[9.5]))
    # succinic acid: sodium_succinate_hexahydrate's identity is already the dianion (see above):
    set_acid_base_system!(sodium_succinate_hexahydrate,AcidBaseSystem(
        [SuccinicAcid,SuccinateMonoanion,C4H4O4²⁻],[4.21,5.64]))
    # ammonium, shared across all three ammonium salts:
    ammonium_system = AcidBaseSystem([NH4⁺,NH3],[9.25])
    set_acid_base_system!(ammonium_chloride,ammonium_system)
    set_acid_base_system!(ammonium_nitrate,ammonium_system)
    set_acid_base_system!(ammonium_sulfate,ammonium_system)

    return nothing
end
