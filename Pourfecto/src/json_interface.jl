const TYPEKEY = "__type__"

type_tag(T::Type) = string(T)

# BE SURE TO EDIT THESE WHEN DEFINING NEW INSTRUMENTS!!
const INSTRUMENT_TYPES = Dict{String,DataType}(
    "Cobra" => Cobra ,
    "EightChannel"=> EightChannel,
    "Nimbus" => Nimbus,
    "PlateMaster" => PlateMaster,
    "SingleChannel" => SingleChannel,
)

for T in subtypes(InstrumentModel)
  INSTRUMENT_TYPES[type_tag(T)] = T
end

const ACTUATOR_TYPES = Dict{String,DataType}(
    "ContinuousActuator" => ContinuousActuator,
    "DiscreteActuator"   => DiscreteActuator,
)

const REPEATER_TYPES = Dict{String,DataType}(
    "SingleRepeater" => SingleRepeater,
    "MultiRepeater"  => MultiRepeater,
)

# Labware is no longer one Julia type per kind (see CHESSCore.LocationKind) -- ConstrainedPosition's
# `labware` field holds LocationKind names (Symbol) directly, so there's no type registry to
# maintain here anymore (previously LABWARE_TYPES mapped JSON strings to Julia labware types).


# ----------------------------
# Unitful.Volume helpers
# ----------------------------
function lower_volume(v::Unitful.Volume)
    #convert to ul for consistency
    vμL = uconvert(u"µL", v)
    return Dict(TYPEKEY => "Unitful.Volume",
                "value" => float(ustrip(vμL)),
                "unit"  => "µL")
end

function raise_volume(d::JSON.Object{String,Any})
    d[TYPEKEY] == "Unitful.Volume" || error("Not a Unitful.Volume dict")
    return d["value"] * uparse(d["unit"])
end

# ----------------------------
# BitMatrix helpers
# ----------------------------
function lower_bitmatrix(M::BitMatrix)
    return Dict(TYPEKEY => "BitMatrix",
                "size" => [size(M,1), size(M,2)],
                "data" => vec(Bool.(M)))
end

function raise_bitmatrix(d::JSON.Object{String,Any})
    d[TYPEKEY] == "BitMatrix" || error("Not a BitMatrix dict")
    m, n = d["size"]
    data = Bool.(d["data"])
    return BitMatrix(reshape(data, m, n))
end

# ----------------------------
# JSON.lower for core types
# ----------------------------
function JSON.lower(p::Piston{A,R}) where {A<:Actuator, R<:RepeaterStyle}
    Dict(
        TYPEKEY => "Piston",
        "actuator" => String(nameof(A)),
        "repeater" => String(nameof(R)),
        "asp" => [lower_volume(p.asp[1]), lower_volume(p.asp[2])],
        "disp" => [lower_volume(p.disp[1]), lower_volume(p.disp[2])],
        "deadPad" => p.deadPad,
    )
end

JSON.lower(c::Channel) = Dict(
    TYPEKEY => "Channel",
    "capacity" => lower_volume(c.capacity),
)


function lower_channels(ch::AbstractArray{<:Channel})
  Dict(
  TYPEKEY => "ChannelSet",
  "size" => [size(ch,1),size(ch,2)],
  "data" => vec(collect(ch))
  )
end


function JSON.lower(h::Head{I}) where {I<:InstrumentModel}
    Dict(
        TYPEKEY => "Head",
        "instrument_type" => type_tag(I),
        "pistons" => collect(h.pistons),
        "aspirate_channels" => lower_channels(h.aspirate_channels),
        "aspirate_mask" => lower_bitmatrix(h.aspirate_mask),
        "dispense_channels" => lower_channels(h.dispense_channels),
        "dispense_mask" => lower_bitmatrix(h.dispense_mask),
        "channel_routing" => lower_bitmatrix(h.channel_routing),
    )
end

JSON.lower(p::EmptyPosition) = Dict(TYPEKEY=>"EmptyPosition", "name"=>p.name)

JSON.lower(p::UnconstrainedPosition) = Dict(
    TYPEKEY=>"UnconstrainedPosition",
    "name"=>p.name,
    "aspirate"=>p.aspirate,
    "dispense"=>p.dispense,
    "plotting_shape"=>p.plotting_shape,
)

