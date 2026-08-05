# Real lab-measured pH values, for tracking pH() prediction accuracy over time. Add new entries as
# you record them; mismatches are reported via @info, not hard-failed (see the testset below for why).

# Amino acid panel: 17.5 mmol/L, 50 mL stocks, four cut with a small 2N HCl addition for solubility --
# mirrors a lab-supplied stock-building script (physical Location/deposit! steps omitted here, only
# the Stock recipes matter for this fixture).
const AMINO_ACID_STOCK_VOLUME = 50u"mL"
const AMINO_ACID_STOCK_CONCENTRATION = 17.5u"mmol/L"
const AMINO_ACID_HCL_2N = 2u"mol"*rgt"HCl" + 1u"l"*rgt"water"
const AMINO_ACID_HCL_2N_ADDITIONS = Dict(
    "aspartic_acid" => 0.156u"mL",
    "glutamic_acid" => 0.156u"mL",
    "phenylalanine" => 0.156u"mL",
    "tyrosine" => 1.876u"mL",
)
const AMINO_ACID_MEASURED_PH = Dict(
    "alanine" => 5.86, "arginine" => 10.11, "asparagine" => 4.63,
    "aspartic_acid" => 2.64, "cysteine" => 2.39, "glutamic_acid" => 2.84,
    "glutamine" => 5.61, "glycine" => 5.91, "histidine" => 7.86,
    "isoleucine" => 5.98, "leucine" => 5.93, "lysine" => 5.85,
    "methionine" => 5.89, "phenylalanine" => 2.79, "proline" => 5.71,
    "serine" => 5.91, "threonine" => 5.70, "tryptophan" => 6.00,
    "tyrosine" => 1.40, "valine" => 5.90,
)

function _amino_acid_stock(symb::String)
    aa = reagentparse(symb;reagent_context=CHESSLabConstants)
    moles = AMINO_ACID_STOCK_CONCENTRATION*AMINO_ACID_STOCK_VOLUME
    mass = uconvert(u"g",moles*molecular_weight(aa))
    hcl_vol = get(AMINO_ACID_HCL_2N_ADDITIONS,symb,0u"mL")
    water_vol = AMINO_ACID_STOCK_VOLUME-hcl_vol
    return mass*aa + water_vol*rgt"water" + hcl_vol*AMINO_ACID_HCL_2N
end

const AMINO_ACID_MEASUREMENTS = [
    (label="$(symb) stock (17.5 mmol/L, 50 mL)",stock=_amino_acid_stock(symb),
     measured_pH=AMINO_ACID_MEASURED_PH[symb],ph_kwargs=(water_correction=true,),notes="amino acid panel")
    for symb in sort(collect(keys(AMINO_ACID_MEASURED_PH)))
]

# Media component panel: individual reagent stocks, plus three real vitamin/trace-metal formulations
# diluted down to working concentration -- mirrors a lab-supplied stock-building script.
const vitamin_k1_solution = 0.05u"g"*rgt"vitamin_k1" + 1u"ml"*rgt"ethanol"
const ferric_chloride_solution = 10u"mmol"*rgt"iron_chloride" + 100u"ml"*rgt"water"
const vitamin_b12_solution = 0.1u"mmol"*rgt"vitamin_b12" + 100u"ml"*rgt"water"

