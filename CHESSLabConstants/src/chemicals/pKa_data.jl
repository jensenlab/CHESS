# Acid/base equilibrium (AcidBaseSystem) data -- registers weak acid/base families against reagents
# already defined in solids.jl. Independent of (and additional to) those reagents' Dissolutions
# in electrolytes.jl, which continue to answer the separate question of complete-dissociation mass
# bookkeeping; this file answers "how does this reagent's dissolved chemistry actually speciate as a
# function of pH." See CHESSCore/src/stocks/AcidBase.jl for the AcidBaseSystem type and solver.
#
# pKa values are thermodynamic (25°C, infinite-dilution) constants -- ionic strength corrections are
# applied at solve time (see CHESSCore.activity_coefficient), not baked in here. Sourced from the CRC
# Handbook of Chemistry and Physics (acid dissociation constants table) unless noted otherwise.
#
# Like electrolytes.jl's set_dissolution! calls, these set_acid_base_system! calls are wrapped in a
# function invoked from CHESSLabConstants's own __init__ rather than running at top-level here, for
# the same precompilation-safety reason (acid_base_systems is a global Dict owned by CHESSCore).

# New Species endpoints not already defined in ions.jl (H2PO4⁻/HPO4²⁻/HCO3⁻/CO3²⁻ already exist there)
@species H3PO4 "H3PO4" 0 "H3PO4" # PubChem CID 1004
@species PO4³⁻ "PO4 3-" -3 "PO4" # PubChem CID 1061
@species H2CO3 "H2CO3" 0 "H2CO3" # PubChem CID 767

# Organic acid conjugate-base endpoints. Each acid's fully-protonated (neutral, as-weighed) reference
# state is the reagent's own identity species -- the single product of its registered Dissolution --
# so none of these acids need a Dissolution registration of their own beyond the one `@reagent`
# makes: `composition()` already reports their moles under exactly the Species that appears in their
# AcidBaseSystem below (see `_identity`). Each conjugate base is defined by its formula, the acid's
# formula with the protons removed.
@species Citrate³⁻ "Citrate3-" -3 "C6H5O7"
@species HCitrate²⁻ "HCitrate2-" -2 "C6H6O7"
@species H2Citrate⁻ "H2Citrate-" -1 "C6H7O7"
@species Lactate⁻ "Lactate-" -1 "C3H5O3" # PubChem CID 107689 (distinct from the "Lactic Acid" reagent's own PubChem entry)
@species Oxalate²⁻ "Oxalate2-" -2 "C2O4" # PubChem CID 971 shares parent; ion CID 71081
@species HOxalate⁻ "HOxalate-" -1 "C2HO4"
@species Formate⁻ "Formate-" -1 "CHO2" # PubChem CID 283
@species Malate²⁻ "Malate2-" -2 "C4H4O5" # PubChem CID 222656
@species HMalate⁻ "HMalate-" -1 "C4H5O5"
@species Tetrahydroxyborate⁻ "B(OH)4-" -1 "B(OH)4" # B(OH)3 + H2O - H+
@species Propionate⁻ "Propionate-" -1 "C3H5O2" # PubChem CID 104745
@species Shikimate⁻ "Shikimate-" -1 "C7H9O5"
@species HAlphaKetoglutarate⁻ "HAlphaKetoglutarate-" -1 "C5H5O5"
@species AlphaKetoglutarate²⁻ "AlphaKetoglutarate2-" -2 "C5H4O5" # PubChem CID 51 shares parent; ion CID 51056

