abstract type PlateMaster <: InstrumentModel end


## Pistons

pm_piston = Piston{ContinuousActuator,SingleRepeater}(
    (1u"µL",220u"µL"),
    (1u"µL",220u"µL"),
    1
)


## Head

pm_head_mask = fill(true,1,96)

pm_head = Head{PlateMaster}(
[pm_piston],
fill(Channel(200u"µL"),8,12),
pm_head_mask
)

# Pourfecto-owned, explicit admissibility/geometry table -- deliberately decoupled from
# CHESSCore.LocationKind's `categories` field (a different-purpose, externally-owned field with no
# exclusivity enforced between tags). Same membership as EightChannel.jl's table today --
# independently defined so the two can diverge later without any shared state to reason about,
# matching how the rest of these two already-duplicated files work. Includes :brPCR96 (tagged
# :PCRLabware, not :WellPlate, in CHESSLabConstants) since Mask genuinely supports it.
# platemaster_wellplate_kinds is *derived* from this table (below), so deck admissibility,
# effective_head_size, and Mask geometry can never drift apart.
const platemaster_mask_rules = [
    MaskRule(Set([:WP96,:DeepWP96,:brPCR96]), :aspirate, :sliding_window, (;)),
    MaskRule(Set([:WP96,:DeepWP96,:brPCR96]), :dispense, :sliding_window, (;)),
    MaskRule(Set([:WP384]), :aspirate, :sliding_window, (;v_spacing=2,h_spacing=2)), # channels are spaced to hit every other well row
    MaskRule(Set([:WP384]), :dispense, :sliding_window, (;v_spacing=2,h_spacing=2)),
    MaskRule(Set([:DeepReservoir]), :aspirate, :blanket, (;)), # single channel SLAS style reservoir only
    MaskRule(Set([:DeepReservoir]), :dispense, :blanket, (;)),
    MaskRule(Set([:DeepWellColumn,:DeepWellRow]), :aspirate, :sliding_window, (;)), # head is wider/taller than the labware in one dimension -- effective_head_size collapses that dimension automatically
    MaskRule(Set([:DeepWellColumn,:DeepWellRow]), :dispense, :sliding_window, (;)),
]
const platemaster_wellplate_kinds = union((r.kinds for r in platemaster_mask_rules)...)

pm_position(name) = ConstrainedPosition(name,platemaster_wellplate_kinds,(1,1),true,true,"rectangle")

## Deck

pm_deck = [
    pm_position("Position A1") pm_position("Position A2") ;
    pm_position("Position B1") pm_position("Position B2")
    ]

## Settings

pm_settings= InstrumentSettings()

## Configuration

register_instrument!(Configuration{PlateMaster}(pm_head,pm_deck,pm_settings;kind=CHESSCore.location_kinds[:Gilson]); name="plate_master")


## Masks

# Add method for effective head size with well-plate-kind labware and platemaster

# THIS funciton does not handle plates with well spacing denser than a 96 well plate

function effective_head_size(h::Head{PlateMaster},l::Labware,direction::Symbol)
     H,L = compute_mask_sizes(h,l,direction)
     if !(kind(l).name in platemaster_wellplate_kinds)
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


Mask(h::Head{PlateMaster},l::Labware) = build_mask_from_rules(h,l,platemaster_mask_rules)
mask_rules_for(::Configuration{PlateMaster}) = platemaster_mask_rules
