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

# Pourfecto-owned, explicit admissibility set -- deliberately decoupled from CHESSCore.LocationKind's
# `categories` field (a different-purpose, externally-owned field with no exclusivity enforced
# between tags). Used for both the deck positions below and effective_head_size/Mask further down, so
# the two can't drift apart. Same membership as EightChannel.jl's set today -- independently defined
# and independently named so the two can diverge later without any shared state to reason about,
# matching how the rest of these two already-duplicated files work. Includes :brPCR96 (tagged
# :PCRLabware, not :WellPlate, in CHESSLabConstants) since Mask genuinely supports it.
const platemaster_wellplate_kinds = Set([:WP96,:WP384,:DeepWP96,:DeepReservoir,:DeepWellColumn,:DeepWellRow,:brPCR96])

pm_position(name) = ConstrainedPosition(name,platemaster_wellplate_kinds,(1,1),true,true,"rectangle")

## Deck

pm_deck = [
    pm_position("Position A1") pm_position("Position A2") ;
    pm_position("Position B1") pm_position("Position B2")
    ]

## Settings

pm_settings= InstrumentSettings()

## Configuration

configurations["plate_master"]= Configuration{PlateMaster}(pm_head,pm_deck,pm_settings;kind=CHESSCore.location_kinds[:Gilson])


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


function Mask(h::Head{PlateMaster},l::Labware)
    k = kind(l).name

    if k in (:WP96,:DeepWP96,:brPCR96)  # 96 well plates only
        asp,asp_positions = sliding_window_mask(h,l,:aspirate)
        disp,disp_positions = sliding_window_mask(h,l,:dispense)
        return Mask(h,l,asp,disp,asp_positions,disp_positions)

    elseif k == :WP384  # 384 well plates only -- channels are spaced to hit every other well row
        asp,asp_positions = sliding_window_mask(h,l,:aspirate;v_spacing=2,h_spacing=2)
        disp,disp_positions = sliding_window_mask(h,l,:dispense;v_spacing=2,h_spacing=2)
        return Mask(h,l,asp,disp,asp_positions,disp_positions)

    elseif k == :DeepReservoir  # single channel SLAS style reservoir only
        asp,asp_positions = blanket_mask(h,l,:aspirate)
        disp,disp_positions = blanket_mask(h,l,:dispense)
        return Mask(h,l,asp,disp,asp_positions,disp_positions)

    elseif k in (:DeepWellColumn,:DeepWellRow) # head is wider/taller than the labware in one dimension -- effective_head_size collapses that dimension automatically
        asp,asp_positions = sliding_window_mask(h,l,:aspirate)
        disp,disp_positions = sliding_window_mask(h,l,:dispense)
        return Mask(h,l,asp,disp,asp_positions,disp_positions)

    else
        Mask(h,l,(x,y,z)->false,(x,y,z)->false,(0,0),(0,0)) # unsupported kind for PlateMaster -- trivial mask (no aspirate/dispense), matching the generic Head/Labware default in types.jl
    end
end
