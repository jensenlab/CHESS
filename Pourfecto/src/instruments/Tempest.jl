abstract type Tempest <: InstrumentModel end

piston_tempest = Piston{ContinuousActuator, MultiRepeater}(
    (0.1u"µL",100u"mL"),
    (0.1u"µL",100u"mL"),
    1
)
tempest_head_mask = falses(8,8) 
for i in 1:8
    tempest_head_mask[i,i] = true 
end 



# Aspirate and dispense are genuinely different topologies on the real instrument: while aspirating,
# all 8 pistons draw through one shared intake (behaves like a single H=(1,1) channel -- this is why
# it fits into a bottle/conical neck at all); while dispensing, the plumbing fans out so each piston
# independently controls its own nozzle (H=(8,1), tempest_head_mask). The 800mL intake capacity is a
# modeling upper bound (the real intake is unconstrained in principle, limited only by the source
# well) chosen as the sum of the 8 downstream 100mL nozzle channels it feeds.
tempest_head = Head{Tempest}(
    fill(piston_tempest,8),
    [Channel(800u"mL")], trues(8,1),               # aspirate: 8 pistons -> 1 shared intake
    fill(Channel(100u"mL"),8), tempest_head_mask;  # dispense: 8 pistons -> 8 independent nozzles
    channel_routing = trues(1,8),  # the single shared intake is physically plumbed to all 8 dispense nozzles
)

# Pourfecto-owned, explicit admissibility sets -- deliberately decoupled from CHESSCore.LocationKind's
# `categories` field (a different-purpose, externally-owned field with no exclusivity enforced
# between tags). Used for both the deck positions below and the Mask branches further down, so the
# two can't drift apart. tempest_aspirate_kinds includes :FilterBottle1L (tagged :Bottle in
# CHESSLabConstants), preserving Tempest's existing behavior (this instrument already treated it as
# aspirate-eligible, since deck and Mask used the same category check today).
const tempest_aspirate_kinds = Set([:Conical15,:Conical50,:Bottle1L,:Bottle250mL,:Bottle500mL,:FilterBottle1L])
const tempest_dispense_kinds = Set([:WP96,:WP384])

const tempest_input =ConstrainedPosition("Tempest Input Slots",tempest_aspirate_kinds,(1,6),true,false,"circle")
const tempest_main=ConstrainedPosition("Main Tempest Position",tempest_dispense_kinds,(1,1),false,true,"rectangle")
tempest_deck = vcat(tempest_input,tempest_main)


configurations["tempest"] = Configuration{Tempest}(tempest_head,tempest_deck,InstrumentSettings();kind=CHESSCore.location_kinds[:Tempest])


const tempest_names=Dict(
    :WP96=>"PT3-96-Assay.pd.txt",
    :WP384=>"PT9-384-Assay.pd.txt"
)


## Tempest Masks

function Mask(h::Head{Tempest},l::Labware)
    k = kind(l).name

    if k in tempest_aspirate_kinds # tempest can only aspirate from these labware
        asp,asp_positions = sliding_window_mask(h,l,:aspirate)
        disp = (well::Integer,position::Integer,channel::Integer) -> false
        return Mask(h,l,asp,disp,asp_positions,(0,0))

    elseif k == :WP96 # tempest can only dispense into these labware
        disp,disp_positions = sliding_window_mask(h,l,:dispense)
        asp = (well::Integer,position::Integer,channel::Integer) -> false
        return Mask(h,l,asp,disp,(0,0),disp_positions)

    elseif k == :WP384  # 384 well plates only
        disp,disp_positions = sliding_window_mask(h,l,:dispense;v_spacing=2,h_spacing=2)
        asp = (well::Integer,position::Integer,channel::Integer) -> false
        return Mask(h,l,asp,disp,(0,0),disp_positions)

    else
        Mask(h,l,(x,y,z)->false,(x,y,z)->false,(0,0),(0,0)) # unsupported kind for Tempest -- trivial mask (no aspirate/dispense), matching the generic Head/Labware default in types.jl
    end
end

## Compiling Functions 