const MEDIA_COMPONENT_MEASUREMENTS = [
    (label="glucose 50g/250mL",stock=50u"g"*rgt"glucose"+250u"mL"*rgt"water",
     measured_pH=4.83,ph_kwargs=(water_correction=true,),notes="media component panel -- " *
     "KNOWN LIMITATION, not a bug: glucose has no registered acid/base chemistry (correctly so -- pure " *
     "D-glucose has no meaningful ionizable group near neutral pH, its only one is the anomeric OH at " *
     "pKa~12+), so the prediction is just the water_correction baseline. Commercial dextrose is real-" *
     "world acidic by design: USP 5% Dextrose Injection specifies pH 4.3-4.4 (range 3.2-6.5), for " *
     "autoclave sterilization and storage-stability reasons (dextrose is most stable near pH 4; higher " *
     "pH accelerates Maillard/caramelization degradation), typically from trace acid added or formed " *
     "during manufacture -- not from glucose's own chemistry. Unlike lactic_acid's purity correction, " *
     "this isn't a fixed citable constant (varies by vendor/lot/grade, per USP's own 3.2-6.5 range), so " *
     "it's left undocumented in the model rather than guessed at."),
    (label="calcium_chloride 1.8g/500mL",stock=1.8u"g"*rgt"calcium_chloride"+500u"mL"*rgt"water",
     measured_pH=5.56,ph_kwargs=(water_correction=true,),notes="media component panel"),
    (label="yeast_extract 41.6g/250mL",stock=41.6u"g"*rgt"yeast_extract"+250u"mL"*rgt"water",
     measured_pH=6.96,ph_kwargs=(water_correction=true,),notes="media component panel"),
    (label="sodium_acetate_trihydrate 59.7g/500mL",stock=59.7u"g"*rgt"sodium_acetate_trihydrate"+500u"ml"*rgt"water",
     measured_pH=8.22,ph_kwargs=(water_correction=true,),notes="media component panel"),
    (label="sodium_chloride 10g/500mL",stock=10u"g"*rgt"sodium_chloride"+500u"mL"*rgt"water",
     measured_pH=5.93,ph_kwargs=(water_correction=true,),notes="media component panel"),
    # sodium_phosphate_mono 11.5g/500mL -- no measured pH yet, add when available
    (label="potassium_phosphate_mono 40g/500mL",stock=40u"g"*rgt"potassium_phosphate_mono"+500u"ml"*rgt"water",
     measured_pH=4.24,ph_kwargs=(water_correction=true,),notes="media component panel"),
    (label="magnesium_sulfate 0.49g/500mL",stock=0.49u"g"*rgt"magnesium_sulfate"+500u"ml"*rgt"water",
     measured_pH=5.67,ph_kwargs=(water_correction=true,),notes="media component panel"),
    (label="alpha_cyclodextrin 0.15g/10mL",stock=0.15u"g"*rgt"alpha_cyclodextrin"+10u"mL"*rgt"water",
     measured_pH=5.91,ph_kwargs=(water_correction=true,),notes="media component panel"),
    (label="cysteine 3.5g/500mL",stock=3.5u"g"*rgt"cysteine"+500u"mL"*rgt"water",
     measured_pH=1.84,ph_kwargs=(water_correction=true,),notes="media component panel"),
    (label="ammonium_sulfate 0.18g/10mL",stock=0.18u"g"*rgt"ammonium_sulfate"+10u"ml"*rgt"water",
     measured_pH=5.29,ph_kwargs=(water_correction=true,),notes="media component panel"),
    (label="myo_inositol 0.9g/10mL",stock=0.9u"g"*rgt"myo_inositol"+10u"ml"*rgt"water",
     measured_pH=5.48,ph_kwargs=(water_correction=true,),notes="media component panel"),
    (label="sodium_succinate_hexahydrate 2.06g/10mL",stock=2.06u"g"*rgt"sodium_succinate_hexahydrate"+10u"mL"*rgt"water",
     measured_pH=8.32,ph_kwargs=(water_correction=true,),notes="media component panel"),
    (label="vitamin_k1 solution diluted 1:250",stock=1u"mL"*vitamin_k1_solution+249u"mL"*rgt"water",
     measured_pH=5.61,ph_kwargs=(water_correction=true,),notes="media component panel"),
    (label="ferric_chloride solution diluted to 250mL",
     stock=250u"mL"*(1u"mL"*ferric_chloride_solution+656.85u"ml"*rgt"water"),
     measured_pH=3.46,ph_kwargs=(water_correction=true,),notes="media component panel"),
    (label="vitamin_b12 solution diluted to 250mL",
     stock=250u"mL"*(1u"ml"*vitamin_b12_solution+499u"ml"*rgt"water"),
     measured_pH=5.39,ph_kwargs=(water_correction=true,),notes="media component panel"),
]

# Complex media stocks panel: several real multi-ingredient 20x/100x/1000x stock recipes -- mirrors a
# lab-supplied stock-building script. nucleobases_100x, vitamins_1000x, vitamin_k1_5000x, metals_500x,
# and the broken/commented-out high_phosphates_20x (references an undefined `lvl`) are excluded --
# no measured pH was provided for those yet.
const complex_NaOH_2N = 2u"mol"*rgt"NaOH" + 1u"l"*rgt"water"

