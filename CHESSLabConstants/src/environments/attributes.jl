# Starter AttributeKind registry, covering the environmental variables the incubator/thermal-cycler
# instruments already defined in locations/instruments.jl control. Wiring these onto individual
# instruments' actuatable_attributes is separate, later work.

@attribute Temperature u"°C" # every incubator/thermal cycler
@attribute Humidity u"percent" # cell-culture incubators (Incubator/BioSpa/Panopticon)
@attribute CO2 u"percent" # cell-culture incubators, same group
@attribute Pressure u"atm" # Autoclave (steam sterilization)
@attribute LinearShaking u"Hz" # BioSpa's shaking-incubation function