# Zwitterion endpoints (amino acids: aspartic_acid, glutamic_acid; and PABA, a weakly basic aromatic
# amine + carboxylic acid). The reagent's own stored/derived molecular_weight is the *neutral* form in
# every case (the species actually weighed out) -- consistent with the trick above, that neutral state
# is one of AcidBaseSystem's own `species` entries (not necessarily `species[1]`, since the
# fully-protonated *cation* carries a real net charge here), so again no Dissolution registration
# is needed.
@species AspartateCation "Aspartate(cation)" 1 "C4H8NO4" # L-aspartic acid + H+
@species AspartateAnion "Aspartate(anion)" -1 "C4H6NO4" # L-aspartic acid - H+
@species AspartateDianion "Aspartate(dianion)" -2 "C4H5NO4"
@species GlutamateCation "Glutamate(cation)" 1 "C5H10NO4" # L-glutamic acid + H+
@species GlutamateAnion "Glutamate(anion)" -1 "C5H8NO4" # L-glutamic acid - H+
@species GlutamateDianion "Glutamate(dianion)" -2 "C5H7NO4"
@species PABACation "PABA(cation)" 1 "C7H8NO2" # 4-aminobenzoic acid + H+ (protonated anilinium)
@species PABAAnion "PABA(anion)" -1 "C7H6NO2" # 4-aminobenzoic acid - H+ (deprotonated COOH)

# MOPS (a Good's buffer) is weighed out as its zwitterion (protonated morpholinium + sulfonate, net
# charge 0 -- the reagent's own default identity, same trick as above). Its sulfonic acid group is a
# strong acid (pKa ≈ -1) and is always fully deprotonated in any realistic aqueous solution, so it's
# not modeled as an equilibrium step at all (same reasoning as HCl/NaOH staying Dissolution-only) --
# only the morpholinium's own deprotonation (pKa ≈ 7.20, 25°C) is registered.
@species MOPS⁻ "MOPS-" -1 "C7H14NO4S" # PubChem CID 70807 shares parent; deprotonated morpholine

# Tier-1 audit pass: amino acid endpoints. Each reagent's identity Species is the neutral zwitterion
# -- the endpoints are its formula with one proton added or removed per unit of charge, chained
# outward. See the cluster comments in _register_acid_base_systems! below for each chain's
# shape/pKa citations.
@species AlanineCation "Alanine(cation)" 1 "C3H8NO2"
@species AlanineAnion "Alanine(anion)" -1 "C3H6NO2"
@species ValineCation "Valine(cation)" 1 "C5H12NO2"
@species ValineAnion "Valine(anion)" -1 "C5H10NO2"
@species LeucineCation "Leucine(cation)" 1 "C6H14NO2"
@species LeucineAnion "Leucine(anion)" -1 "C6H12NO2"
@species IsoleucineCation "Isoleucine(cation)" 1 "C6H14NO2"
@species IsoleucineAnion "Isoleucine(anion)" -1 "C6H12NO2"
@species GlycineCation "Glycine(cation)" 1 "C2H6NO2"
@species GlycineAnion "Glycine(anion)" -1 "C2H4NO2"
@species ProlineCation "Proline(cation)" 1 "C5H10NO2"
@species ProlineAnion "Proline(anion)" -1 "C5H8NO2"
@species SerineCation "Serine(cation)" 1 "C3H8NO3"
@species SerineAnion "Serine(anion)" -1 "C3H6NO3"
@species ThreonineCation "Threonine(cation)" 1 "C4H10NO3"
@species ThreonineAnion "Threonine(anion)" -1 "C4H8NO3"
@species MethionineCation "Methionine(cation)" 1 "C5H12NO2S"
@species MethionineAnion "Methionine(anion)" -1 "C5H10NO2S"
@species PhenylalanineCation "Phenylalanine(cation)" 1 "C9H12NO2"
@species PhenylalanineAnion "Phenylalanine(anion)" -1 "C9H10NO2"
@species TryptophanCation "Tryptophan(cation)" 1 "C11H13N2O2"
@species TryptophanAnion "Tryptophan(anion)" -1 "C11H11N2O2"
@species AsparagineCation "Asparagine(cation)" 1 "C4H9N2O3"
@species AsparagineAnion "Asparagine(anion)" -1 "C4H7N2O3"
@species GlutamineCation "Glutamine(cation)" 1 "C5H11N2O3"
@species GlutamineAnion "Glutamine(anion)" -1 "C5H9N2O3"
@species CitrulineCation "Citruline(cation)" 1 "C6H14N3O3"
@species CitrulineAnion "Citruline(anion)" -1 "C6H12N3O3"