const carbon_sources_20x =
    10u"g"*rgt"glucose" + 10u"g"*rgt"mannitol" + 10u"g"*rgt"trehalose" +
    10u"g"*rgt"sodium_butyrate" + 10u"g"*rgt"mannose" + 10u"g"*rgt"xylose" +
    10u"g"*rgt"glcnac" + 10u"g"*rgt"lactic_acid" + 10u"g"*rgt"sodium_pyruvate" +
    10u"g"*rgt"myo_inositol" + 10u"g"*rgt"sodium_acetate_trihydrate" +
    45u"ml"*complex_NaOH_2N + (1000-45)*u"ml"*rgt"water"

const amino_acids_20x =
    0.312u"g"*rgt"alanine" + 0.610u"g"*rgt"arginine" + 0.462u"g"*rgt"aspartic_acid" +
    0.466u"g"*rgt"asparagine" + 0.424u"g"*rgt"cysteine" + 0.514u"g"*rgt"glutamic_acid" +
    0.512u"g"*rgt"glutamine" + 0.262u"g"*rgt"glycine" + 0.544u"g"*rgt"histidine" +
    0.460u"g"*rgt"isoleucine" + 0.460u"g"*rgt"leucine" + 0.512u"g"*rgt"lysine" +
    0.522u"g"*rgt"methionine" + 0.578u"g"*rgt"phenylalanine" + 0.402u"g"*rgt"proline" +
    0.368u"g"*rgt"serine" + 0.416u"g"*rgt"threonine" + 0.714u"g"*rgt"tryptophan" +
    0.634u"g"*rgt"tyrosine" + 0.410u"g"*rgt"valine" + 1u"l"*rgt"water"

const nps_20x =
    0.2u"g"*rgt"acetamide" + 0.4u"g"*rgt"formamide" + 0.4u"g"*rgt"agmatine" +
    0.4u"g"*rgt"ammonium_nitrate" + 0.4u"g"*rgt"taurine" + 0.4u"g"*rgt"spermidine" +
    0.4u"g"*rgt"carnitine" + 0.4u"g"*rgt"choline" + 0.4u"g"*rgt"ornithine" + 1u"l"*rgt"water"

const phosphates_20x =
    11.6u"g"*rgt"potassium_phosphate_di" + 10u"g"*rgt"sodium_phosphate_di" +
    2.85u"g"*rgt"sodium_phosphate_mono" + 1u"l"*rgt"water"

const salts_20x =
    1510u"mg"*rgt"calcium_chloride" + 100u"mg"*rgt"edta" + 2u"g"*rgt"magnesium_sulfate" +
    100u"mg"*rgt"manganese_chloride" + 100u"mg"*rgt"manganese_sulfate" +
    200u"mg"*rgt"sodium_chloride" + 1u"l"*rgt"water"

const bicarbonate_10x = 12.5u"g"*rgt"sodium_bicarbonate" + 1u"L"*rgt"water"

const COMPLEX_MEDIA_MEASUREMENTS = [
    (label="carbon_sources_20x",stock=carbon_sources_20x,
     measured_pH=6.97,ph_kwargs=(water_correction=true,),notes="complex media stocks panel"),
    (label="amino_acids_20x",stock=amino_acids_20x,
     measured_pH=4.84,ph_kwargs=(water_correction=true,),notes="complex media stocks panel"),
    (label="nps_20x",stock=nps_20x,
     measured_pH=9.18,ph_kwargs=(water_correction=true,),notes="complex media stocks panel"),
    (label="phosphates_20x",stock=phosphates_20x,
     measured_pH=7.55,ph_kwargs=(water_correction=true,),notes="complex media stocks panel"),
    (label="salts_20x",stock=salts_20x,
     measured_pH=3.51,ph_kwargs=(water_correction=true,),notes="complex media stocks panel"),
    (label="bicarbonate_10x",stock=bicarbonate_10x,
     measured_pH=9.31,ph_kwargs=(water_correction=true,),notes="complex media stocks panel"),
]

const EMPIRICAL_MEASUREMENTS = vcat(AMINO_ACID_MEASUREMENTS, MEDIA_COMPONENT_MEASUREMENTS, COMPLEX_MEDIA_MEASUREMENTS)

@testset "Empirical measurement library: prediction accuracy (informational only)" begin
    for m in EMPIRICAL_MEASUREMENTS
        predicted = CHESSCore.pH(m.stock;get(m,:ph_kwargs,(;))...)
        err = predicted - m.measured_pH
        @info "empirical measurement" label=m.label predicted measured=m.measured_pH error=err
        @test isfinite(err) # sanity check only (pH() didn't throw/NaN) -- not an accuracy assertion,
                             # so real-world gaps/noise don't fail CI; read the @info output to track them
    end
end
