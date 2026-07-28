abstract type Nimbus <: InstrumentModel end

piston_nimbus = Piston{ContinuousActuator, MultiRepeater}(
    (25u"µL",1000u"µL"),
    (25u"µL",1000u"µL"),
    1
)

nimbus_head_mask = trues(1,1) 

nimbus_channels = [Channel(1000u"µL")]

nimbus_head = Head{Nimbus}([piston_nimbus],nimbus_channels, nimbus_head_mask)

# Define our available racks
#15 mL tube
tuberack15mL_0001=ConstrainedPosition("TubeRack15ML_0001",Set([:Conical15]),(4,6),true,true,"circle")
# 50 mL tube
tuberack50mL_0001=ConstrainedPosition("TubeRack50ML_0001",Set([:Conical50]),(2,3),true,true,"circle")
tuberack50mL_0002=ConstrainedPosition("TubeRack50ML_0002",Set([:Conical50]),(2,3),true,true,"circle")
tuberack50mL_0003=ConstrainedPosition("TubeRack50ML_0003",Set([:Conical50]),(2,3),true,true,"circle")
tuberack50mL_0004=ConstrainedPosition("TubeRack50ML_0004",Set([:Conical50]),(2,3),true,true,"circle")
tuberack50mL_0005=ConstrainedPosition("TubeRack50ML_0005",Set([:Conical50]),(2,3),true,true,"circle")
tuberack50mL_0006=ConstrainedPosition("TubeRack50ML_0006",Set([:Conical50]),(2,3),true,true,"circle")

# 2 mL deep well plate
# Explicit kind names, not CHESSCore.LocationKind categories -- Nimbus's Mask never branches on kind
# (a single degenerate H=(1,1) formula applies to any labware), so there's no separate Mask-support
# list this could drift from; this constant just removes a literal-Set duplication (used below twice).
const nimbus_deep_well_kinds = Set([:DeepWP96,:WP96,:DeepReservoir,:DeepWellColumn,:DeepWellRow])
Cos_96_DW_2mL_0001=ConstrainedPosition("Cos_96_DW_2mL_0001",nimbus_deep_well_kinds,(1,1),true,true,"rectangle")
Cos_96_DW_2mL_0002=ConstrainedPosition("Cos_96_DW_2mL_0002",nimbus_deep_well_kinds,(1,1),true,true,"rectangle")


nimbus_deck = [Cos_96_DW_2mL_0001 tuberack50mL_0001 tuberack50mL_0002 EmptyPosition("tip rack"); tuberack50mL_0003 tuberack50mL_0004 tuberack50mL_0005 tuberack50mL_0006]


configurations["nimbus"] = Configuration{Nimbus}(nimbus_head,nimbus_deck,InstrumentSettings("max_tip_use" => 10);kind=CHESSCore.location_kinds[:Nimbus])

## Nimbus Masks 

function Mask(h::Head{Nimbus},l::Labware)
    asp,asp_positions = sliding_window_mask(h,l,:aspirate)
    disp,disp_positions = sliding_window_mask(h,l,:dispense)
    return Mask(h,l,asp,disp,asp_positions,disp_positions)
end



## Nimbus Compiling Functions 

function convert_design(design::DataFrame,sources::Vector{<:Labware},targets::Vector{<:Labware}, slotting::SlottingDict,config::Configuration{Nimbus}) 
    # helper function that converts the design and slotting scheme into operations for the nimbus 
    
    all(map(x-> x[1] in deck(config),values(slotting))) || ArgumentError("All deck positions in the SlottingDict must be present on the deck")
    S=length(sources)
    src_idx = vcat([fill(i,length(sources[i])) for i in 1:S]...)
    within_src_index = vcat([1:length(sources[i]) for i in 1:S]...) 
     T=length(targets)
    tgt_idx = vcat([fill(i,length(targets[i])) for i in 1:T]...)
    within_tgt_index = vcat([1:length(targets[i]) for i in 1:T]...) 

    source_id=String[]
    source_position=Union{String,Integer}[]
    volume=Real[]
    destination_id=String[]
    destination_position=Union{String,Integer}[]
    alphabet=collect('A':'Z')
    for row in 1:nrow(design) #sources
        source = sources[src_idx[row]]
        s_slot , s_pos = slotting[source]
        for col in 1:ncol(design) #destinations
            if design[row,col] == 0 
                continue # skip if no volume transferred 
            end 
            push!(source_id,s_slot.name)
            if length(source) ==1 
                push!(source_position,s_pos)
            else
                pos = cartesian_to_well(CartesianIndices(CHESSCore.children(source))[with_src_index[row]])
                push!(source_position,pos)
            end 
            push!(volume,design[row,col])
            destination =targets[tgt_idx[col]]
            d_slot,d_pos = slotting[destination]
            push!(destination_id,d_slot.name)
            if length(destination) == 1 
                push!(destination_position,d_pos)
            else
                pos = cartesian_to_well(CartesianIndices(CHESSCore.children(destination))[within_tgt_index[col]])
                push!(destination_position,pos)
            end 
        end 
    end 

    out=DataFrame("Source Labware ID"=>source_id,
        "Source Position ID"=> source_position,
        "Volume (uL)"=> volume,
        "Destination Labware ID"=> destination_id,
        "Destination Position ID"=> destination_position,
    )

    return out
end





function write_instrument_files(directory::AbstractString,design::DataFrame,source::Vector{<:Labware},target::Vector{<:Labware},config::Configuration{Nimbus},slotting::SlottingDict=slotting_greedy(vcat(source,target),config);kwargs...) 
    # input error handling 
    S,T = size(design) 
    S == sum(length.(source)) && T == sum(length.(target)) || ArgumentError("Dimension mismatch between design ($S x $T) and number of wells in the source and target labware ($(sum(length.(source))) x $(sum(length.(target))) )")
    all(map(x-> x in keys(slotting),vcat(source,target)))|| ArgumentError("All labware must be slotted")
    allunique(values(slotting)) || ArgumentError("Only one labware can be assigned to a given slot")
    df=convert_design(design,source,target,slotting,config)
    n=nrow(df)
    dispense_df=DataFrame([[],[],[],[],[],],names(df))
    for i = 1:n 
        vol=df[i,"Volume (uL)"] *u"µL"
        while vol > 1e-4u"µL"
            shotvol=min(dispense_channels(head(config))[1].capacity,vol) # maximum shot volume of 1 ml
            push!(dispense_df,(df[i,"Source Labware ID"],df[i,"Source Position ID"],ustrip(uconvert(u"µL",shotvol)),df[i,"Destination Labware ID"],df[i,"Destination Position ID"]))
            vol-=shotvol
        end 
    end 
    #append!(dispenses,dispense_df)

    n=nrow(dispense_df)
    
    change_tip=zeros(Int64,n)
    for i in 2:n
        if dispense_df[i,"Source Position ID"] != dispense_df[i-1,"Source Position ID"]
            change_tip[i]=1
        end 
    end 

    windowsize=settings(config)["max_tip_use"]
    for i in 1:n-windowsize+1   
        window=change_tip[i:i+windowsize-1]
        if sum(window)==0
            change_tip[i+windowsize-1]=1
        end 
    end 
    dispense_df[!,"Change Tip Before"].= change_tip
    
    if ~isdir(directory)
        mkdir(directory)
    end 

    
    CSV.write(joinpath(directory,basename(directory)*".csv"),dispense_df)
    return nothing 
end 