@species HistidineDication "Histidine(dication)" 2 "C6H11N3O2" # imidazole side chain is basic, like lysine/arginine/ornithine's -- see the registration below
@species HistidineCation "Histidine(cation)" 1 "C6H10N3O2"
@species HistidineAnion "Histidine(anion)" -1 "C6H8N3O2"
@species CysteineCation "Cysteine(cation)" 1 "C3H8NO2S"
@species CysteineZwitterion "Cysteine(zwitterion)" 0 "C3H7NO2S" # the reagent itself is now the HCl monohydrate salt (see electrolytes.jl), not this state -- kept explicit for the chain
@species CysteineAnion "Cysteine(anion)" -1 "C3H6NO2S"
@species CysteineDianion "Cysteine(dianion)" -2 "C3H5NO2S"
@species TyrosineCation "Tyrosine(cation)" 1 "C9H12NO3"
@species TyrosineAnion "Tyrosine(anion)" -1 "C9H10NO3"
@species TyrosineDianion "Tyrosine(dianion)" -2 "C9H9NO3"

@species LysineDication "Lysine(dication)" 2 "C6H16N2O2"
@species LysineCation "Lysine(cation)" 1 "C6H15N2O2"
@species LysineZwitterion "Lysine(zwitterion)" 0 "C6H14N2O2" # the reagent itself is now the HCl salt (see electrolytes.jl), not this state -- kept explicit for the chain
@species LysineAnion "Lysine(anion)" -1 "C6H13N2O2"
@species ArginineDication "Arginine(dication)" 2 "C6H16N4O2"
@species ArginineCation "Arginine(cation)" 1 "C6H15N4O2"
@species ArginineAnion "Arginine(anion)" -1 "C6H13N4O2"
@species OrnithineDication "Ornithine(dication)" 2 "C5H14N2O2"
@species OrnithineCation "Ornithine(cation)" 1 "C5H13N2O2"
@species OrnithineAnion "Ornithine(anion)" -1 "C5H11N2O2"

# cystine (cysteine's disulfide dimer, symmetric, no thiol) -- approximate macroscopic pKa's, see
# comment at its registration below.
@species CystineDication "Cystine(dication)" 2 "C6H14N2O4S2"
@species CystineCation "Cystine(cation)" 1 "C6H13N2O4S2"
@species CystineAnion "Cystine(anion)" -1 "C6H11N2O4S2"
@species CystineDianion "Cystine(dianion)" -2 "C6H10N2O4S2"

# Tier-1: common acids. pyruvate/butyrate/tartrate turned out to be real sodium salts (confirmed
# against the lab's actual stocklist, Reagent_StockList.xlsx -- see electrolytes.jl), so their
# reagent's own identity is charged (the anion/dianion), not neutral: `_identity(reagent)` always
# constructs charge 0 (matching dissolution()'s own default fallback), so it cannot be used for
# these three -- each instead gets an explicit, correctly-charged Species matching the stored MW
# exactly (their Dissolution, registered in electrolytes.jl, adds the real Na+ counter-ion).
# ascorbate, by contrast, is the plain free acid (also confirmed against the stocklist -- both
# catalog lines there are "L-ASCORBIC ACID") once its stored name/MW/PubChem CID are corrected, so
# it uses the ordinary `_identity(ascorbate)` trick like citric_acid/lactic_acid, no Dissolution.
@species EDTAAnion "EDTA(anion)" -1 "C10H15N2O8"
@species EDTADianion "EDTA(dianion)" -2 "C10H14N2O8"
@species EDTATrianion "EDTA(trianion)" -3 "C10H13N2O8"
@species EDTATetraanion "EDTA(tetraanion)" -4 "C10H12N2O8"
@species AscorbateAnion "Ascorbate(anion)" -1 "C6H7O6"
@species AscorbateDianion "Ascorbate(dianion)" -2 "C6H6O6"
@species PyruvicAcid "Pyruvic acid" 0 "C3H4O3" # neutral acid
@species PyruvateAnion "Pyruvate(anion)" -1 "C3H3O3" # == pyruvate's stored MW, now correctly charged
@species ButyricAcid "Butyric acid" 0 "C4H8O2" # neutral acid
@species ButyrateAnion "Butyrate(anion)" -1 "C4H7O2" # == butyrate's stored MW, now correctly charged
@species TartaricAcid "Tartaric acid" 0 "C4H6O6" # neutral diacid
@species TartrateMonoanion "Tartrate(monoanion)" -1 "C4H5O6"
@species TartrateDianion "Tartrate(dianion)" -2 "C4H4O6" # == tartrate's stored MW, now correctly charged
@species BiotinAnion "Biotin(anion)" -1 "C10H15N2O3S"
@species LipoateAnion "Lipoate(anion)" -1 "C8H13O2S2"

