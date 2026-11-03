# Static @reagent definitions for every Solid, alphabetized by lab ID. Generated once from the
# author-time cache (JLConstants_database.db) via register_reagent! -- see chemical_utils.jl. To add
# a new compound, call register_reagent!, paste the returned line in below (alphabetically), commit.

@reagent acetamide "Acetamide" Solid "C2H5NO" 1.159u"g/mL" 178
@reagent_product acetamide "Sigma-Aldrich" catalog_number="A0500" product_name="ACETAMIDE"
@reagent acid_red_1 "Acid Red 1" Solid "C18H13N3Na2O8S2" missing 19522
@reagent_product acid_red_1 "Sigma-Aldrich" catalog_number="210633" notes="dye content 60%"
@reagent adenine "adenine" Solid "C5H5N5" missing 190
@reagent_product adenine "Sigma-Aldrich" catalog_number="1152" product_name="Adenine" notes="Manufacturer: Millipore"
@reagent adenosine "adenosine" Solid "C10H13N5O4" missing 60961
@reagent_product adenosine "Sigma-Aldrich" catalog_number="A4036" product_name="ADENOSINE BIOREAGENT"
@reagent adonitol "Adonitol (Ribitol)" Solid "C5H12O5" missing 6912
# ^ CID 6912 is also xylitol's. PubChem keeps one record for both meso pentitols: the CAS numbers of ribitol
# (488-81-3) and xylitol (87-99-0) both resolve to it, and it leaves the middle carbon's stereochemistry
# undefined. PubChem has no separate record for either, so the two species share the ID and differ by name.
@reagent_product adonitol "Sigma-Aldrich" catalog_number="A5502" product_name="ADONITOL"
@reagent agar "agar" Solid "C14H24O9" missing 71571511
@reagent_product agar "Fisher Scientific" catalog_number="AC443570010" product_name="Thermo Scientific Chemicals Agar, Bacteriological grade, powder" manufacturer_number="Thermo 443570010"
@reagent agmatine_sulfate "agmatine sulfate" Solid missing missing missing
# ^ was agmatine, the free base, until 2026-10-13: the lab bought agmatine sulfate. Its dissolution is in electrolytes.jl.
@reagent_product agmatine_sulfate "Sigma-Aldrich" catalog_number="A7127" product_name="AGMATINE SULFATE"
@reagent alanine "DL-alanine" Solid "C3H7NO2" missing 602
@reagent_product alanine "Sigma-Aldrich" catalog_number="A7502" product_name="DL-Alanine" grade="99%"
@reagent alpha_amylase "alpha-Amylase from porcine pancreas (Type VI-B)" Solid opaque missing missing
# ^ Sold by enzyme activity (1 MU pack), not by mass. An enzyme preparation, so registered
# opaque with no molar mass, for identity/inventory purposes only, same as the other undefined biological
# materials here.
@reagent_product alpha_amylase "Sigma-Aldrich" catalog_number="A3176" product_name="alpha-Amylase from porcine pancreas Type VI-B"
@reagent alpha_cyclodextrin "Alpha-Cyclodextrin" Solid "C36H60O30" missing 444913
@reagent_product alpha_cyclodextrin "Fisher Scientific" catalog_number="J60687.14" product_name="Alpha Cyclodextrin" notes="cyclohexapentylose"
@reagent alpha_ketoglutaric_acid "Alpha Ketoglutaric Acid (2-Oxoglutaric Acid)" Solid "C5H6O5" missing 51
@reagent_product alpha_ketoglutaric_acid "Sigma-Aldrich" catalog_number="75890" product_name="A-KETOGLUTARIC ACID >= 99.0% (T)"
@reagent amitrole "amitrole (3-amino-1,2,4-triazole)" Solid "C2H4N4" 1.138u"g/mL" 1639
@reagent ammonium_chloride "Ammonium_chloride" Solid (NH4⁺+Cl⁻) 1.53u"g/mL" missing
@reagent_product ammonium_chloride "Fisher Scientific" catalog_number="A661-500" product_name="Ammonium Chloride (Crystalline/Certified ACS), Fisher Chemical™"
@reagent_product ammonium_chloride "Sigma-Aldrich" catalog_number="A4514" product_name="AMMONIUM CHLORIDE, REAGENTPLUS"
@reagent ammonium_nitrate "Ammonium Nitrate" Solid (NH4⁺+NO3⁻) 1.72u"g/mL" missing
@reagent_product ammonium_nitrate "Sigma-Aldrich" catalog_number="A9642" product_name="AMMONIUM NITRATE, >=99.0%"
@reagent ammonium_sulfate "Ammonium Sulfate" Solid (2*NH4⁺+SO4²⁻) 1.78u"g/mL" missing
@reagent_product ammonium_sulfate "Fisher Scientific" catalog_number="423400250" product_name="Ammonium Sulfate" grade="99%"
@reagent amoxicillin "amoxicillin" Solid "C16H19N3O5S" missing 33613
@reagent_product amoxicillin "Sigma-Aldrich" catalog_number="A8523" product_name="Amoxicillin" notes="95-102% anhydrous basis. Sigma lists the anhydrous form (C16H19N3O5S, 365.40 g/mol) and notes a high moisture content, so check the lot's certificate of analysis"
@reagent ampicillin_sodium "ampicillin sodium" Solid missing missing missing
# ^ both products in the lab are the sodium salt (Sigma-Aldrich A8351 and Fisher BP1760, "Ampicillin Sodium Salt"). Its
# dissolution (Na⁺ + the ampicillin anion) is registered in electrolytes.jl, and its acid/base chain in pKa_data.jl.
@reagent_product ampicillin_sodium "Sigma-Aldrich" catalog_number="A8351" product_name="Ampicillin Sodium Salt"
@reagent_product ampicillin_sodium "Fisher Scientific" catalog_number="BP1760" product_name="Ampicillin Sodium Salt"
@reagent arabinan "Arabinan" Solid opaque missing missing
# ^ Sigma-Aldrich AABH9BD89ECE-250MG (sugar-beet arabinan). Polydisperse polysaccharide, no PubChem
# CID/fixed MW exists -- registered for identity/inventory purposes only (same pattern as agar/
# dextrin/tryptone: a real, named lab reagent with no single-molecule MW to report).
@reagent_product arabinan "Sigma-Aldrich" catalog_number="AABH9BD89ECE" product_name="Arabinan from sugar beet"
@reagent arabinose "D-Arabinose" Solid "C5H10O5" missing 66308
# ^ fixed 2026-08-13: was incorrectly CID 188324 (D-Arabinose 5-phosphate, MW 230.11), a different,
# phosphorylated compound -- corrected to plain D-Arabinose (CID 66308) while registering l_arabinose
# alongside it.
@reagent_product arabinose "Sigma-Aldrich" catalog_number="10850" product_name="D(-)-ARABINOSE, FOR MICROBIOLOGY" notes="Manufacturer: Millipore"
@reagent arbutin "Arbutin" Solid "C12H16O7" missing 440936
@reagent_product arbutin "Fisher Scientific" catalog_number="AAL1494506" notes="Manufacturer: Thermo Scientific"
@reagent arginine "L-arginine" Solid "C6H14N4O2" missing 6322
@reagent_product arginine "Sigma-Aldrich" catalog_number="1015420100" product_name="L-ARGININE FOR BIOCHEMISTRY" notes="Manufacturer: Millipore"
@reagent ascorbate "L-Ascorbic Acid" Solid "C6H8O6" missing 54670067
@reagent_product ascorbate "Sigma-Aldrich" catalog_number="A92902" product_name="L-ASCORBIC ACID, 99%"
@reagent_product ascorbate "Fisher Scientific" catalog_number="AC352680050" notes="Manufacturer: Thermo Scientific"
@reagent asparagine "L-asparagine" Solid "C4H8N2O3" 1.543u"g/mL" 6267
@reagent_product asparagine "Sigma-Aldrich" catalog_number="A4159" product_name="L-ASPARAGINE SUITABLE FOR CELL CULTURE" notes="Product name is cut off in the stocklist"
@reagent aspartic_acid "L-aspartic acid" Solid "C4H7NO4" 1.6603u"g/mL" 5960
@reagent_product aspartic_acid "Sigma-Aldrich" catalog_number="A9256" product_name="L-ASPARTIC ACID, REAGENT GRADE, >=98%" notes="Product name is cut off in the stocklist"
@reagent b_nadp "β-NADP (β-nicotinamide adenine dinucleotide phosphate)" Solid "C21H28N7O17P3" missing 5885
# ^ corrected 2026-10-13: this was registered as b_nadph, NADPH, but it is NADP, the oxidized form. The
# lab's received list gives the vendor product "B-NICOTINAMIDE ADENINE DINUCLEOTIDE PHOS" (cut off by the
# order system) with formula C21H28N7O17P3, and CID 5885 is NADP. The ordering sheet planned catalog
# COMH042346F4, noted "tetra sodium hydrate"; the order and the received list show N5755. The lab calls it
# CoenzymeII (b-nadph).
@reagent_product b_nadp "Sigma-Aldrich" catalog_number="N5755" product_name="β-Nicotinamide adenine dinucleotide phosphate" notes="Manufactured by CombiBlocks. The product name is cut off in the order record."
@reagent beef_extract "Beef Extract" Solid opaque missing missing
@reagent_product beef_extract "Fisher Scientific" catalog_number="DF0115-17-3" product_name="Gibco™ Bacto™ Beef Extract, desiccated" manufacturer_number="BD Gibco 211520"
@reagent_product beef_extract "Gibco" catalog_number="4073205" product_name="Bacto Beef Extract, Desiccated"
@reagent beef_heart "Beef Heart" Solid opaque missing missing
@reagent benzamadine "benzamidine" Solid "C7H8N2" missing 2332
@species MethylBetaDGlucoside "Methyl-beta-D-glucopyranoside" 0 "C7H14O6" 445238
@reagent beta_methyl_d_glucoside_hemihydrate "Methyl-beta-D-glucopyranoside Hemihydrate" Solid (MethylBetaDGlucoside + 0.5*H2O) missing missing
# ^ Thermo/Acros AC270920250 is the hemihydrate, not anhydrous: one mole of the glucoside with half a mole
# of water (194.18 + 18.015/2 = 203.19). PubChem's own "hemihydrate"-titled CID (75487602, MW 212.20) is
# internally inconsistent -- its formula is actually a full monohydrate's, not a hemihydrate's -- confirmed
# against the clean 2:1 compound:water co-crystal entry (CID 2724704, MW 406.38 = 2x194.18+18.02).
# The glucoside species carries the anhydrous parent's CID (445238); no PubChem CID accurately represents
# the hemihydrate on its own, and the reagent has none.
@reagent_product beta_methyl_d_glucoside_hemihydrate "Fisher Scientific" catalog_number="AC270920250" product_name="Methyl-beta-D-glucopyranoside hemihydrate" notes="Thermo Scientific (Acros Organics)"
@reagent bhi "Brain Heart Infusion Broth" Solid opaque missing missing
@reagent_product bhi "Fisher Scientific" catalog_number="DF0037-17-8" product_name="BD Difco™ Bacto™ Brain Heart Infusion Broth" manufacturer_number="BD 237200"
@reagent biotin "biotin" Solid "C10H16N2O3S" missing 171548
@reagent_product biotin "Sigma-Aldrich" catalog_number="8512090001" product_name="D(+)-Biotin Novabiochem®" notes="Manufacturer: Novabiochem"
@species BleomycinA2⁺ "Bleomycin A2(cation)" 1 "C55H84N17O21S3" 5460769
@reagent bleomycin "bleomycin sulfate" Solid (BleomycinA2⁺ + HSO4⁻) missing missing
# ^ modeled on Sigma BP971, the British Pharmacopoeia reference standard for bleomycin sulfate (CAS 9041-93-4).
# The product is a mixture of bleomycin A2 and B2. It is modeled as the A2 salt, the A2 cation plus hydrogen
# sulfate, C55H85N17O25S4 at 1512.6 g/mol, which is the formula and molar mass that vendors give for
# bleomycin sulfate; BP971 itself states neither. The B2 component is not modeled. This was opaque at 1415.6
# g/mol, the cation's mass without its counter-ion, with CID 5360373, which has the same formula as A2's
# record but a general name. No AcidBaseSystem: the pH of a bleomycin sulfate solution is not modeled.
@reagent_product bleomycin "Sigma-Aldrich" catalog_number="BP971" product_name="Bleomycin sulfate, British Pharmacopoeia reference standard" grade="British Pharmacopoeia reference standard" notes="100 mg lyophilized powder. From the ordering sheet, whose 25 g size does not match the 100 mg unit."
@reagent boric_acid "Boric Acid" Solid "BH3O3" 1.435u"g/mL" 7628
@reagent_product boric_acid "Sigma-Aldrich" catalog_number="B0252" product_name="BORIC ACID, REAGENTPLUS TM, 99.5%"
@reagent sodium_butyrate "Sodium Butyrate" Solid 110.09u"g/mol" missing missing
@reagent_product sodium_butyrate "Sigma-Aldrich" catalog_number="303410" product_name="Butyric acid, sodium salt" grade="98%"
@reagent calcium_chloride_dihydrate "calcium chloride dihydrate" Solid (Ca²⁺+2*Cl⁻+2*H2O) 1.85u"g/mL" missing  # dihydrate
@reagent_product calcium_chloride_dihydrate "Fisher Scientific" catalog_number="BP510-250" product_name="Calcium Chloride Dihydrate (White Crystals to Powder), Fisher BioReagents™"
@reagent_product calcium_chloride_dihydrate "Sigma-Aldrich" catalog_number="C3306" product_name="CALCIUM CHLORIDE DIHYDRATE"
@reagent calcium_l_threonate "Calcium L-threonate" Solid "C8H14CaO10" missing 13388558
@reagent carbenicillin "carbenicillin" Solid "C17H18N2O6S" missing 20824
@reagent carnitine_hydrochloride "DL-carnitine hydrochloride" Solid missing missing missing
# ^ was carnitine, the free zwitterion, until 2026-10-13: the lab bought DL-carnitine hydrochloride. Its dissolution is in electrolytes.jl.
@reagent_product carnitine_hydrochloride "Sigma-Aldrich" catalog_number="C9500" product_name="DL-CARNITINE HYDROCHLORIDE"
@reagent ceftriaxone "ceftriaxone" Solid "C18H18N8O7S3" missing 5479530
@reagent cellobiose "cellobiose" Solid "C12H22O11" missing 294
@reagent_product cellobiose "Sigma-Aldrich" catalog_number="22150" product_name="D-(+)-Cellobiose"
@reagent_product cellobiose "Fisher Scientific" catalog_number="AC108460050" notes="Manufacturer: Thermo Scientific"
@reagent cellulose_triacetate "Cellulose Triacetate" Solid opaque missing missing
# ^ Thermo Scientific/Acros AC177822500 (CAS 9012-09-3, repeat unit (C24H32O16)n) -- lab_id/name
# reflect the actual product on the shelf, not plain cellulose. Polymer, no PubChem CID/fixed MW;
# no Dissolution/AcidBaseSystem (same non-discrete-material treatment as arabinan/
# hydrolyzed_mucin below).
@reagent_product cellulose_triacetate "Thermo Scientific" catalog_number="AC177822500" notes="Acros Organics, CAS 9012-09-3"
@reagent chloramphenicol "chloramphenicol" Solid "C11H12Cl2N2O5" missing 5959
@reagent chlortetracycline "chlortetracycline" Solid 515.3u"g/mol" missing missing
@reagent choline_chloride "Choline Chloride" Solid (Choline⁺ + Cl⁻) missing missing
# ^ Sigma C7527 choline chloride (139.62 g/mol). The choline cation is `Choline⁺` (ions.jl, CID 305).
@reagent_product choline_chloride "Sigma-Aldrich" catalog_number="C7527" product_name="Choline chloride, suitable for cell culture" grade=">98%"
@reagent ciprofloxacin "ciprofloxacin" Solid "C17H18FN3O3" missing 2764
@reagent citric_acid "Citric Acid" Solid "C6H8O7" 1.54u"g/mL" 311
@reagent_product citric_acid "Sigma-Aldrich" catalog_number="27109" product_name="CITRIC ACID ANHYDROUS"
@reagent citruline "L-citruline" Solid "C6H13N3O3" missing 9750
@reagent_product citruline "Sigma-Aldrich" catalog_number="C7629" product_name="L-CITRULLINE"
@reagent cobalt_chloride_hexahydrate "Cobalt (II) Chloride Hexahydrate" Solid (Co²⁺+2*Cl⁻+6*H2O) 1.924u"g/mL" missing  # hexahydrate
# ^ fixed 2026-08-14: was registered anhydrous (CID 3032536, real anhydrous density ~3.35 g/mL) but
# the stored density (1.924) actually matches the hexahydrate's -- corrected to the hexahydrate CID
# (24643); molecular_weight derives from the Dissolution (electrolytes.jl), now including 6 H2O.
@reagent_product cobalt_chloride_hexahydrate "Sigma-Aldrich" catalog_number="202185" product_name="COBALT(II) CHLORIDE HEXAHYDRATE, REAGEN" notes="Product name is cut off in the stocklist"
@reagent cobalt_nitrate_hexahydrate "Cobalt (II) Nitrate Hexahydrate" Solid (Co²⁺+2*NO3⁻+6*H2O) 1.88u"g/mL" missing  # hexahydrate
# ^ fixed 2026-08-14: was registered anhydrous (CID 25000, density 1.54 -- neither the anhydrous
# nor hexahydrate reference density) -- corrected to hexahydrate (CID 24821, density 1.88) per the
# lab's own purchase record (Sigma 230375-100G, "COBALT(II) NITRATE HEXAHYDRATE, 98%").
# molecular_weight derives from the Dissolution (electrolytes.jl), now including 6 H2O.
@reagent_product cobalt_nitrate_hexahydrate "Sigma-Aldrich" catalog_number="230375" product_name="Cobalt(II) nitrate hexahydrate" grade="98%"
@reagent colistin "colistin" Solid "C52H98N16O13" missing 5311054
@reagent copper_chloride_dihydrate "Copper (II) Chloride Dihydrate" Solid (Cu²⁺+2*Cl⁻+2*H2O) 2.54u"g/mL" missing  # dihydrate
# ^ fixed 2026-08-14: was registered anhydrous (CID 24014, real anhydrous density ~3.4 g/mL) but the
# stored density (2.54) actually matches the dihydrate's -- corrected to the dihydrate CID (61482);
# molecular_weight derives from the Dissolution (electrolytes.jl), now including 2 H2O.
@reagent_product copper_chloride_dihydrate "Sigma-Aldrich" catalog_number="221783" product_name="COPPER(II) CHLORIDE DIHYDRATE, REAGENT" notes="Product name is cut off in the stocklist"
@reagent copper_sulfate_pentahydrate "Copper (II) Sulfate Pentahydrate" Solid (Cu²⁺+SO4²⁻+5*H2O) 2.29u"g/mL" missing  # pentahydrate
# ^ fixed 2026-08-14: was registered anhydrous (CID 24462, real anhydrous density ~3.6 g/mL) but the
# stored density (2.29) actually matches the pentahydrate's -- corrected to the pentahydrate CID
# (24463); molecular_weight derives from the Dissolution (electrolytes.jl), now including 5 H2O.
@reagent_product copper_sulfate_pentahydrate "Sigma-Aldrich" catalog_number="C7631" product_name="COPPER(II) SULFATE PENTAHYDRATE, REAGENT" notes="Product name is cut off in the stocklist"
@reagent cyclohexamide "cycloheximide" Solid "C15H23NO4" missing 6197
@reagent cycloserine "cycloserine" Solid "C3H6N2O2" missing 6234
@reagent cysteine "L-Cysteine hydrochloride monohydrate" Solid missing missing missing
@reagent_product cysteine "Thermo Fisher Scientific" catalog_number="BP376" product_name="L-Cysteine hydrochloride monohydrate"
@reagent_product cysteine "Sigma-Aldrich" catalog_number="C121800" product_name="L-CYSTEINE HYDROCHLORIDE HYDRATE, 99%" notes="Manufacturer: Millipore"
@reagent cystine "L-cystine" Solid "C6H12N2O4S2" missing 67678
@reagent cytosine "cytosine" Solid "C4H5N3O" missing 597
@reagent_product cytosine "Sigma-Aldrich" catalog_number="C3506" product_name="CYTOSINE"
@reagent d_alanine "D-Alanine" Solid "C3H7NO2" missing 71080
# ^ distinct from the existing alanine (DL, CID 602) and l_alanine (CID 5950) -- same formula/MW
# as its stereoisomers, but no density data on PubChem for this specific CID (not assumed to match
# l_alanine's 1.432 g/mL just because enantiomers share physical properties -- no per-CID citation).
@reagent_product d_alanine "Fisher Scientific" catalog_number="A10231.14" product_name="D-Alanine" grade="99%"
@reagent d_arabitol "D-Arabitol" Solid "C5H12O5" missing 94154
@reagent_product d_arabitol "Fisher Scientific" catalog_number="AC302870050" notes="Manufacturer: Thermo Scientific"
@reagent d_galactarate "D-Galactaric Acid (Mucic Acid)" Solid "C6H10O8" missing 3037582
@reagent_product d_galactarate "Fisher Scientific" catalog_number="AAB2417022" notes="Manufacturer: Thermo Scientific"
@reagent d_galactonate "Calcium D-Galactonate Monohydrate" Solid "C12H24CaO15" missing 129700926
# ^ eMolecules 50-222-8418 is "listed as calcium d-galactonate hydrate" -- CID 129700926's formula
# (C12H24CaO15, 448.39) is exactly the anhydrous salt (C12H22CaO14, 430.37) plus one H2O, i.e. a
# monohydrate.
@reagent_product d_galactonate "Fisher Scientific" catalog_number="50-222-8418" notes="Manufacturer: eMolecules"
@reagent d_galacturonate "D-Galacturonic Acid Monohydrate" Solid "C6H12O8" missing 44654794
# ^ Thermo AAJ6628206 is "listed as d-galacturonic acid monohydrate" -- CID 44654794 (212.15 =
# 194.14 + 18.015) is the dedicated monohydrate entry.
@reagent_product d_galacturonate "Fisher Scientific" catalog_number="AAJ6628206" notes="Manufacturer: Thermo Scientific"
@reagent d_glucarate "Calcium D-Glucarate Tetrahydrate (Calcium Saccharate)" Solid "C6H16CaO12" missing 11954337
# ^ Thermo AAJ6694714 is "listed as calcium D-saccharate tetrahydrate" -- CID 11954337 (320.26 =
# 248.20 + 4x18.015) is the dedicated tetrahydrate entry.
@reagent_product d_glucarate "Fisher Scientific" catalog_number="AAJ6694714" notes="Manufacturer: Thermo Scientific"
@reagent d_gluconate "Potassium D-Gluconate" Solid "C6H11KO7" missing 16760467
@reagent_product d_gluconate "Fisher Scientific" catalog_number="AAB2513518" notes="Manufacturer: Thermo Scientific"
@reagent d_glucosamine "D-Glucosamine Hydrochloride" Solid "C6H14ClNO5" missing 91431
@reagent_product d_glucosamine "Fisher Scientific" catalog_number="AAA1553218" notes="Manufacturer: Thermo Scientific"
@reagent d_glucuronate "D-Glucuronic Acid" Solid "C6H10O7" missing 94715
@reagent_product d_glucuronate "Fisher Scientific" catalog_number="AC309880100" notes="Manufacturer: Thermo Scientific"
@reagent d_malic_acid "D-Malic Acid" Solid "C4H6O5" missing 92824
@reagent d_psicose "D-Psicose" Solid "C6H12O6" missing 441036
@reagent d_ribose "D-Ribose" Solid "C5H10O5" missing 10975657
@reagent_product d_ribose "Fisher Scientific" catalog_number="AC132360050" notes="Manufacturer: Thermo Scientific"
@reagent d_serine "D-Serine" Solid "C3H7NO3" missing 71077
@reagent d_tagatose "D-Tagatose" Solid "C6H12O6" missing 439312
@reagent_product d_tagatose "Fisher Scientific" catalog_number="50-291-6585" notes="Manufacturer: Cayman Chemical"
@reagent dextrin "dextrin from corn" Solid "C18H32O16" missing 62698
@reagent dihydroxyacetone "Dihydroxyacetone" Solid "C3H6O3" missing 670
@reagent_product dihydroxyacetone "Fisher Scientific" catalog_number="AAA1418918" notes="Manufacturer: Thermo Scientific"
@reagent doxycycline "doxycycline" Solid 480.9u"g/mol" missing missing
@reagent dulcitol "Dulcitol (Galactitol)" Solid "C6H14O6" missing 11850
@reagent ectoine "Ectoine" Solid "C6H10N2O2" missing 126041
@reagent_product ectoine "Sigma-Aldrich" catalog_number="81619" product_name="ECTOIN"
@reagent edta "EDTA" Solid "C10H16N2O8" 0.86u"g/mL" 6049
@reagent_product edta "Sigma-Aldrich" catalog_number="EDS" product_name="ETHYLENEDIAMINETETRAACETIC ACID FREE ACI" notes="Product name is cut off in the stocklist"
@reagent erythromycin "erythromycin" Solid "C37H67NO13" missing 12560
@reagent folic_acid "folic acid" Solid "C19H19N7O6" missing 135398658
@reagent_product folic_acid "Sigma-Aldrich" catalog_number="F8758" product_name="FOLIC ACID, BIOREAGENT, SUITABLE FOR" notes="Product name is cut off in the stocklist"
@reagent formamide "Formamide" Solid "CH3NO" 1.1334u"g/mL" 713
@reagent_product formamide "Sigma-Aldrich" catalog_number="F7503" product_name="FORMAMIDE, REAGENTPLUS®, >=99.0% (GC)" notes="Product name is cut off in the stocklist"
@reagent fructose "D-(-)-fructose" Solid "C6H12O6" missing 5984
@reagent_product fructose "Sigma-Aldrich" catalog_number="F3510" product_name="D(-)FRUCTOSE CELL CULTURE TESTED"
@reagent fusaric_acid "fusaric_acid" Solid "C10H13NO2" missing 3442
@reagent fusidic_acid "fusidic_acid" Solid "C31H48O6" missing 3000226
@reagent galactose "D-galactose" Solid "C6H12O6" missing 6036
@reagent gentamicin "gentamicin" Solid "C21H43N5O7" missing 3467
@reagent gifu_anaerobic_broth "Gifu Anaerobic Broth, Modified (GAM)" Solid opaque missing missing
@reagent_product gifu_anaerobic_broth "Fisher Scientific" catalog_number="NC1649821" product_name="HIMEDIA GIFU ANAEROBIC BROTH MDFID RX" manufacturer_number="HIMEDIA M2079500G"
@reagent glcnac "GlcNAc" Solid "C8H15NO6" missing 439174
@reagent_product glcnac "Sigma-Aldrich" catalog_number="A3286" product_name="N-ACETYL-D-GLUCOSAMINE BIOREAG" notes="Product name is cut off in the stocklist"
@reagent glucose "D-glucose" Solid "C6H12O6" 1.2u"g/mL" 5793
@reagent_product glucose "Fisher Scientific" catalog_number="BP350500" product_name="Dextrose Anhydrous (Crystalline Granules/Molecular Biology), Fisher BioReagents"
@reagent_product glucose "Sigma-Aldrich" catalog_number="G7021" product_name="D-(+)-GLUCOSE, POWDER, BIOREAGENT, SUITA" notes="Product name is cut off in the stocklist"
@reagent glutamic_acid "L-glutamic_acid" Solid "C5H9NO4" 1.538u"g/mL" 33032
@reagent_product glutamic_acid "Sigma-Aldrich" catalog_number="G1251" product_name="L-GLUTAMIC ACID, REAGENTPLUS™, >=99%" notes="Product name is cut off in the stocklist"
@reagent glutamine "L-glutamine" Solid "C5H10N2O3" 1.364u"g/mL" 5961
# ^ note 2026-08-14: the lab's actual stocklist (Reagent_StockList.xlsx) shows l-glutamine purchased
# both as this solid (Sigma G3126-100G) and as Gibco's 200mM aqueous solution (25-030-081) -- this
# reagent correctly represents the solid form; a Stock built from the Gibco bottle should be dosed
# as a solution (by volume/molarity), not by weighing this reagent. Same situation as sodium_pyruvate
# below (see its own comment).
@reagent_product glutamine "Sigma-Aldrich" catalog_number="G3126" product_name="L-Glutamine, ReagentPlus" grade="≥99%"
@reagent glutathione "L-Glutathione (reduced)" Solid "C10H17N3O6S" missing 124886
@reagent glycine "glycine" Solid "C2H5NO2" 1.1607u"g/mL" 750
@reagent_product glycine "Sigma-Aldrich" catalog_number="G7126" product_name="GLYCINE, REAGENTPLUS™, >= 99% (HPLC)" notes="Product name is cut off in the stocklist"
@reagent guanidine "guanidine" Solid "CH5N3" missing 3520
@reagent guanine "guanine hydrochloride" Solid "C5H6ClN5O" missing 135436483
@reagent_product guanine "Sigma-Aldrich" catalog_number="51030" product_name="GUANINE HYDROCHLORIDE, >= 99.0 %"
@reagent guanosine "guanosine" Solid "C10H13N5O5" missing 135398635
@reagent_product guanosine "Sigma-Aldrich" catalog_number="G6752" product_name="GUANOSINE"
@reagent histidine "L-histidine" Solid "C6H9N3O2" missing 6274
@reagent_product histidine "Sigma-Aldrich" catalog_number="H8000" product_name="L-HISTIDINE, REAGENTPLUS TM, >= 99%"
@reagent hs_com "2-Mercaptoethanesulfonate Sodium Salt (Coenzyme M)" Solid "C2H5NaO3S2" missing 23662354
# ^ PubChem's canonical entry for this compound is titled "Mesna" (its pharmaceutical name), CID
# 23662354, the anhydrous sodium salt -- a monohydrate exists commercially under a different CAS but
# isn't what's registered here (no catalog number on hand to confirm). No density data on PubChem.
# No AcidBaseSystem: the sulfonate is a strong acid (always ionized, same as other strong-acid
# conjugate bases here); the only thiol pKa's found (7.4, 9.2) are enzyme-active-site-bound values
# from CoM-transferase studies, not the free compound in solution, so not used here.
@reagent hydrolyzed_mucin "Mucin from porcine stomach (Type III)" Solid opaque missing missing
# ^ Sigma M1778 (CAS 84082-64-4), bound sialic acid 0.5-1.5%, partially purified powder. A
# heterogeneous glycoprotein (monomer ~640 kDa, polymeric mucin ~4000-5500 kDa) -- no PubChem
# CID/fixed MW; registered for identity/inventory purposes only, same as arabinan above.
@reagent_product hydrolyzed_mucin "Sigma-Aldrich" catalog_number="M1778" notes="CAS 84082-64-4"
@reagent hypoxanthine "Hypoxanthine" Solid "C5H4N4O" missing 135398638
@reagent inosine "inosine" Solid "C10H12N4O5" missing 135398641
@reagent_product inosine "Sigma-Aldrich" catalog_number="I4125" product_name="INOSINE, >=99% (HPLC)" notes="Manufacturer: ChemImpex"
@reagent iron_chloride "Iron Chloride (Ferric Chloride)" Solid (Fe³⁺+3*Cl⁻) 2.8u"g/mL" missing
# ^ checked 2026-08-14: not in the lab stocklist, but its stored density matches the anhydrous reference value
# cleanly, unlike the hydrates fixed in this file -- confirmed anhydrous.
@reagent iron_nitrate_nonahydrate "iron (III) nitrate nonahydrate" Solid (Fe³⁺+3*NO3⁻+9*H2O) 1.68u"g/mL" missing  # nonahydrate
@reagent_product iron_nitrate_nonahydrate "Sigma-Aldrich" catalog_number="F8508" product_name="FERRIC NITRATE NONAHYDRATE CELL CULTURE" notes="Product name is cut off in the stocklist"
@reagent iron_sulfate_heptahydrate "iron (II) sulfate heptahydrate" Solid (Fe²⁺+SO4²⁻+7*H2O) 1.895u"g/mL" missing  # heptahydrate
@reagent_product iron_sulfate_heptahydrate "Sigma-Aldrich" catalog_number="F7002" product_name="IRON(II) SULFATE HEPTAHYDRATE, REAGENTP" notes="Product name is cut off in the stocklist"
@reagent isoleucine "L-isoleucine" Solid "C6H13NO2" missing 6306
@reagent_product isoleucine "Sigma-Aldrich" catalog_number="I2752" product_name="L-ISOLEUCINE, REAGENT GRADE, >=98% (HPLC" notes="Product name is cut off in the stocklist"
@reagent kanamycin "kanamycin" Solid "C18H36N4O11" missing 6032
@reagent l_alanine "L-Alanine" Solid "C3H7NO2" 1.432u"g/mL" 5950
@reagent_product l_alanine "Fisher Scientific" catalog_number="A15804.14" product_name="L-Alanine" grade="99%"
@reagent_product l_alanine "Sigma-Aldrich" catalog_number="A7469" product_name="L-ALANINE, FROM NON-ANIMAL SOURCE, MEET" notes="Product name is cut off in the stocklist"
@reagent l_arabinose "L-Arabinose" Solid "C5H10O5" missing 439195
@reagent l_fucose "L-Fucose" Solid "C6H12O5" missing 17106
@reagent l_lyxose "L-Lyxose" Solid "C5H10O5" missing 644176
@reagent l_malic_acid "L-Malic Acid" Solid "C4H6O5" missing 222656
@reagent_product l_malic_acid "Fisher Scientific" catalog_number="ICN218073" notes="Manufacturer: MP Biomedicals"
@reagent l_sorbose "L-Sorbose" Solid "C6H12O6" missing 439192
@reagent_product l_sorbose "Fisher Scientific" catalog_number="AC225961000" notes="Manufacturer: Thermo Scientific"
@species Lactose "Lactose" 0 "C12H22O11" 6134
@reagent lactose_monohydrate "D-lactose monohydrate" Solid (Lactose+H2O) missing missing
# ^ was lactose, the anhydrous sugar, until 2026-10-13: the lab bought the monohydrate.
@reagent_product lactose_monohydrate "Sigma-Aldrich" catalog_number="61341" product_name="D-Lactose monohydrate, tested according to Ph. Eur." notes="Replaced the ordered 61345 (D-LACTOSE MONOHYDRATE >= 98.0% (HPLC)), per the stocklist follow-up sheet"
@reagent lactulose "Lactulose" Solid "C12H22O11" missing 11333
@reagent lb "LB Broth" Solid opaque missing missing
@reagent_product lb "Fisher Scientific" catalog_number="DF0446-17-3" product_name="BD Difco™ Dehydrated Culture Media: LB Broth, Miller (Luria-Bertani)" manufacturer_number="BD244620"
@reagent leucine "L-leucine" Solid "C6H13NO2" 1.293u"g/mL" 6106
@reagent_product leucine "Sigma-Aldrich" catalog_number="L8000" product_name="L-LEUCINE, REAGENT GRADE, >=98% (HPLC)" notes="Product name is cut off in the stocklist"
@reagent lincomycin "lincomycin" Solid "C18H34N2O6S" missing 3000540
@reagent lipoic_acid "lipoic_acid" Solid "C8H14O2S2" missing 6112
@reagent_product lipoic_acid "Sigma-Aldrich" catalog_number="62320" product_name="DL-ALPHA-LIPOIC ACID"
@reagent lysine "L-Lysine monohydrochloride" Solid missing missing missing
@reagent_product lysine "Sigma-Aldrich" catalog_number="L5626" product_name="L-Lysine monohydrochloride" grade=">98%"
@reagent magnesium_sulfate_heptahydrate "magnesium sulfate heptahydrate" Solid (Mg²⁺+SO4²⁻+7*H2O) 1.68u"g/mL" missing  # heptahydrate
@reagent_product magnesium_sulfate_heptahydrate "Sigma-Aldrich" catalog_number="M1880" product_name="MAGNESIUM SULFATE HEPTAHYDRATE, REAGENTP" notes="Product name is cut off in the stocklist"
@reagent magnesium_sulfate_anhydrous "magnesium sulfate anhydrous" Solid (Mg²⁺+SO4²⁻) missing missing
@reagent_product magnesium_sulfate_anhydrous "Fisher Scientific" catalog_number="AA3333736" product_name="Magnesium sulfate, anhydrous, 99.5% min" manufacturer_number="Thermo 03333736"
@reagent malic_acid "Malic Acid" Solid "C4H6O5" 1.601u"g/mL" 525
@reagent_product malic_acid "Sigma-Aldrich" catalog_number="240176" product_name="DL-MALIC ACID"
@reagent maltodextrin "maltodextrin" Solid opaque missing missing
@reagent_product maltodextrin "Sigma-Aldrich" catalog_number="419672" product_name="MALTODEXTRIN, DEXTROSE EQUIVALENT 4.0-7" notes="Product name is cut off in the stocklist"
@reagent maltose "Maltose" Solid "C12H22O11" missing 439186
@reagent manganese_chloride_tetrahydrate "Manganese (II) Chloride Tetrahydrate" Solid (Mn²⁺+2*Cl⁻+4*H2O) 2.01u"g/mL" missing  # tetrahydrate
@reagent_product manganese_chloride_tetrahydrate "Sigma-Aldrich" catalog_number="M3634" product_name="MANGANESE(II) CHLORIDE TETRAHYDRATE"
@reagent manganese_sulfate_monohydrate "manganese sulfate monohydrate" Solid (Mn²⁺+SO4²⁻+H2O) 2.95u"g/mL" missing  # monohydrate
@reagent_product manganese_sulfate_monohydrate "Sigma-Aldrich" catalog_number="M7634" product_name="MANGANESE(II) SULFATE MONOHYDRATE, REAG" notes="Product name is cut off in the stocklist"
@reagent mannitol "D-mannitol" Solid "C6H14O6" 1.489u"g/mL" 6251
@reagent_product mannitol "Sigma-Aldrich" catalog_number="M4125" product_name="D-MANNITOL"
@reagent mannose "D-mannose" Solid "C6H12O6" missing 18950
@reagent_product mannose "Sigma-Aldrich" catalog_number="M6020" product_name="D-(+)-MANNOSE BIOREAGENT, SUITABLE FOR" notes="Product name is cut off in the stocklist"
@reagent marine_broth "Marine Broth" Solid opaque missing missing
@reagent_product marine_broth "Fisher Scientific" catalog_number="DF0791-17-4" product_name="BD Difco™ Dehydrated Culture Media: Marine Broth 2216" manufacturer_number="BD 279110"
@reagent melibiose "melibiose" Solid "C12H22O11" missing 11458
@reagent_product melibiose "Sigma-Aldrich" catalog_number="63630" product_name="D-(+)-MELIBIOSE" notes="Manufacturer: Millipore"
@reagent methionine "L-methionine" Solid "C5H11NO2S" 1.178u"g/mL" 6137
@reagent_product methionine "Sigma-Aldrich" catalog_number="M9625" product_name="L-METHIONINE, REAGENT GRADE, >=98% (HPLC" notes="Product name is cut off in the stocklist"
@reagent middlebrook_7h9_broth "Middlebrook 7H9 Broth Base" Solid opaque missing missing
@reagent_product middlebrook_7h9_broth "Fisher Scientific" catalog_number="DF0713-17-9" product_name="BD Difco™ Dehydrated Culture Media: Middlebrook 7H9 Broth" manufacturer_number="BD 271310"
@reagent miltefosine "miltefosine" Solid "C21H46NO4P" missing 3599
@reagent minocycline "minocycline hydrochloride" Solid 493.9u"g/mol" missing missing
@reagent mrs_broth "MRS broth" Solid opaque missing missing
@reagent_product mrs_broth "Sigma-Aldrich" catalog_number="69966" product_name="MRS Broth" notes="Manufacturer: Millipore"
@reagent mops "MOPS" Solid "C7H15NO4S" missing 70807
@reagent mucin_type_ii "Mucin from porcine stomach (Type II)" Solid opaque missing missing
# ^ Partially purified porcine gastric mucin; a different product from hydrolyzed_mucin.
# Heterogeneous glycoprotein with no PubChem CID/fixed MW; registered for
# identity/inventory purposes only, same as hydrolyzed_mucin.
@reagent_product mucin_type_ii "Sigma-Aldrich" catalog_number="M2378" product_name="Mucin from porcine stomach Type II"
@reagent myo_inositol "myo-inositol" Solid "C6H12O6" missing 892
@reagent_product myo_inositol "Sigma-Aldrich" catalog_number="I7508" product_name="MYO-INOSITOL, BIOREAGENT, SUITABLE FOR" notes="Manufacturer: Millipore; Product name is cut off in the stocklist"
@reagent n_acetylgalactosamine "N-Acetyl-D-Galactosamine" Solid "C8H15NO6" missing 35717
@reagent_product n_acetylgalactosamine "Fisher Scientific" catalog_number="AAJ6609506" notes="Manufacturer: Thermo Scientific"
@reagent n_acetylneuraminate "N-Acetylneuraminic Acid" Solid "C11H19NO9" missing 439197
@reagent_product n_acetylneuraminate "Sigma-Aldrich" catalog_number="1101381GM" notes="Manufacturer: MilliporeSigma"
@reagent neomycin "neomycin" Solid "C23H46N6O13" missing 8378
# ^ fixed 2026-10-12: was CID 8738 (butyl lactate, C7H14O3), a transposed-digit typo, with butyl lactate's
# density (0.98) -- corrected to neomycin (CID 8378). The formula is the free base. The salt form of the
# product bought was not checked, so a sulfate would need a Dissolution.
@reagent niacinamide "niacinamide (nicotinamide)" Solid "C6H6N2O" 1.4u"g/mL" 936
@reagent_product niacinamide "Sigma-Aldrich" catalog_number="N0636" product_name="NICOTINAMIDE SUITABLE FOR CELL CULTURE" notes="Product name is cut off in the stocklist"
@reagent nickel_chloride "Nickel (II) Chloride" Solid (Ni²⁺+2*Cl⁻) 3.55u"g/mL" missing
# ^ checked 2026-08-14 against the lab stocklist (Reagent_StockList.xlsx): Sigma N6136-100G "anhydrous".
@reagent_product nickel_chloride "Sigma-Aldrich" catalog_number="N6136" product_name="Nickel chloride, cell culture tested"
@reagent nutrient_broth "Nutrient Broth" Solid opaque missing missing
@reagent_product nutrient_broth "Fisher Scientific" catalog_number="DF0003-17-8" product_name="BD Difco™ Nutrient Broth" manufacturer_number="BD 234000"
@reagent ofloxacin "ofloxacin" Solid "C18H20FN3O4" missing 4583
@reagent ornithine_hydrochloride "L-ornithine hydrochloride" Solid missing missing missing
# ^ was ornithine, the free base, until 2026-10-13: the lab bought L-ornithine hydrochloride. Its dissolution is in electrolytes.jl.
@reagent_product ornithine_hydrochloride "Sigma-Aldrich" catalog_number="W419001" product_name="L-ORNITHINE HYDROCHLORIDE, 99%"
@reagent oxacillin "oxacillin" Solid "C19H19N3O5S" missing 6196
@reagent oxalic_acid "Oxalic Acid" Solid "C2H2O4" 1.9u"g/mL" 971
@reagent_product oxalic_acid "Sigma-Aldrich" catalog_number="75688" product_name="OXALIC ACID ANHYDROUS"
@reagent paba "4-aminobenzoic acid" Solid "C7H7NO2" 1.37u"g/mL" 978
@reagent_product paba "Sigma-Aldrich" catalog_number="A9878" product_name="4-AMINOBENZOIC ACID, REAGENTPLUS®, >=9" notes="Product name is cut off in the stocklist"
@reagent palatinose "Palatinose (Isomaltulose)" Solid "C12H22O11" missing 83686
@reagent_product palatinose "Fisher Scientific" catalog_number="AAJ6009114" notes="Manufacturer: Thermo Scientific"
@reagent pantothenate "calcium pantothenate" Solid "C18H32CaN2O10" missing 443753
@reagent_product pantothenate "Sigma-Aldrich" catalog_number="21210" product_name="D-PANTOTHENIC ACID CALCIUM SALT"
@reagent paromomycin "paromomycin" Solid "C23H45N5O14" missing 165580
@reagent penicillin_g "penicillin_g" Solid "C16H18N2O4S" missing 5904
@reagent peptone "Peptone" Solid opaque missing missing
@reagent phenylalanine "L-phenylalanine" Solid "C9H11NO2" missing 6140
@reagent_product phenylalanine "Sigma-Aldrich" catalog_number="P2126" product_name="L-PHENYLALANINE"
@reagent polymyxin_b "polymyxin_b" Solid "C56H100N16O17S" missing 5702105
@reagent potassium_aluminum_sulfate_dodecahydrate "Potassium Aluminum Sulfate Dodecahydrate" Solid (K⁺+Al³⁺+2*SO4²⁻+12*H2O) 1.725u"g/mL" missing  # dodecahydrate
# ^ fixed 2026-08-14: was registered anhydrous (CID 24856), but the stored density (1.725) is
# PubChem's own dodecahydrate-labeled value, and potassium alum is essentially never sold anhydrous
# -- corrected to the dodecahydrate CID (62667); molecular_weight derives from the Dissolution
# (electrolytes.jl), now including 12 H2O.
@reagent_product potassium_aluminum_sulfate_dodecahydrate "Sigma-Aldrich" catalog_number="237086" product_name="ALUMINUM POTASSIUM SULFATE DODECAHYDRATE" notes="Product name is cut off in the stocklist"
@reagent potassium_chloride "Potassium Chloride" Solid (K⁺+Cl⁻) 1.984u"g/mL" missing
@reagent potassium_phosphate_di "potassium phosphate dibasic" Solid (2*K⁺+HPO4²⁻) missing missing
@reagent_product potassium_phosphate_di "Sigma-Aldrich" catalog_number="P3786" product_name="POTASSIUM PHOSPHATE DIBASIC, ACS REAGENT" notes="Product name is cut off in the stocklist"
@reagent potassium_phosphate_mono "potassium phosphate monobasic" Solid (K⁺+H2PO4⁻) 2.34u"g/mL" missing
@reagent_product potassium_phosphate_mono "Fisher Scientific" catalog_number="P285-500" product_name="Potassium Phosphate Monobasic (Crystalline/Certified ACS), Fisher Chemical™"
@reagent proline "L-proline" Solid "C5H9NO2" 1.064u"g/mL" 145742
@reagent_product proline "Sigma-Aldrich" catalog_number="P0380" product_name="L-PROLINE, REAGENTPLUS™, >=99% (HPLC" notes="Product name is cut off in the stocklist"
@reagent promethazine "promethazine" Solid "C17H20N2S" missing 4927
@reagent putrescine "Putrescine" Solid "C4H12N2" 0.877u"g/mL" 1045
@reagent_product putrescine "Fisher Scientific" catalog_number="ICN10044105" notes="Manufacturer: MP Biomedicals"
@reagent pyridoxal "pyridoxal hydrochloride" Solid "C8H10ClNO3" missing 6171
@reagent_product pyridoxal "Sigma-Aldrich" catalog_number="93759" product_name="PYRIDOXAL HYDROCHLORIDE"
@reagent pyridoxamine "pyridoxamine dihydrochloride" Solid "C8H14Cl2N2O2" missing 10664
@reagent_product pyridoxamine "Sigma-Aldrich" catalog_number="P9380" product_name="PYRIDOXAMINE DIHYDROCHLORIDE"
@reagent sodium_propionate "sodium propionate" Solid missing missing missing
# ^ was propionic_acid until 2026-10-13: the lab bought sodium propionate, not the acid. Its dissolution is in electrolytes.jl.
@reagent_product sodium_propionate "Sigma-Aldrich" catalog_number="P1880" product_name="SODIUM PROPIONATE"
@reagent sodium_pyruvate "Sodium Pyruvate" Solid 110.04u"g/mol" missing missing
@reagent_product sodium_pyruvate "Sigma-Aldrich" catalog_number="P5280" product_name="Pyruvic acid sodium, cell culture tested"
@species Raffinose "Raffinose" 0 "C18H32O16" 439242
@reagent raffinose_pentahydrate "raffinose pentahydrate" Solid (Raffinose+5*H2O) missing missing
# ^ was raffinose, the anhydrous sugar, until 2026-10-13: the lab bought the pentahydrate (Sigma). No product is
# registered yet: the stocklist gives catalog S8625 for it, which is Sigma's sodium acetate trihydrate.
@species ResazurinAnion "Resazurin(anion)" -1 "C12H6NO4" 3800213
@reagent resazurin_sodium "resazurin sodium salt" Solid (Na⁺+ResazurinAnion) missing missing
# ^ was resazurin, the neutral compound, until 2026-10-13: the lab bought the sodium salt (C12H6NNaO4, 251.17 g/mol).
@reagent_product resazurin_sodium "Fisher Scientific" catalog_number="AAB2118706" product_name="Thermo Scientific Chemicals Resazurin sodium salt" manufacturer_number="Thermo B2118706"
@reagent riboflavin "riboflavin (vitamin B2)" Solid "C17H20N4O6" missing 493570
@reagent_product riboflavin "Sigma-Aldrich" catalog_number="R7649" product_name="RIBOFLAVIN USP"
@reagent ribothymidine "ribothymidine (5-methyluridine)" Solid "C10H14N2O6" missing 445408
@reagent_product ribothymidine "Sigma-Aldrich" catalog_number="535893" product_name="5-METHYLURIDINE, 97%"
@reagent rifampicin "rifampicin" Solid "C43H58N4O12" missing 135398735
@reagent salicin "Salicin" Solid "C13H18O7" missing 439503
@reagent_product salicin "Sigma-Aldrich" catalog_number="S0625" product_name="SALICIN"
@reagent_product salicin "Fisher Scientific" catalog_number="AAA1652406" notes="Manufacturer: Thermo Scientific"
@reagent serine "L-serine" Solid "C3H7NO3" 1.6u"g/mL" 5951
@reagent_product serine "Sigma-Aldrich" catalog_number="S4500" product_name="L-SERINE, REAGENTPLUS™, >=99% (HPLC)" notes="Product name is cut off in the stocklist"
@reagent shikimic_acid "Shikimic Acid" Solid "C7H10O5" missing 8742
@reagent silver_nitrate "silver_nitrate" Solid (Ag⁺+NO3⁻) 4.35u"g/mL" missing
@reagent sodium_acetate_anhydrous "sodium acetate" Solid (Na⁺+OAc⁻) 1.528u"g/mL" missing
# ^ note 2026-08-14: a purchase logged as "acetate" (catalog "S28625-500 G") was originally assumed
# to be this anhydrous salt, but S28625 isn't a real Sigma catalog number -- checked against the
# lab's actual stocklist (Reagent_StockList.xlsx), which lists the same item (same price, same
# size) under catalog S8625-500G with formula CH3COONa.3H2O, i.e. sodium_acetate_trihydrate below.
# Digit-transposition typo in the original purchase log, not a registry error -- no code change
# needed since both reagents already existed; flagged so future stock-building uses the right one.
@reagent sodium_acetate_trihydrate "sodium acetate trihydrate" Solid (Na⁺+OAc⁻+3*H2O) 1.528u"g/mL" missing
@reagent_product sodium_acetate_trihydrate "Fisher Scientific" catalog_number="AAA1623036" product_name="Sodium acetate trihydrate, 99%" manufacturer_number="Thermo A1623036"
@reagent_product sodium_acetate_trihydrate "Sigma-Aldrich" catalog_number="S8625" product_name="Sodium acetate trihydrate, 99%" notes="Listed as S28625-500 G in the stocklist, a typo of S8625"
@reagent_product sodium_acetate_trihydrate "Sigma-Aldrich" catalog_number="32318" product_name="SODIUM ACETATE TRIHYDRATE"
@reagent sodium_bicarbonate "sodium bicarbonate" Solid (Na⁺+HCO3⁻) 2.159u"g/mL" missing
@reagent_product sodium_bicarbonate "Sigma-Aldrich" catalog_number="S5761" product_name="SODIUM BICARBONATE, POWDER, BIOREAGENT" notes="Product name is cut off in the stocklist"
@reagent sodium_carbonate "Sodium Carbonate" Solid (2*Na⁺+CO3²⁻) 2.54u"g/mL" missing
@reagent sodium_chloride "Sodium Chloride" Solid (Na⁺+Cl⁻) missing missing
# ^ fixed 2026-08-14: stored CID was 5324 (Sulfaguanidine), a transposed-digit typo -- corrected to
# 5234 (Sodium Chloride). MW/density were already `missing`, so this doesn't change any derived
# value, only the CID metadata.
@reagent_product sodium_chloride "Fisher Scientific" catalog_number="S671-500" product_name="Sodium Chloride (Crystalline/Biological, Certified), Fisher Chemical™"
@reagent_product sodium_chloride "Sigma-Aldrich" catalog_number="S9625" product_name="SODIUM CHLORIDE, REAGENTPLUS®,>=99%"
@reagent sodium_citrate_dihydrate "Sodium Citrate Dihydrate" Solid missing missing missing
# ^ Fisherbrand S279-500. Vendor listing says "citrate buffer solution" but the product is actually
# the raw salt, Sodium Citrate Dihydrate (trisodium citrate dihydrate, CAS 6132-04-3) -- not a
# premixed buffer. molecular_weight is `missing` and derived instead from its Dissolution
# (electrolytes.jl: 3*Na+ + Citrate3- + 2*H2O), matching sodium_acetate_trihydrate's convention.
@reagent_product sodium_citrate_dihydrate "Fisher Scientific" catalog_number="S279-500" product_name="Sodium citrate dihydrate" notes="Listed by the vendor as a citrate buffer solution; the product is the salt"
@reagent sodium_dichromate_dihydrate "Sodium Dichromate Dihydrate" Solid (2*Na⁺+Cr2O7²⁻+2*H2O) 2.35u"g/mL" missing  # dihydrate
# ^ fixed 2026-08-14: was registered anhydrous (CID 25408) -- corrected to dihydrate (CID 108005)
# per the lab's own purchase record (Sigma 398063-100G, whose catalog listing is "Sodium dichromate
# dihydrate"). Density (2.35) was already the dihydrate's value, unchanged. molecular_weight derives
# from the Dissolution (electrolytes.jl), now including 2 H2O.
@reagent_product sodium_dichromate_dihydrate "Sigma-Aldrich" catalog_number="398063" product_name="Sodium dichromate dihydrate"
@reagent sodium_formate "sodium formate" Solid missing missing missing
# ^ was formic_acid until 2026-10-13: the lab bought sodium formate, not the acid. Its dissolution is in electrolytes.jl.
@reagent_product sodium_formate "Sigma-Aldrich" catalog_number="247596" product_name="SODIUM FORMATE, 99+%, A.C.S. REAGENT"
@reagent sodium_molybdate_dihydrate "Sodium Molybdate Dihydrate" Solid (2*Na⁺+MoO4²⁻+2*H2O) 3.5u"g/mL" missing  # dihydrate
# ^ fixed 2026-08-14: was registered anhydrous (CID 61424, density 3.78) -- corrected to dihydrate
# (CID 16211258, density 3.5) per the lab's own purchase record (catalog 243655-100G, "Sodium
# molybdate dihydrate"). molecular_weight derives from the Dissolution (electrolytes.jl), now
# including 2 H2O.
@reagent_product sodium_molybdate_dihydrate "Sigma-Aldrich" catalog_number="243655" product_name="Sodium molybdate dihydrate" grade="98+%"
@reagent sodium_phosphate_di_heptahydrate "sodium phosphate dibasic heptahydrate" Solid (2*Na⁺+HPO4²⁻+7*H2O) missing missing  # heptahydrate
@reagent sodium_phosphate_di_anhydrous "sodium phosphate dibasic anhydrous" Solid (2*Na⁺+HPO4²⁻) missing missing  # anhydrous (e.g. Sigma S9763)
@reagent_product sodium_phosphate_di_anhydrous "Sigma-Aldrich" catalog_number="S9763" product_name="Sodium phosphate dibasic" grade="ACS reagent"
@reagent_product sodium_phosphate_di_anhydrous "Fisher Scientific" catalog_number="S375-212" product_name="Sodium Phosphate Dibasic Anhydrous (USP), Fisher Chemical™"
@reagent sodium_phosphate_mono_monohydrate "sodium phosphate monobasic monohydrate" Solid (Na⁺+H2PO4⁻+H2O) missing missing  # monohydrate
@reagent_product sodium_phosphate_mono_monohydrate "Fisher Scientific" catalog_number="BP330" product_name="Sodium phosphate monobasic monohydrate, Fisher BioReagents" notes="Supplied by the lab; not in the stocklist. Pack size not recorded."
@reagent sodium_phosphate_mono_anhydrous "sodium phosphate monobasic anhydrous" Solid (Na⁺+H2PO4⁻) missing missing  # anhydrous
# ^ Sigma S0751 (NaH2PO4, 119.98 g/mol on Sigma's listing; the ordering sheet notes it as anhydrous). The lab
# also has the monohydrate above. Sigma's listing does not state the hydrate and the material can carry some
# water, so the lot's certificate of analysis is the final word.
@reagent_product sodium_phosphate_mono_anhydrous "Sigma-Aldrich" catalog_number="S0751" product_name="SODIUM PHOSPHATE MONOBASIC, REAGENTPLUS" grade="≥99.0%"
@reagent sodium_selenite "Sodium Selenite" Solid (2*Na⁺+SeO3²⁻) 3.1u"g/mL" missing
# ^ checked 2026-08-14 against the lab stocklist (Reagent_StockList.xlsx): Sigma 71950-100G "ANHYDROUS".
@reagent_product sodium_selenite "Sigma-Aldrich" catalog_number="71950" product_name="Sodium selenite, anhydrous" grade="≥90.0%"
@reagent sodium_succinate_hexahydrate "Sodium Succinate Hexahydrate" Solid (2*Na⁺+C4H4O4²⁻+6*H2O) missing missing
@reagent sodium_tungstate_dihydrate "Sodium Tungstate Dihydrate" Solid (2*Na⁺+WO4²⁻+2*H2O) 3.25u"g/mL" missing  # dihydrate
# ^ fixed 2026-08-14: was registered anhydrous (CID 26052, density 4.179) -- corrected to dihydrate
# (CID 150191, density 3.25) per the lab's own purchase record (Sigma 223336-100G, "SODIUM TUNGSTATE
# DIHYDRATE, ACS REAGENT"). molecular_weight derives from the Dissolution (electrolytes.jl), now
# including 2 H2O.
@reagent_product sodium_tungstate_dihydrate "Sigma-Aldrich" catalog_number="223336" product_name="Sodium tungstate dihydrate" grade="ACS reagent"
@reagent soluble_starch "Soluble Starch" Solid opaque missing missing
@reagent_product soluble_starch "Fisher Scientific" catalog_number="DF0178-17-7" product_name="BD BBL™/Difco™ Media Additives/Ingredients/Reagents: Soluble Starch" manufacturer_number="BD 217820"
@reagent sorbitol "D-sorbitol" Solid "C6H14O6" 1.49u"g/mL" 5780
@reagent_product sorbitol "Sigma-Aldrich" catalog_number="S1876" product_name="D-SORBITOL"
@reagent spectinomycin "spectinomycin" Solid "C14H24N2O7" missing 15541
@species Stachyose "Stachyose" 0 "C24H42O21" 439531
@reagent stachyose_tetrahydrate "stachyose tetrahydrate" Solid (Stachyose+4*H2O) missing missing
# ^ Thermo AC226085000 is listed as "stachyose hydrate, 97+%", but its SDS (rev. 19-Dec-2025) names it stachyose tetrahydrate.
# The SDS gives C24H42O21·xH2O with the anhydrous 666.58 g/mol; Karl Fischer water ≤12% fits the tetrahydrate (9.8%).
# Fisher's IUPAC name on one listing says trihydrate: the vendor does not state x, so check the lot CoA. No density given.
# Unverified: the tetrahydrate count (4*H2O) rests on the SDS title alone; purity (HPLC ≥97.0%) is not modeled.
# Neutral non-ionizable sugar: no AcidBaseSystem. No pKa source was looked up for this.
@reagent_product stachyose_tetrahydrate "Fisher Scientific" catalog_number="AC226085000" product_name="Thermo Scientific Chemicals Stachyose hydrate, 97+%" manufacturer_number="Thermo 226085000"
@reagent streptomycin "streptomycin" Solid "C21H39N7O12" missing 19649
@reagent succinic_acid "Succinic Acid" Solid "C4H6O4" 1.572u"g/mL" 1110
@reagent_product succinic_acid "Sigma-Aldrich" catalog_number="S9512" product_name="SUCCINIC ACID FREE ACID INSECT CELL CULT" notes="Product name is cut off in the stocklist"
@reagent sucrose "sucrose" Solid "C12H22O11" 1.59u"g/mL" 5988
@reagent_product sucrose "Sigma-Aldrich" catalog_number="S0389" product_name="D-SUCROSE"
@reagent sulfadiazine "sulfadiazine" Solid "C10H10N4O2S" missing 5215
@reagent sulfamethazine "sulfamethazine" Solid "C12H14N4O2S" 1.4655u"g/mL" 5327
@reagent sulfathiazole "sulfathiazole" Solid "C9H9N3O2S2" missing 5340
@reagent tartrate "sodium tartrate dihydrate" Solid missing missing missing
@reagent_product tartrate "Sigma-Aldrich" catalog_number="AAA1618730" product_name="Sodium L-(+) Tartrate"
@reagent_product tartrate "Fisher Scientific" catalog_number="AAA1618730" notes="Manufacturer: Thermo Scientific"
@reagent taurine "Taurine" Solid "C2H7NO3S" missing 1123
@reagent_product taurine "Sigma-Aldrich" catalog_number="T8691" product_name="TAURINE, BIOXTRA, MEETS USP TESTING SP" notes="Product name is cut off in the stocklist"
@reagent tetracycline "tetracycline_hydrochloride" Solid 480.9u"g/mol" missing missing
@reagent thb "Todd-Hewitt Broth" Solid opaque missing missing
@reagent_product thb "Fisher Scientific" catalog_number="DF0492-17-6" product_name="BD Bacto™ Dehydrated Culture Media: Todd Hewitt Broth" manufacturer_number="BD249240"
@reagent thiamine "thiamine hydrochloride" Solid "C12H18Cl2N4OS" missing 6202
@reagent_product thiamine "Sigma-Aldrich" catalog_number="T4625" product_name="THIAMINE HYDROCHLORIDE REAGENT GRADE"
@reagent thiourea "Thiourea" Solid "CH4N2S" 1.405u"g/mL" 2723790
@reagent_product thiourea "Sigma-Aldrich" catalog_number="T7875" product_name="Thiourea, ReagentPlus" grade="≥99.0%"
@reagent threonine "L-threonine" Solid "C4H9NO3" missing 6288
@reagent_product threonine "Sigma-Aldrich" catalog_number="1084110100" product_name="L-THREONINE FOR BIOCHEMISTRY" notes="Manufacturer: Millipore; Received entry: replacement to be sent - 3009292048- available 5-28-26, 6-1-26 ship, arrived 6-5-26"
@reagent thymine "thymine" Solid "C5H6N2O2" missing 1135
@reagent_product thymine "Sigma-Aldrich" catalog_number="T0376" product_name="THYMINE"
@reagent tin_fluoride "Tin (II) Fluoride" Solid (Sn²⁺+2*F⁻) 2.79u"g/mL" missing
@reagent tobramycin "tobramycin" Solid "C18H37N5O9" missing 36294
@reagent trehalose "D-(+)-trehalose dihydrate" Solid "C12H26O13" missing 181978
@reagent_product trehalose "Sigma-Aldrich" catalog_number="T0167" product_name="D(+)TREHALOSE DIHYDRATE CELL CULTURE TES" notes="Product name is cut off in the stocklist"
@reagent triclosan "triclosan" Solid "C12H7Cl3O2" missing 5564
@reagent tryptic_soy_broth "Tryptic Soy Broth" Solid opaque missing missing
@reagent_product tryptic_soy_broth "Fisher Scientific" catalog_number="DF0370-17-3" product_name="BD Bacto™ Tryptic Soy Broth (Soybean-Casein Digest Medium)" manufacturer_number="BD 211825"
@reagent tryptone "tryptone" Solid opaque missing missing
@reagent tryptophan "L-tryptophan" Solid "C11H12N2O2" missing 6305
@reagent_product tryptophan "Sigma-Aldrich" catalog_number="T0254" product_name="L-TRYPTOPHAN, REAGENT GRADE, >=98% (HPLC" notes="Product name is cut off in the stocklist"
@reagent tryptose "Tryptose" Solid opaque missing missing
@reagent_product tryptose "Fisher Scientific" catalog_number="DF0124-17-2" product_name="Gibco™ Bacto™ Tryptose" manufacturer_number="BD Gibco 211713"
@reagent tyrosine "L-tyrosine" Solid "C9H11NO3" missing 6057
@reagent_product tyrosine "Sigma-Aldrich" catalog_number="T8566" product_name="L-TYROSINE BIOXTRA, MEETS EP, JP, USP" notes="Product name is cut off in the stocklist"
@reagent uracil "uracil" Solid "C4H4N2O2" missing 1174
@reagent_product uracil "Fisher Scientific" catalog_number="157300250" product_name="Uracil" grade="99%"
@reagent urea "Urea" Solid "CH4N2O" 1.34u"g/mL" 1176
# ^ Anhydrous neutral urea. Density is PubChem's. No AcidBaseSystem: urea is
# a very weak base, conjugate acid pKa 0.10 at 21 °C (Perrin, Dissociation Constants of Organic Bases
# in Aqueous Solution, IUPAC Chem. Data Ser., 1965, via PubChem CID 1176), so it is not protonated in
# the working pH range.
@reagent_product urea "Sigma-Aldrich" catalog_number="U5128" product_name="Urea ACS reagent" grade="ACS reagent"
@reagent uridine "uridine" Solid "C9H12N2O6" missing 6029
@reagent_product uridine "Sigma-Aldrich" catalog_number="U3750" product_name="URIDINE 99+%"
@reagent valine "L-valine" Solid "C5H11NO2" 1.23u"g/mL" 6287
@reagent_product valine "Sigma-Aldrich" catalog_number="V0500" product_name="L-VALINE, REAGENT GRADE, >=98% (HPLC)"
@reagent vancomycin "vancomycin" Solid "C66H75Cl2N9O24" missing 14969
@reagent vitamin_b12 "vitamin B12" Solid "C63H88CoN14O14P" missing 165339223
@reagent_product vitamin_b12 "Sigma-Aldrich" catalog_number="V6629" product_name="VITAMIN B12, BIOREAGENT, SUITABLE FOR" notes="Product name is cut off in the stocklist"
@reagent vitamin_k1 "Vitamin K1 (phylloquinone)" Solid "C31H46O2" 0.964u"g/mL" 5284607
@reagent_product vitamin_k1 "Sigma-Aldrich" catalog_number="47773" product_name="PHYLLOQUINONE (K1) 100MG NEAT"
@reagent xanthine "xanthine" Solid "C5H4N4O2" missing 1188
@reagent_product xanthine "Sigma-Aldrich" catalog_number="X0626" product_name="XANTHINE"
@reagent_product xanthine "Fisher Scientific" catalog_number="AAA1107714" notes="Manufacturer: Thermo Scientific"
@reagent xanthosine "xanthosine" Solid "C10H12N4O6" missing 64959
@reagent xylitol "Xylitol" Solid "C5H12O5" missing 6912
# ^ fixed 2026-10-12: was CID 581285 ("xylitol, 1-O-octanoyl-", C13H26O6), a different compound --
# corrected to xylitol. CID 6912 is shared with adonitol (ribitol); see the note under adonitol.
@reagent xylose "D-xylose" Solid "C5H10O5" 1.525u"g/mL" 135191
@reagent_product xylose "Sigma-Aldrich" catalog_number="X1500" product_name="D(+)XYLOSE"
@reagent yeast_extract "yeast_extract" Solid opaque missing missing
@reagent_product yeast_extract "Fisher Scientific" catalog_number="BP9727-2" product_name="Fisher BioReagents™ Yeast Extract (Granulated)"
@reagent zinc_chloride "Zinc (II) Chloride" Solid (Zn²⁺+2*Cl⁻) 2.91u"g/mL" missing
# ^ checked 2026-08-14 against the lab stocklist (Sigma Z0152-100G, plain "ZINC CHLORIDE CELL CULTURE", no
# hydrate noted): confirmed anhydrous, unlike zinc_sulfate_heptahydrate below.
@reagent_product zinc_chloride "Sigma-Aldrich" catalog_number="Z0152" product_name="Zinc chloride, cell culture"
@reagent zinc_sulfate_heptahydrate "Zinc Sulfate Heptahydrate" Solid (Zn²⁺+SO4²⁻+7*H2O) 1.97u"g/mL" missing  # heptahydrate
# ^ fixed 2026-08-14: was registered anhydrous (CID 24424, real anhydrous density ~3.8 g/mL) -- the
# stored density (1.96) actually matched the heptahydrate's, and the lab's own purchase record
# (Reagent_StockList.xlsx: Sigma Z0251-100G, "ZINC SULFATE HEPTAHYDRATE") confirms it. Corrected to
# the heptahydrate CID (62640); molecular_weight derives from the Dissolution (electrolytes.jl),
# now including 7 H2O.
@reagent_product zinc_sulfate_heptahydrate "Sigma-Aldrich" catalog_number="Z0251" product_name="Zinc sulfate heptahydrate, cell culture"