function JSON.lower(p::ConstrainedPosition)
    Dict(
        TYPEKEY=>"ConstrainedPosition",
        "name"=>p.name,
        "labware"=>[string(s) for s in collect(p.labware)],
        "slots"=>[p.slots[1], p.slots[2]],
        "aspirate"=>p.aspirate,
        "dispense"=>p.dispense,
        "plotting_shape"=>p.plotting_shape,
    )
end

# Deck is an alias, so encode any deck array as a tagged object
function lower_deck(deck::AbstractArray{<:DeckPosition})
    Dict(
        TYPEKEY => "Deck",
        "size" => [size(deck,1), size(deck,2)],   # works for 1D too (n, 1) if you pass reshape
        "data" => vec(collect(deck)),
    )
end

# Configuration{I}
function JSON.lower(c::Configuration{I}) where {I<:InstrumentModel}
    Dict(
        TYPEKEY => "Configuration",
        "instrument_type" => type_tag(I),
        "head" => c.head,
        "deck" => lower_deck(c.deck),
        "settings" => c.settings,  # you must implement JSON.lower + raise_settings for InstrumentSettings
        "kind" => isnothing(c.kind) ? nothing : string(c.kind.name),
    )
end

# ----------------------------
# Raising (parsed Dict -> Julia objects)
# ----------------------------
raise_piston(d::JSON.Object{String,Any}) = begin
    d[TYPEKEY] == "Piston" || error("Not a Piston dict")
    A = ACTUATOR_TYPES[d["actuator"]]
    R = REPEATER_TYPES[d["repeater"]]
    asp1 = raise_volume(d["asp"][1]); asp2 = raise_volume(d["asp"][2])
    disp1 = raise_volume(d["disp"][1]); disp2 = raise_volume(d["disp"][2])
    dead = d["deadPad"]
    Piston{A,R}((asp1, asp2), (disp1, disp2), dead)
end

function raise_channel(d::JSON.Object{String,Any}) 
  d[TYPEKEY] == "Channel" || error("Not a Channel dict")
  return Channel(raise_volume(d["capacity"]))
end

function raise_channels(d::JSON.Object{String,Any})
  d[TYPEKEY] == "ChannelSet" || error("Not a ChannelSet dict")
  m,n = d["size"]
  data = Channel[raise_channel(c) for c in d["data"]]
  return reshape(data,m,n)
end 


function raise_head(d::JSON.Object{String,Any})
    d[TYPEKEY] == "Head" || error("Not a Head dict")
    I = INSTRUMENT_TYPES[d["instrument_type"]]
    pistons  = [raise_piston(p) for p in d["pistons"]]
    aspirate_channels = raise_channels(d["aspirate_channels"])
    aspirate_mask     = raise_bitmatrix(d["aspirate_mask"])
    dispense_channels = raise_channels(d["dispense_channels"])
    dispense_mask     = raise_bitmatrix(d["dispense_mask"])
    channel_routing   = raise_bitmatrix(d["channel_routing"])
    Head{I}(pistons, aspirate_channels, aspirate_mask, dispense_channels, dispense_mask, channel_routing)
end

function raise_deckpos(d::JSON.Object{String,Any})::DeckPosition
    t = d[TYPEKEY]
    if t == "EmptyPosition"
        return EmptyPosition(d["name"])
    elseif t == "UnconstrainedPosition"
        return UnconstrainedPosition(d["name"], d["aspirate"], d["dispense"], d["plotting_shape"])
    elseif t == "ConstrainedPosition"
        lw = Set{Symbol}(Symbol(s) for s in d["labware"])
        slots = (d["slots"][1], d["slots"][2])
        return ConstrainedPosition(d["name"], lw, slots, d["aspirate"], d["dispense"], d["plotting_shape"])
    else
        error("Unknown DeckPosition __type__: $t")
    end
end

function raise_deck(d::JSON.Object{String,Any})
    d[TYPEKEY] == "Deck" || error("Not a Deck dict")
    m, n = d["size"]
    data = DeckPosition[raise_deckpos(p) for p in d["data"]]
    return reshape(data, m, n)
end


function raise_settings(x::JSON.Object{String,Any}) 
    ins = InstrumentSettings()
    for key in keys(x) 
      ins[key] = x[key]
    end 
    return ins 
  end 

