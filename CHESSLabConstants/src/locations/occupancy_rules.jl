# set_occupancy_cost! mutates CHESSCore's single global `occupancy_rules` Dict directly -- unlike
# @location_kind/@reagent/@organism (which write into this module's OWN per-module registry, later
# merged into CHESSCore's registries by register_lab at __init__ time), there is no per-module
# occupancy-rule registry to survive precompilation. Calling set_occupancy_cost! at top-level here
# would populate CHESSCore's Dict only for the remainder of *this* precompile run -- lost the moment a
# fresh session loads both packages from their precompiled caches. So these calls are wrapped in a
# function and invoked from CHESSLabConstants's own __init__ instead (the same reason JensenLabUnits
# calls Unitful.register from its own __init__ rather than at module top-level).
function _register_occupancy_rules!()
    set_occupancy_cost!(:PCRRack,:PCRTube,1//96)
    set_occupancy_cost!(:PCRRack,:PCR8Strip,1//12)
    set_occupancy_cost!(:PCRRack,:BreakawayPCRWafer,1//3)
    set_occupancy_cost!(:PCRRack,:BreakawayPCRPlate,1//1)
    set_occupancy_cost!(:MagPlate,:BreakawayPCRPlate,1//1)
    set_occupancy_cost!(:CryoTubeSlot,:CryoTube,1//1)

    set_occupancy_cost!(:MicroPlateSlot,:MicroPlate,1//1)
    set_occupancy_cost!(:CobraSlot,:CobraSlot,1//2)
    set_occupancy_cost!(:CobraSlot,:WellPlate,1//1)
    set_occupancy_cost!(:GilsonSlot,:WellPlate,1//1)
    set_occupancy_cost!(:Mantis,:LC3,1//3)
    set_occupancy_cost!(:Mantis,:MantisSlot,1//3)
    set_occupancy_cost!(:Mantis,:MantisConicalHolder,1//3)
    set_occupancy_cost!(:MantisSlot,:MicroPlate,1//1)
    set_occupancy_cost!(:MantisSlot,:BreakawayPCRPlate,1//1)
    set_occupancy_cost!(:LC3,:TipReservior,1//1)
    set_occupancy_cost!(:LC3,:Conical15,1//1)
    set_occupancy_cost!(:MantisConicalHolder,:Conical50,1//1)
    set_occupancy_cost!(:NimbusPosition,:NimbusRack,1//1)
    set_occupancy_cost!(:NimbusPlateRack,:WellPlate,1//1)
    set_occupancy_cost!(:NimbusPlateRack,:MagPlate,1//1)
    set_occupancy_cost!(:NimbusConical50Slot,:Conical50,1//1)
    set_occupancy_cost!(:NimbusConical15Slot,:Conical15,1//1)
    set_occupancy_cost!(:ProFlexSlot,:PCRTube,1//32)
    set_occupancy_cost!(:ProFlexSlot,:PCR8Strip,1//4)
    set_occupancy_cost!(:ProFlexSlot,:BreakawayPCRWafer,1//1)
    set_occupancy_cost!(:QuantStudioSlot,:QPCRPlate96,1//1)
    set_occupancy_cost!(:SimpliAmpSlot,:PCRTube,1//96)
    set_occupancy_cost!(:SimpliAmpSlot,:PCR8Strip,1//12)
    set_occupancy_cost!(:SimpliAmpSlot,:BreakawayPCRWafer,1//3)
    set_occupancy_cost!(:SimpliAmpSlot,:BreakawayPCRPlate,1//1)
    set_occupancy_cost!(:Tempest,:TempestHolder,1//3)
    set_occupancy_cost!(:Tempest,:TempestMagazine,1//3)
    set_occupancy_cost!(:TempestSlot,:Bottle,1//1)
    set_occupancy_cost!(:TempestSlot,:Tube,1//1)
    set_occupancy_cost!(:TempestMagazine,:MicroPlate,1//12)
    set_occupancy_cost!(:Panopticon,:PlateReader,1//5)
    set_occupancy_cost!(:Panopticon,:CarouselBase,1//5)
    set_occupancy_cost!(:Panopticon,:StackBase,1//5)
    set_occupancy_cost!(:Panopticon,:PlateCrane,1//5)
    return nothing
end