# Tier-1: antibiotics. Sulfonamides/fluoroquinolones/most penicillins reuse the identity trick
# (neutral zwitterion or free acid, matches stored MW) exactly like the amino acids/organic acids
# above. The tetracycline family is the exception: their stored molecular_weight is the *HCl salt*
# mass (confirmed by exact arithmetic, e.g. tetracycline free base 444.43 + HCl 36.46 = 480.89 ≈
# stored 480.9 -- true even for chlortetracycline/doxycycline, whose display names don't say
# "hydrochloride" but whose masses confirm it), so none of their chain states reuse the reagent's own
# identity at all -- see their Dissolution registration in electrolytes.jl and the fresh
# free-base-derived Species below.
@species SulfadiazineCation "Sulfadiazine(cation)" 1 "C10H11N4O2S"
@species SulfadiazineAnion "Sulfadiazine(anion)" -1 "C10H9N4O2S"
@species SulfamethazineCation "Sulfamethazine(cation)" 1 "C12H15N4O2S"
@species SulfamethazineAnion "Sulfamethazine(anion)" -1 "C12H13N4O2S"
@species SulfathiazoleCation "Sulfathiazole(cation)" 1 "C9H10N3O2S2"
@species SulfathiazoleAnion "Sulfathiazole(anion)" -1 "C9H8N3O2S2"
@species CiprofloxacinCation "Ciprofloxacin(cation)" 1 "C17H19FN3O3"
@species CiprofloxacinAnion "Ciprofloxacin(anion)" -1 "C17H17FN3O3"
@species OfloxacinCation "Ofloxacin(cation)" 1 "C18H21FN3O4"
@species OfloxacinAnion "Ofloxacin(anion)" -1 "C18H19FN3O4"
@species PenicillinGAnion "PenicillinG(anion)" -1 "C16H17N2O4S"
@species AmpicillinCation "Ampicillin(cation)" 1 "C16H20N3O4S"
@species AmpicillinAnion "Ampicillin(anion)" -1 "C16H18N3O4S"
@species AmoxicillinCation "Amoxicillin(cation)" 1 "C16H20N3O5S"
@species AmoxicillinAnion "Amoxicillin(anion)" -1 "C16H18N3O5S"
@species AmoxicillinDianion "Amoxicillin(dianion)" -2 "C16H17N3O5S"
@species CarbenicillinAnion "Carbenicillin(anion)" -1 "C17H17N2O6S"
@species OxacillinAnion "Oxacillin(anion)" -1 "C19H18N3O5S"