function raise_configuration(d::JSON.Object{String,Any})
    d[TYPEKEY] == "Configuration" || error("Not a Configuration dict")
    I = INSTRUMENT_TYPES[d["instrument_type"]]
    head = raise_head(d["head"])                 # already encodes instrument_type; registry must match
    deck = raise_deck(d["deck"])
    settings = raise_settings(d["settings"])
    kn = get(d,"kind",nothing)
    kind = isnothing(kn) ? nothing : CHESSCore.location_kinds[Symbol(kn)]
    return Configuration{I}(head, deck, settings; kind=kind)
end

# ----------------------------
# User-facing routines
# ----------------------------
"Lower a Configuration to a JSON string."
config_to_json(cfg::Configuration) = JSON.json(cfg)

"Parse a JSON string back into a Configuration."
function json_to_config(json_str::AbstractString)
    d = JSON.parse(json_str)
    return raise_configuration(d)
end



## My old code 


StructUtils.lowerkey(::JSON.JSONWriteStyle, x::CHESSCore.Reagent) = JSON.json(reagent_to_string(x))
StructUtils.lowerkey(::JSON.JSONWriteStyle, x::CHESSCore.Organism) = JSON.json(x)
StructUtils.lowerkey(::JSON.JSONWriteStyle, x::CHESSCore.Attribute) = JSON.json(x)
StructUtils.lowerkey(::JSON.JSONWriteStyle, x::DataType) = JSON.json(x)


"""
    pourcast_to_json(p::Pourcast) -> String

Serialize a [`Pourcast`](@ref) to a JSON string.

This converter prepares `Pourcast` contents for JSON encoding by first converting
stocks, labware, and configurations into table-like or dictionary-like representations, then assembling a single dictionary and encoding it with `JSON.json`.
"""
function pourcast_to_json(p::Pourcast)

  

    ss,su = stock_to_df(source_stocks(p))
    ts,tu = stock_to_df(target_stocks(p))

    sl,slu = labware_to_df(source_labware(p))
    tl,tlu = labware_to_df(target_labware(p))





  json_dict = Dict(
    "source_stocks" => (objecttable(ss),objecttable(su)),
    "target_stocks" => (objecttable(ts),objecttable(tu)),
    "source_labware" => (objecttable(sl),objecttable(slu)),
    "target_labware" => (objecttable(tl),objecttable(tlu)),
    "configurations" => config_to_json.(configs(p)),
    "params" => params(p),
    "model_solution" => model_solution(p),
    "objective_value" => scheduling_objective_value(p)
  )

  return JSON.json(json_dict)
end 


"""
    json_to_pourcast(j::String) -> Pourcast

Deserialize a JSON string produced by [`pourcast_to_json`](@ref) back into a
[`Pourcast`](@ref) instance.
"""
function json_to_pourcast(j::String)

    json_dict = JSON.parse(j)

    src_stocks = json_dict["source_stocks"]
    tgt_stocks =json_dict["target_stocks"]

    src_labware = json_dict["source_labware"]
    tgt_labware = json_dict["target_labware"]

    ss = df_to_stock(DataFrame(JSON.parse(src_stocks[1])),DataFrame(JSON.parse(src_stocks[2])))
    ts = df_to_stock(DataFrame(JSON.parse(tgt_stocks[1])),DataFrame(JSON.parse(tgt_stocks[2])))
    sl = df_to_labware(DataFrame(JSON.parse(src_labware[1])),DataFrame(JSON.parse(src_labware[2])))
    tl = df_to_labware(DataFrame(JSON.parse(tgt_labware[1])),DataFrame(JSON.parse(tgt_labware[2])))
    #sl = json_dict["source_labware"]
    #tl= json_dict["target_labware"]
    c = json_to_config.(json_dict["configurations"])
    p = json_dict["params"]
    p = ParameterDict(Symbol.(keys(p)).=> values(p))
    if :priority in keys(p) 
        p[:priority] = PriorityDict(p[:priority])
    end 

    obj_val = json_dict["objective_value"]



    m = json_dict["model_solution"]

    m = Dict(Symbol.(keys(m)) .=> values(m))

    return Pourcast(ss, ts, sl,tl , c,p,m,obj_val)
end