function convert_design(design::DataFrame,sources::Vector{<:Labware},targets::Vector{<:Labware},slotting::SlottingDict,config::Configuration{Tempest})

    # helper function that converts the design and slotting scheme into operations for the mantis
    
    all(map(x-> x[1] in deck(config),values(slotting))) || ArgumentError("All deck positions in the SlottingDict must be present on the deck")
    S=length(sources)
    src_idx = vcat([fill(i,length(sources[i])) for i in 1:S]...)
    within_src_index = vcat([1:length(sources[i]) for i in 1:S]...) 
     T=length(targets)
    tgt_idx = vcat([fill(i,length(targets[i])) for i in 1:T]...)
    within_tgt_index = vcat([1:length(targets[i]) for i in 1:T]...) 

    source_names = String[]

    for row in 1:nrow(design)
        lw = sources[src_idx[row]]
        if can_aspirate(lw,slotting[lw][1])
            push!(source_names,"$(CHESSCore.name(lw))_$(CHESSCore.name.(children(lw))[within_src_index[row]])")
        else
            error("labware $(CHESSCore.name(lw)) cannot be used as a source in its slotted location")
        end 
    end 

    for col in 1:ncol(design)
        lw = targets[tgt_idx[col]]
        if can_dispense(lw,slotting[lw][1])
            # do nothing 
        else 
            error("labware $(CHESSCore.name(lw)) cannot be used as a target in its slotted location")
        end 
    end 

    if length(targets) > 1 
        designs = DataFrame[]
        for i in eachindex(targets)
            idxs = findall(x-> x==i ,src_idx)
            lw_design = design[:,idxs]
            push!(designs,lw_design)
        end 
        return designs, source_names 
    else


        return design, source_names 
    end 
end 


function write_tempest_dl(filename::String,design::DataFrame,target::Labware,source_names::Vector{String})
    n_stocks=nrow(design)
    outfile=open(filename,"w")
    platefilename=tempest_names[kind(target).name]
    print(outfile,join(["Version            :", 6],'\t'),"\r\n")
    print(outfile,join(["Plate type name    :", platefilename],'\t'),"\r\n")
    print(outfile,join(["Priority Delays    :", 0],'\t'),"\r\n")
    R,C=CHESSCore.shape(target)

    for i in 1:n_stocks 
        vols=Vector(design[i,:])
        vols=reshape(vols,R,C)
        print(outfile,join(["Reagent Name    :", source_names[i]],'\t'),"\r\n")
        print(outfile,join(["Barcode            :"],'\t'),"\r\n")
        print(outfile,join(["Priority           :", 1],'\t'),"\r\n")
        for r in 1:R
            print(outfile,join(vols[r,:],'\t'),"\r\n")
        end 
    end 
    close(outfile)
end
    
function write_instrument_files(directory::AbstractString,design::DataFrame,sources::Vector{<:Labware},targets::Vector{<:Labware},config::Configuration{Tempest},slotting::SlottingDict=slotting_greedy(vcat(sources,targets),config);kwargs...) 

    protocol_name = basename(directory)
    dispenses, source_names =convert_design(design,sources,targets,slotting,config)
    if ~isdir(directory)
        mkdir(directory)
    end


    N = 1 
    if dispenses isa Vector{DataFrame}
        N = length(dispenses) 
    end 
    if N == 1  # single dispense file 
        filename=joinpath(directory,protocol_name*".dl.txt")
        write_tempest_dl(filename,dispenses,targets[1],source_names)
    else  # multidispense 

        allequal(kind.(targets)) || error("all targets must be the same plate type for a tempest multidispense protocol")

        protocol_names = [protocol_name*i for i in 1:N]
        for i in 1:N 
            filename=joinpath(directory,protocol_names[i]*".dl.txt")
            write_tempest_dl(filename,dispenses[i],targets[i],source_names)
        end 
        mdlbasename=protocol_name*".mdl.txt"
        outpath=joinpath(directory,mdlbasename)
        outfile=open(outpath,"w")
        print(outfile,join(["LP:$(tempest_names[kind(targets[1]).name]).pd.txt"],'\t'),"\r\n") # we previously check that all destinations are the same type, so we can safely take the first one
        for i in 1:n
            print(outfile,join(["P:$i","TP:1","DL:$(protocol_names[i])"],'\t'),"\r\n")
        end
        close(outfile)
    end
    
    #delay_header=vcat(n_stocks,repeat([0,""],n_stocks))

    return nothing 
end

