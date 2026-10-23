"""
    abstract type Human <: InstrumentModel end

A person preparing a stock by hand: weighing powders on a balance and measuring liquids by volume
(for example with a graduated cylinder). The `Human` head has two pistons that share one channel, a
volume piston and a mass piston, so one configuration can draw both liquid and powder sources. Pourfecto
plans the amounts and writes them as protocol steps (see [`protocol_steps`](@ref)); it does not model
the steps that follow, such as mixing, filtering or labelling.

The ranges of the pistons are the smallest and largest amounts a person can reasonably measure. They are
only enforced with `enforce_minimum_shot=true`, like the minimum shot of every other instrument. The
defaults suit a benchtop prepared stock: volumes from 1 mL to 10 L and masses from 1 mg to 10 kg. A lab
with different equipment builds its own configuration with [`human_configuration`](@ref) and registers
it with [`register_instrument!`](@ref). Volumes below the minimum are better pipetted: include a pipette
configuration such as `"p200"` in the same run.
"""
abstract type Human <: InstrumentModel end


"""
    human_configuration(; min_volume=1u"mL", max_volume=10u"L", min_mass=1u"mg", max_mass=10u"kg")

Build a `Configuration{Human}` whose volume piston measures between `min_volume` and `max_volume` and
whose mass piston weighs between `min_mass` and `max_mass`. The `"human"` configuration registered by
Pourfecto uses the defaults.

```jldoctest
julia> config = human_configuration(min_mass=10u"mg", max_mass=2u"kg");

julia> [piston_dimension(p) for p in pistons(head(config))]
2-element Vector{Symbol}:
 :volume
 :mass
```
"""
function human_configuration(;min_volume::Unitful.Volume=1u"mL",max_volume::Unitful.Volume=10u"L",min_mass::Unitful.Mass=1u"mg",max_mass::Unitful.Mass=10u"kg")
    0u"µL" < min_volume <= max_volume || error("the volume range must satisfy 0 < min_volume <= max_volume")
    0u"mg" < min_mass <= max_mass || error("the mass range must satisfy 0 < min_mass <= max_mass")
    volume_piston = Piston{ContinuousActuator,SingleRepeater}((min_volume,max_volume),(min_volume,max_volume),1)
    mass_piston = Piston{ContinuousActuator,SingleRepeater}((min_mass,max_mass),(min_mass,max_mass),1)
    # both pistons feed the one channel, the person's hands, so they are the two rows of a 2x1 mask
    human_head = Head{Human}([volume_piston,mass_piston],[Channel(max_volume)],trues(2,1))
    return Configuration{Human}(human_head,human_deck,InstrumentSettings())
end

# the benchtop, as for the pipettes: any labware, any number at a time
const human_deck = [UnconstrainedPosition("benchtop",true,true,"rectangle")]

register_instrument!(human_configuration(); name="human")


# Masks

# A person can reach any open labware, so there is no kind-based admissibility gate (the same
# reasoning as SingleChannel), and one channel moves over the wells one at a time.
const human_mask_rules = [
    MaskRule(:all, :aspirate, :sliding_window, (;)),
    MaskRule(:all, :dispense, :sliding_window, (;)),
]
Mask(h::Head{Human},l::Labware) = build_mask_from_rules(h,l,human_mask_rules)
mask_rules_for(::Configuration{Human}) = human_mask_rules


"""
Compiling function for Human: writes the steps of the protocol to `protocol_steps.csv`, in the order given by
[`protocol_steps`](@ref).
"""
function write_instrument_files(directory::AbstractString,design::DataFrame,source::Vector{<:Labware},target::Vector{<:Labware},config::Configuration{Human},slotting::SlottingDict=slotting_greedy(vcat(source,target),config);kwargs...)
    steps = protocol_steps(Matrix(design),source,target;instrument=last(split(CHESSCore.name(config),".")))
    CSV.write(joinpath(directory,"protocol_steps.csv"),steps)
    return nothing
end
