"""
    NimbusFourChannel <: InstrumentModel

The Hamilton Nimbus running in its 4-channel mode: 4 independent pistons arranged along a fixed
vertical (row) axis, in a fixed, unchangeable physical order (channel 1 always "above" channel 2,
above channel 3, above channel 4). Each channel's row position is independently adjustable subject
to that ordering and a minimum mechanical spacing; all 4 channels share one gantry column position
per physical move; an inactive channel still holds a placeholder row position that respects
ordering/spacing.

This is deliberately a separate `InstrumentModel`/`Configuration` from [`Nimbus`](@ref) (the
existing single-channel mode), not a variant of it -- the two modes have very different labware
access properties. For scheduling purposes (the MILP in `pourfecto_algorithms/algorithms.jl`), this
instrument's `Head`/`Mask` is intentionally indistinguishable from single-channel Nimbus's: channel
assignment and parallelism are a compile-time secondary optimization (see
`compiler/nimbus_four_channel.jl`), not something the solver decides.
"""
abstract type NimbusFourChannel <: InstrumentModel end

piston_nimbus_4ch = Piston{ContinuousActuator, MultiRepeater}(
    (25u"µL",1000u"µL"),
    (25u"µL",1000u"µL"),
    1
)

# Deliberately the same trivial single-point mask/channel shape as single-channel Nimbus's own
# `nimbus_head` -- the MILP-facing scheduling layer must not be able to tell the two modes apart.
nimbus_4ch_head_mask = trues(1,1)

nimbus_4ch_channels = [Channel(1000u"µL")]

nimbus_4ch_head = Head{NimbusFourChannel}([piston_nimbus_4ch],nimbus_4ch_channels,nimbus_4ch_head_mask)

# Deck layout: the same physical Nimbus robot/deck as single-channel mode, so the same slot names
# and admissible kinds are used -- defined independently here (own bindings, not references into
# Nimbus.jl) since Nimbus.jl must remain completely untouched.
tuberack15mL_0001_4ch=ConstrainedPosition("TubeRack15ML_WellNames_0001",Set([:Conical15]),(4,6),true,true,"circle")
tuberack50mL_0001_4ch=ConstrainedPosition("TubeRack50ML_WellNames_0001",Set([:Conical50]),(2,3),true,true,"circle")
tuberack50mL_0002_4ch=ConstrainedPosition("TubeRack50ML_WellNames_0002",Set([:Conical50]),(2,3),true,true,"circle")
tuberack50mL_0003_4ch=ConstrainedPosition("TubeRack50ML_WellNames_0003",Set([:Conical50]),(2,3),true,true,"circle")
tuberack50mL_0004_4ch=ConstrainedPosition("TubeRack50ML_WellNames_0004",Set([:Conical50]),(2,3),true,true,"circle")
tuberack50mL_0005_4ch=ConstrainedPosition("TubeRack50ML_WellNames_0005",Set([:Conical50]),(2,3),true,true,"circle")
tuberack50mL_0006_4ch=ConstrainedPosition("TubeRack50ML_WellNames_0006",Set([:Conical50]),(2,3),true,true,"circle")

const nimbus_4ch_deep_well_kinds = Set([:DeepWP96,:WP96,:DeepReservoir,:DeepWellColumn,:DeepWellRow])
Cos_96_DW_2mL_0001_4ch=ConstrainedPosition("Cos_96_DW_2mL_0001",nimbus_4ch_deep_well_kinds,(1,1),true,true,"rectangle")
Cos_96_DW_2mL_0002_4ch=ConstrainedPosition("Cos_96_DW_2mL_0002",nimbus_4ch_deep_well_kinds,(1,1),true,true,"rectangle")

const nimbus_4ch_admissible_kinds = union(Set([:Conical15,:Conical50]), nimbus_4ch_deep_well_kinds)

nimbus_4ch_deck = [Cos_96_DW_2mL_0001_4ch tuberack50mL_0001_4ch tuberack50mL_0002_4ch EmptyPosition("tip rack"); tuberack50mL_0003_4ch tuberack50mL_0004_4ch tuberack50mL_0005_4ch tuberack50mL_0006_4ch]

register_instrument!(Configuration{NimbusFourChannel}(nimbus_4ch_head,nimbus_4ch_deck,InstrumentSettings("max_tip_use" => 10, "n_channels" => 4); kind=CHESSCore.location_kinds[:Nimbus]); name="nimbus_four_channel")

## Masks -- deliberately identical in shape/coverage to single-channel Nimbus's, per the instrument's
## own docstring above: channel parallelism is a compile-time concern, invisible to the MILP.
const nimbus_4ch_mask_rules = [
    MaskRule(nimbus_4ch_admissible_kinds, :aspirate, :sliding_window, (;)),
    MaskRule(nimbus_4ch_admissible_kinds, :dispense, :sliding_window, (;)),
]
Mask(h::Head{NimbusFourChannel},l::Labware) = build_mask_from_rules(h,l,nimbus_4ch_mask_rules)
mask_rules_for(::Configuration{NimbusFourChannel}) = nimbus_4ch_mask_rules

"""
    four_channel_row_spacing(kind_name::Symbol) -> Int

Minimum well-row spacing (in well-grid units) required between two active channels on the
4-channel Nimbus head, for a labware of kind `kind_name`. The 4-channel head's physical pitch is
double that of an 8-channel head, so wherever the existing 8-channel-pitch instruments
(`EightChannel`/`Cobra`/`PlateMaster`) use a given `v_spacing` for a labware kind (`v_spacing=1`
for `:WP96`-family kinds, `v_spacing=2` for `:WP384`, see `EightChannel.jl`'s
`eight_channel_mask_rules`), this instrument's minimum row spacing for that same kind is **2x**
that value -- confirmed directly against a real compiled protocol (see
`Pourfecto/src/instruments/templates/esthetically_sticking_multichannel_rounding.csv`): it
dispenses into rows A,C,E,G (stride 2) on a 96-well-format plate, then a second full pass into
B,D,F,H.

This is an explicit per-kind lookup (mirroring how `MaskRule` kwargs already hand-set `v_spacing`
per kind, e.g. `eight_channel_mask_rules`), not a formula derived from labware grid dimensions --
that derivation breaks down for non-well-plate labware (e.g. a 2-row tube rack, where physical tube
spacing is already coarser than any well-plate row pitch). The values below are the real hardware
constraint as described during design and should be validated against the physical instrument
before relying on them for a real protocol; kinds not listed default to `2` (the 96-well-pitch
baseline).
"""
function four_channel_row_spacing(kind_name::Symbol)
    kind_name === :WP384 && return 4
    return 2
end
four_channel_row_spacing(l::Labware) = four_channel_row_spacing(kind(l).name)
