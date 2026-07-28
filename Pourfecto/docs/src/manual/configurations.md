# [Configurations](@id pourfecto_configurations)


```@meta
CurrentModule = Pourfecto
```

Pourfecto uses **configurations** to describe the liquid-handling instruments available to a scheduling problem. A [`Configuration`](@ref) defines the physical and operational constraints of an instrument, including:

- how liquid can be aspirated aspirated and dispensed by the instrument at once,
- how much liquid each channel can carry,
- which pistons are connected to which channels,
- which labware can be placed on the deck,
- which deck positions can aspirate or dispense,
- and any additional instrument-specific settings.

Configurations are supplied to Pourfecto when solving for a [`Pourcast`](@ref). They tell the algorithm what operations are physically possible.

---
## Using pre-defined Configurations 

Pourfecto provides a set of pre-defined instrument configurations with the [`configurations`](@ref) dictionary. These are default configurations commonly used within the Jensen Lab's liquid handling platform. 

```julia 
configurations 
``` 
!!! warning 
    Pre-defined configurations may need to be modified on a case-by-case basis to use in other labs or workflows. For example, the ARI Cobra default configuration contains Jensen Lab-specific file paths in its settings. 


## Creating New Configurations 

A `Configuration` is built from three main pieces:

```julia
Configuration{I}(
    head,
    deck,
    settings,
)
```

where:

- `I` is an [`Instrument`](@ref) type,
- `head` is a [`Head`](@ref) describing pistons and channels,
- `deck` is a collection of [`DeckPosition`](@ref)s,
- `settings` is an [`InstrumentSettings`](@ref) dictionary.




## Instruments

An [`Instrument`](@ref) is an abstract type used to identify a class of liquid handler.

To define a new instrument type, create a subtype of `Instrument`:

```julia
abstract type MyNewInstrument <: Instrument end
```

Instrument types are used as parameters for [`Head`](@ref) and [`Configuration`](@ref):

## Heads

A [`Head`](@ref) describes the liquid-handling apparatus of an instrument. A head contains:

- an array of pistons,
- an array of channels,
- a mask defining which pistons are connected to which channels.


The head defines a Configuration's ability to move liquid and how it interacts with labware. 



---

### Pistons


A [`Piston`](@ref) describes how liquid is moved by an instrument head.


```julia
Piston{A, R}(
    asp,
    disp,
    deadPad,
)
```

where:

- `A <: Actuator` describes the actuation mechanism,
- `R <: RepeaterStyle` describes how repeated dispenses are handled,
- `asp` is a tuple of minimum and maximum aspiration volumes,
- `disp` is a tuple of minimum and maximum dispense volumes,
- `deadPad` is a multiplicative factor used to account for piston error or miscalibration.

For example:

```julia
using Unitful

piston = Piston{ContinuousActuator, SingleRepeater}(
    (20u"µL", 200u"µL"),
    (20u"µL", 200u"µL"),
    1.0,
)
```

This piston can aspirate between `20 µL` and `200 µL`, dispense between `20 µL` and `200 µL`, and uses no additional dead-padding correction.



---

#### Actuator types

An [`Actuator`](@ref) describes the mechanism used by a piston to move liquid.

Pourfecto currently defines two abstract actuator styles:

- [`ContinuousActuator`](@ref)
- [`DiscreteActuator`](@ref)

A continuous actuator represents a mechanism that can move liquid as a continuous flow. A discrete actuator represents a mechanism that dispenses in discrete shots. The mechanism type is passed to the scheduling algorithm a constraint. 



---

#### Repeater styles

A [`RepeaterStyle`](@ref) describes how an instrument handles repeated aspiration and dispense operations.

Pourfecto defines two repeater styles:

- [`SingleRepeater`](@ref)
- [`MultiRepeater`](@ref)

A `SingleRepeater` must dispense its aspirated volume in a single shot. A `MultiRepeater` can dispense a single aspiration across multiple shots. The Repeater style is useful for creating objectives that minimize the number of individual aspirations and dispenses in a liquid handling plan. For example, a `MultiRepeater` can execute multiple dispenses per aspiration, and may thus be faster than a `SingleRepeater`. 




---




### Channels

A [`Channel`](@ref) describes how much liquid an instrument channel can carry.



```julia
channel = Channel(220u"µL")
```

The capacity must be positive:

```julia
Channel(0u"µL")      # errors
Channel(-10u"µL")    # errors
```

Channels are independent of pistons. This allows an instrument to have a piston with one volume range and a channel with a separate carrying capacity.

---

### Head Masks 

The `Head` definition contains arrays of `Piston` and `Channel` definitions along with a binary mask, `H`, that indicates how the pistons and channels are connected. The mask should be of size `P × C`, where `P` is the number of pistons, and `C` is the number of channels. The mask is true for element [`p`,`c`] if piston `p` is connected to channel `c`, and false otherwise. 

For example, a single-piston, single-channel head uses a `1 × 1` mask to indicate that the single piston is connected to the single channel: 

```julia
H = trues(1, 1)
```

The full Head definition becomes

```julia
head = Head{SingleChannelPipette}(
    [piston],
    [channel],
    H,
)
```

Other instruments may have different mask shapes. For example, an eight channel pipette has the following head definition 

```julia
head = Head{EightChannelPipette}(
    [piston],
    fill(channel,8),
    trues(1,8),
)
```

Here, all eight channels are connected to a single piston with the  `1 × 8` head mask

