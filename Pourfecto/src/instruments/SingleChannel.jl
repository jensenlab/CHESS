abstract type SingleChannel <: InstrumentModel end


## Piston Defintions 

piston_p1000  = Piston{ContinuousActuator,SingleRepeater}(
    (200u"µL",1000u"µL"),
    (200u"µL",1000u"µL"),
    1
)

piston_p200  = Piston{ContinuousActuator,SingleRepeater}(
    (20u"µL",200u"µL"),
    (20u"µL",200u"µL"),
    1
)

piston_p20  = Piston{ContinuousActuator,SingleRepeater}(
    (2u"µL",20u"µL"),
    (2u"µL",20u"µL"),
    1
)

piston_p2  = Piston{ContinuousActuator,SingleRepeater}(
    (0.1u"µL",2u"µL"),
    (0.1u"µL",2u"µL"),
    1
)

piston_single_channel = Piston{ContinuousActuator,SingleRepeater}(
    (0.1u"µL",1000u"µL"),
    (0.1u"µL",1000u"µL"),
    1
)

## Head Definitions 

single_channel_head_mask = trues(1,1)

head_p1000 = Head{SingleChannel}(
    [piston_p1000],
    [Channel(1200u"µL")],
    single_channel_head_mask
)

head_p200 = Head{SingleChannel}(
    [piston_p200],
    [Channel(220u"µL")],
    single_channel_head_mask
)

head_p20 = Head{SingleChannel}(
    [piston_p20],
    [Channel(25u"µL")],
    single_channel_head_mask
)

head_p2 = Head{SingleChannel}(
    [piston_p2],
    [Channel(25u"µL")],
    single_channel_head_mask
)

head_single_channel = Head{SingleChannel}(
    [piston_single_channel],
    [Channel(1250u"µL")],
    single_channel_head_mask
)


## Deck Definition 

# all single channels have unconstrained decks with a single position (i.e. a benchtop) 

single_channel_deck = [UnconstrainedPosition("benchtop",true,true,"rectangle")]


## Settings definition 

single_channel_settings = InstrumentSettings()


## Configurations 

configurations["single_channel"] = Configuration{SingleChannel}(head_single_channel,single_channel_deck,single_channel_settings)
configurations["p1000"] = Configuration{SingleChannel}(head_p1000,single_channel_deck,single_channel_settings)
configurations["p200"] = Configuration{SingleChannel}(head_p1000,single_channel_deck,single_channel_settings)
configurations["p20"] = Configuration{SingleChannel}(head_p1000,single_channel_deck,single_channel_settings)
configurations["p2"] = Configuration{SingleChannel}(head_p1000,single_channel_deck,single_channel_settings)


# Masks 

function Mask(h::Head{SingleChannel},l::Labware)
    asp,asp_positions = sliding_window_mask(h,l,:aspirate)
    disp,disp_positions = sliding_window_mask(h,l,:dispense)
    return Mask(h,l,asp,disp,asp_positions,disp_positions)
end







