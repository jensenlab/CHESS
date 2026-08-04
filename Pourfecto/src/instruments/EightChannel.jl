abstract type EightChannel <: InstrumentModel end

## Pistons
piston_p1000  = Piston{ContinuousActuator,SingleRepeater}(
    (200u"µL",1000u"µL"),
    (200u"µL",1000u"µL"),
    1
)

piston_p100 = piston_p1000  = Piston{ContinuousActuator,SingleRepeater}(
    (10u"µL",100u"µL"),
    (10u"µL",100u"µL"),
    1
)

piston_p10  = Piston{ContinuousActuator,SingleRepeater}(
    (1u"µL",10u"µL"),
    (1u"µL",10u"µL"),
    1
)

piston_eight_channel = Piston{ContinuousActuator,SingleRepeater}(
    (1u"µL",1000u"µL"),
    (1u"µL",1000u"µL"),
    1
)

eight_channel_pistons = [piston_eight_channel,piston_p1000,piston_p100,piston_p10]


## Heads

eight_channel_head_mask = trues(1,8)

eight_channel_types = [Channel(1200u"µL"),Channel(1200u"µL"),Channel(220u"µL"),Channel(25u"µL")]

eight_channel_channels = AbstractArray{Channel}[]
for typ in eight_channel_types
    push!(eight_channel_channels,fill(typ,8,1)) # vertical orientation
    push!(eight_channel_channels,fill(typ,1,8)) # horizontal orientation
end


eight_channel_heads = Head[]

for h in eachindex(eight_channel_channels)
    push!(eight_channel_heads,Head{EightChannel}([repeat(eight_channel_pistons,inner=2)[h]],eight_channel_channels[h],eight_channel_head_mask))
end


## Decks

# Pourfecto-owned, explicit admissibility/geometry table -- deliberately decoupled from
# CHESSCore.LocationKind's `categories` field (a different-purpose, externally-owned field with no
# exclusivity enforced between tags). Includes :brPCR96 (tagged :PCRLabware, not :WellPlate, in
# CHESSLabConstants) since Mask genuinely supports it -- deck admissibility must match, or that
# support is unreachable dead code. eight_channel_wellplate_kinds is *derived* from this table
# (below), so deck admissibility, effective_head_size, and Mask geometry can never drift apart.
const eight_channel_mask_rules = [
    MaskRule(Set([:WP96,:DeepWP96,:brPCR96]), :aspirate, :sliding_window, (;)),
    MaskRule(Set([:WP96,:DeepWP96,:brPCR96]), :dispense, :sliding_window, (;)),
    MaskRule(Set([:WP384]), :aspirate, :sliding_window, (;v_spacing=2,h_spacing=2)), # channels are spaced to hit every other well row
    MaskRule(Set([:WP384]), :dispense, :sliding_window, (;v_spacing=2,h_spacing=2)),
    MaskRule(Set([:DeepReservoir]), :aspirate, :blanket, (;)), # single channel SLAS style reservoir only
    MaskRule(Set([:DeepReservoir]), :dispense, :blanket, (;)),
    MaskRule(Set([:DeepWellColumn,:DeepWellRow]), :aspirate, :sliding_window, (;)), # head is wider/taller than the labware in one dimension -- effective_head_size collapses that dimension automatically
    MaskRule(Set([:DeepWellColumn,:DeepWellRow]), :dispense, :sliding_window, (;)),
]
const eight_channel_wellplate_kinds = union((r.kinds for r in eight_channel_mask_rules)...)

eight_channel_deck = [
    ConstrainedPosition("benchtop",eight_channel_wellplate_kinds,(2,1),true,true,"rectangle") # Only two positions allowed to force new protocols for each pair of labware when slotting
    ]


## Settings


eight_channel_settings = InstrumentSettings()

## Configurations

eight_channel_names =[
    "eight_channel_vertical",
    "eight_channel_horizontal",
    "p1000_8_vertical",
    "p1000_8_horizontal",
    "p100_8_vertical",
    "p100_8_horizontal",
    "p10_8_vertical",
    "p10_8_horizontal"
]

for h in eachindex(eight_channel_heads)
    register_instrument!(Configuration{EightChannel}(eight_channel_heads[h],eight_channel_deck,eight_channel_settings); name=eight_channel_names[h])
end


## Masks

# Add method for effective head size with well-plate-kind labware and eight channel pipettes

# THIS funciton does not handle plates with well spacing denser than a 96 well plate

function effective_head_size(h::Head{EightChannel},l::Labware,direction::Symbol)
     H,L = compute_mask_sizes(h,l,direction)
     if !(kind(l).name in eight_channel_wellplate_kinds)
        return H
     end
     r = H[1]
     c = H[2]
     if H[1] > L[1] && H[1] <= 8 # based on typical spacing
       r = L[1]
     end
     if H[2] > L[2] && H[2] <= 12 #based on typical spacing
        c = L[2]
     end
     return (r,c)
end




Mask(h::Head{EightChannel},l::Labware) = build_mask_from_rules(h,l,eight_channel_mask_rules)
mask_rules_for(::Configuration{EightChannel}) = eight_channel_mask_rules