# Tetracycline family (free-base MW anchors, not the reagents' own stored HCl-salt MW): tetracycline
# and doxycycline share the same molecular formula (444.43 g/mol free base); chlortetracycline is
# 478.89 (its own chlorine substituent, separate from the HCl salt's counter-ion); minocycline is
# 457.48. Each gets its own 4-state cation/zwitterion/anion/dianion chain.
@species TetracyclineCation "Tetracycline(cation)" 1 "C22H25N2O8"
@species TetracyclineZwitterion "Tetracycline(zwitterion)" 0 "C22H24N2O8"
@species TetracyclineAnion "Tetracycline(anion)" -1 "C22H23N2O8"
@species TetracyclineDianion "Tetracycline(dianion)" -2 "C22H22N2O8"
@species DoxycyclineCation "Doxycycline(cation)" 1 "C22H25N2O8"
@species DoxycyclineZwitterion "Doxycycline(zwitterion)" 0 "C22H24N2O8"
@species DoxycyclineAnion "Doxycycline(anion)" -1 "C22H23N2O8"
@species DoxycyclineDianion "Doxycycline(dianion)" -2 "C22H22N2O8"
@species ChlortetracyclineCation "Chlortetracycline(cation)" 1 "C22H24ClN2O8"
@species ChlortetracyclineZwitterion "Chlortetracycline(zwitterion)" 0 "C22H23ClN2O8"
@species ChlortetracyclineAnion "Chlortetracycline(anion)" -1 "C22H22ClN2O8"
@species ChlortetracyclineDianion "Chlortetracycline(dianion)" -2 "C22H21ClN2O8"
@species MinocyclineCation "Minocycline(cation)" 1 "C23H28N3O7"
@species MinocyclineZwitterion "Minocycline(zwitterion)" 0 "C23H27N3O7"
@species MinocyclineAnion "Minocycline(anion)" -1 "C23H26N3O7"
@species MinocyclineDianion "Minocycline(dianion)" -2 "C23H25N3O7"

@species CycloserineCation "Cycloserine(cation)" 1 "C3H7N2O2"
@species CycloserineAnion "Cycloserine(anion)" -1 "C3H5N2O2"
@species ErythromycinCation "Erythromycin(cation)" 1 "C37H68NO13"
@species LincomycinCation "Lincomycin(cation)" 1 "C18H35N2O6S"

# Tier-1: miscellaneous simple bases.
@species PromethazineCation "Promethazine(cation)" 1 "C17H21N2S"
@species CarnitineCation "Carnitine(cation)" 1 "C7H16NO3" # the quaternary N is permanently +1; only the carboxyl equilibrates
@species TaurineAnion "Taurine(anion)" -1 "C2H6NO3S" # sulfonate stays fully deprotonated, MOPS-style; only the amine equilibrates
@species AgmatineDication "Agmatine(dication)" 2 "C5H16N4"
@species AgmatineCation "Agmatine(cation)" 1 "C5H15N4"
@species AmitroleCation "Amitrole(cation)" 1 "C2H5N4"
@species BenzamidineCation "Benzamidine(cation)" 1 "C7H9N2"
@species GuanidineCation "Guanidine(cation)" 1 "CH6N3"

# Metal-cation hydrolysis, and other salts audited on request. Fe³⁺ (registered on iron_chloride and
# iron_nitrate) is a classic hydrolyzing Lewis-acidic metal cation -- this is why FeCl3 solutions are
# well known to run distinctly acidic in practice. Only the first hydrolysis step is modeled (real
# solutions precipitate Fe(OH)3 rather than continuing as a clean aqueous equilibrium past that);
# same documented-simplification spirit as boric acid's apparent pKa. Fe²⁺ (iron_sulfate) hydrolyzes
# far more weakly (pKa≈9.5, standard reference value e.g. Baes & Mesmer) since its lower charge
# density polarizes coordinated water much less than Fe³⁺'s -- registered too, for completeness.
@species FeOH²⁺ "FeOH2+" 2 "FeOH" # Fe3+ + H2O - H+
@species FeOH⁺ "FeOH+" 1 "FeOH" # Fe2+ + H2O - H+ (same mass as FeOH2+, one less charge)