--- 

## Decks

 A [`Deck`](@ref) represents the physical platform upon which the [`Head`](@ref) has access. It is assumed that the head can visit every deck position. 


A Deck is an array of deck positions.
### Deck positions

A [`DeckPosition`](@ref) describes a physical position on the instrument deck.

Pourfecto defines three deck position types:

- [`EmptyPosition`](@ref)
- [`UnconstrainedPosition`](@ref)
- [`ConstrainedPosition`](@ref)



---

### Empty positions

An [`EmptyPosition`](@ref) represents a position that is empty, inaccessible, or unavailable.

```julia
pos = EmptyPosition("unused")
```

Empty positions:

- cannot aspirate,
- cannot dispense,
- cannot hold labware,
- have zero slots.

```julia
can_aspirate(pos)   # false
can_dispense(pos)   # false
slots(pos)          # (0, 0)
```

---

### Unconstrained positions

An [`UnconstrainedPosition`](@ref) represents a deck position that can hold any labware

```julia
pos = UnconstrainedPosition(
    "deck_position_1",
    true,      # aspirate
    true,      # dispense
    "rectangle",    # plotting shape
)
```

The fields are:

| Field | Meaning |
|---|---|
| `name` | Position name |
| `aspirate` | Whether aspiration is allowed from this position |
| `dispense` | Whether dispense is allowed into this position |
| `plotting_shape` | Shape used for plotting/visualization |

By default, `slots(pos)` for an unconstrained position returns:

```julia
(4, 6)
```

which provides a practical cap of 24 labware slots.

---

### Constrained positions

A [`ConstrainedPosition`](@ref) represents a deck position that can hold only specified labware types.

```julia
pos = ConstrainedPosition(
    "plate_position",
    Set([MyPlateType]),
    (1, 1),
    true,
    true,
    "rectangle",
)
```

The fields are:

| Field | Meaning |
|---|---|
| `name` | Position name |
| `labware` | Set of allowed `JLIMS.Labware` types |
| `slots` | Number of labware slots available |
| `aspirate` | Whether aspiration is allowed |
| `dispense` | Whether dispensing is allowed |
| `plotting_shape` | Shape used for plotting/visualization |

For example, a position that can hold only [SLAS plates](https://www.slas.org/resources/standards/ansi-slas-microplate-standards/) and supports both aspiration and dispense might look like:

```julia
plate_position = ConstrainedPosition(
    "plate_position",
    Set([SLASLabware]),
    (1, 1),
    true,
    true,
    "rectangle",
)
```

---

### Creating Decks from multiple positions 

As mentioned, a [`Deck`](@ref) is an array of deck positions.

```julia
deck = [
    UnconstrainedPosition("source", true, false, "rectangle"),
    UnconstrainedPosition("target", false, true, "rectangle"),
]
```

In this example:

- `"source"` can be aspirated from but not dispensed into,
- `"target"` can be dispensed into but not aspirated from.

A more constrained deck might look like:

```julia
deck = [
    ConstrainedPosition("source_plate_slot", Set([SourcePlateType]), (1, 1), true, false, "rectangle"),
    ConstrainedPosition("target_plate_slot", Set([TargetPlateType]), (1, 1), false, true, "rectangle"),
    EmptyPosition("unused"),
]
```



---



## Instrument settings

[`InstrumentSettings`](@ref) is an alias for:

```julia
Dict{String, Any}
```

It stores additional configuration values that do not belong directly in the head or deck definitions.

For example:

```julia
settings = InstrumentSettings(
    "name" => "example instrument",
    "aspiration_speed" => 1.0,
    "default_liquid_class" => "water", 
    "description" => "single-channel example configuration",
)
```

Settings are typically used by instrument-specific compiling functions to pass important parameters to different liquid handler control software. 



---

## Example: Creating a new configuration 

A complete configuration combines an instrument type, head, deck, and settings.

```julia
using Unitful
using Pourfecto

abstract type ExamplePipette <: Instrument end

piston = Piston{ContinuousActuator, SingleRepeater}(
    (20u"µL", 200u"µL"),
    (20u"µL", 200u"µL"),
    1.0,
)

channel = Channel(220u"µL")

head = Head{ExamplePipette}(
    [piston],
    [channel],
    trues(1, 1),
)

deck = [
    UnconstrainedPosition("source", true, false, "rect"),
    UnconstrainedPosition("target", false, true, "rect"),
]

settings = InstrumentSettings(
    "name" => "example single-channel pipette",
)

config = Configuration{ExamplePipette}(
    head,
    deck,
    settings,
)
```

This configuration describes a simple single-channel pipette that can aspirate from one deck position and dispense into another.

---


## JSON Serialization

Configurations can be converted to JSON, and vice-versa



During serialization, each configuration is converted with:

```julia
j_config  = config_to_json(config)
```

During deserialization, configurations are reconstructed with:

```julia
json_to_config(j_config)
```

```@docs
config_to_json
json_to_config
```

---

## Best practices and reminders 

When defining configurations:

- Use an `Instrument` subtype for each distinct instrument class.
- Set realistic aspiration and dispense limits on each `Piston`.
- Keep `Channel` capacity consistent with physical hardware.
- Use the head mask to represent real piston-channel connectivity.
- Use `ConstrainedPosition`s when only certain labware types are valid.
- Use `can_aspirate` and `can_dispense` behavior to separate source and target positions.
- Store extra parameters in `InstrumentSettings`.

---
