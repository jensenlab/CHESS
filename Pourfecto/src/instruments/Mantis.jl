abstract type Mantis <: InstrumentModel end

piston_mantis = Piston{ContinuousActuator, MultiRepeater}(
    (0.1u"µL",100u"mL"),
    (0.1u"µL",100u"mL"),
    1
)

mantis_head_mask = trues(1,1) 

mantis_channels = [Channel(100u"mL")]

mantis_head = Head{Mantis}([piston_mantis],mantis_channels, mantis_head_mask)

# Pourfecto-owned, explicit admissibility sets -- deliberately decoupled from CHESSCore.LocationKind's
# `categories` field (a different-purpose, externally-owned field with no exclusivity enforced
# between tags). Used for both the deck positions below and the Mask branches further down, so the
# two can't drift apart. mantis_aspirate_kinds includes :FilterBottle1L (tagged :Bottle in
# CHESSLabConstants, treated the same as the other bottle kinds for Mantis's aspirate mechanism), and
# :MantisBottle -- a labware kind that exists specifically to be Mantis-aspirate-only: since no other
# instrument's own admissibility set lists it, it's automatically unschedulable everywhere else.
const mantis_aspirate_kinds = Set([:Conical15,:Conical50,:Bottle1L,:Bottle250mL,:Bottle500mL,:FilterBottle1L,:MantisBottle])
const mantis_dispense_kinds = Set([:WP96,:WP384,:brPCR96])

const mantis_lc3_position =ConstrainedPosition("LC3",mantis_aspirate_kinds,(1,24),true,false,"circle")
const mantis_hv_position =ConstrainedPosition("High Volume Position",mantis_aspirate_kinds,(1,4),true,false,"circle")
const mantis_main=ConstrainedPosition("Main",mantis_dispense_kinds,(1,1),false,true,"rectangle")
mantis_deck = [mantis_hv_position  mantis_main mantis_lc3_position]


register_instrument!(Configuration{Mantis}(mantis_head,mantis_deck,InstrumentSettings();kind=CHESSCore.location_kinds[:Mantis]); name="mantis")

const mantis_names = Dict(

   :WP96 => "PT3-96-Assay.pd.txt",
   :WP384 => "PT9-384-Assay.pd.txt",
   :brPCR96 => "breakaway_pcr_96.pd.txt"
)


## Mantis Masks

const mantis_mask_rules = [
    MaskRule(mantis_aspirate_kinds, :aspirate, :sliding_window, (;)), # mantis can only aspirate from these labware
    MaskRule(mantis_dispense_kinds, :dispense, :sliding_window, (;)), # mantis can only dispense into these labware
]
Mask(h::Head{Mantis},l::Labware) = build_mask_from_rules(h,l,mantis_mask_rules)
mask_rules_for(::Configuration{Mantis}) = mantis_mask_rules



## Mantis Compiling Functions 

function convert_design(design::DataFrame,sources::Vector{<:Labware},targets::Vector{<:Labware},slotting::SlottingDict,config::Configuration{Mantis})

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
        error("multiple target labware detected. Mantis only supports a single target labware at a time")
    end 

    return design, source_names 
end 

"""

Compiling function for Mantis 
""" 
function write_instrument_files(directory::AbstractString,design::DataFrame,sources::Vector{<:Labware},targets::Vector{<:Labware},config::Configuration{Mantis},slotting::SlottingDict=slotting_greedy(vcat(sources,targets),config);kwargs...) 
        design, source_names= convert_design(design,sources,targets,slotting,config)

        filename=joinpath(directory,basename(directory)*".dl.txt")
        S=nrow(design)
        delay_header=vcat(S,repeat([0,""],S))
        outfile=open(filename,"w")
        tgt_plate = targets[1] # convert_design checks that targets is of length 1 
        platefilename=mantis_names[kind(tgt_plate).name]
        R,C = CHESSCore.shape(tgt_plate)
        print(outfile,join(["[ Version: 5 ]"],'\t'),"\r\n")
        print(outfile,platefilename,"\r\n")
        print(outfile,join(delay_header,'\t'),"\r\n")
        print(outfile,join([1],'\t'),"\r\n")
        print(outfile,join(delay_header,'\t'),"\r\n")

        for i in 1:S
            vols=collect(design[i,:]) # already in µL as a Real 
            vols=round.(reshape(vols,R,C),digits=1) # mantis rounds volumes to nearest 0.1 µL 
            print(outfile,join([source_names[i],"","Normal"],'\t'),"\r\n")
            print(outfile,join(["Well",1],'\t'),"\r\n")
            for r in 1:R
                print(outfile,join(vols[r,:],'\t'),"\r\n")
            end 
        end 
        close(outfile)
        return nothing 
end 