# Succinic acid: sodium_succinate_hexahydrate's own Dissolution already dissociates to the fully
# deprotonated dianion (C4H4O4²⁻, already in ions.jl), same situation as pyruvate/butyrate/tartrate --
# these two new endpoints are the more-protonated states above it in the chain.
@species SuccinicAcid "Succinic acid" 0 "C4H6O4" # matches real succinic acid's MW (118.09) -- consistency check
@species SuccinateMonoanion "Succinate(monoanion)" -1 "C4H5O4"

# Ammonium: NH4⁺ (already in ions.jl, shared by ammonium_chloride/ammonium_nitrate/ammonium_sulfate)
# is one of the most well-established weak acids in aqueous chemistry (conjugate acid of ammonia).
@species NH3 "NH3" 0 "NH3" # PubChem CID 222

# butyric_acid/succinic_acid/l_malic_acid/d_malic_acid are new free-acid reagents added alongside
# the existing sodium_butyrate/sodium_succinate_hexahydrate/malic_acid salts -- same conjugate
# chemistry, so they reuse the ButyricAcid/SuccinicAcid/HMalate-/Malate2- Species already defined
# above rather than duplicating them. Only ethanolamine/putrescine/hypoxanthine below are genuinely
# new conjugate endpoints.
@species EthanolamineCation "Ethanolamine(cation)" 1 "C2H8NO"
@species PutrescineDication "Putrescine(dication)" 2 "C4H14N2"
@species PutrescineCation "Putrescine(cation)" 1 "C4H13N2"
@species HypoxanthineAnion "Hypoxanthine(anion)" -1 "C5H3N4O"

# Glutathione (reduced): 4 ionizable groups (gamma-Glu carboxyl, Gly carboxyl, Cys thiol, alpha-amino).
# pKa's are the well-established Rabenstein 1973 values (13C-NMR titration; widely cited in
# biochemistry references since), same [cation,identity,anion,dianion,trianion] chain shape as
# aspartic_acid/glutamic_acid above -- identity's net-neutral state is the physiological zwitterion
# (NH3+, gamma-COO-, SH, Gly-COOH), matching how _identity's charge-0/stored-MW convention is already
# used for those two-carboxyl amino acids.
@species GSHCation "Glutathione(cation)" 1 "C10H18N3O6S"
@species GSHAnion "Glutathione(anion)" -1 "C10H16N3O6S"
@species GSHDianion "Glutathione(dianion)" -2 "C10H15N3O6S"
@species GSHTrianion "Glutathione(trianion)" -3 "C10H14N3O6S"

function _register_acid_base_systems!()
    # Phosphoric acid family: H3PO4 ⇌ H2PO4⁻ ⇌ HPO4²⁻ ⇌ PO4³⁻ -- pKa1/pKa2/pKa3 = 2.148/7.198/12.375
    # (CRC Handbook, 25°C). Shared across all four phosphate salts -- same conjugate family regardless
    # of counter-ion (K⁺ vs Na⁺, already handled by each reagent's own Dissolution).
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
    # acid/base chemistry of its own -- confirmed via dissolution/acid_base_system elsewhere in this
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
    # name/molecular_weight, so it's `==` to what dissolution(reagent) already returns by default (see
    # the comment above the Species definitions).
    _identity(r::Reagent) = only(keys(CHESSCore.dissolution(r).products)) # the reagent's own registered identity species

    citric_acid_system = AcidBaseSystem([_identity(citric_acid),H2Citrate⁻,HCitrate²⁻,Citrate³⁻],[3.13,4.76,6.40])
    set_acid_base_system!(citric_acid,citric_acid_system)
    # sodium_citrate_dihydrate is the same conjugate family from the fully-deprotonated end (its
    # Dissolution, electrolytes.jl, already dissociates it straight to Citrate3-) -- shared
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
    # Dissolutions -- same conjugate species, whether reached via complete salt dissociation or
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
    # ascorbate is the plain free acid (identity = neutral, matches dissolution()'s default):
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
    # (matches dissolution()'s default), unlike the pyruvate/butyrate/tartrate salts just above.
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
    # none of these 4 chain states reuse the reagent's own identity -- their Dissolution
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
