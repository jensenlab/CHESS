######
@location_kind Autoclave [:Incubator,:Instrument] nothing nothing nothing nothing nothing 0//1 0//1 Set([:Temperature,:Pressure]) Set{Function}([set_attribute!]) Set{Symbol}() true
@location_kind Freezer [:Incubator,:Instrument] nothing nothing nothing nothing nothing 0//1 0//1 Set([:Temperature]) Set{Function}([set_attribute!]) Set{Symbol}() true
@location_kind Refrigerator [:Incubator,:Instrument] nothing nothing nothing nothing nothing 0//1 0//1 Set([:Temperature]) Set{Function}([set_attribute!]) Set{Symbol}() true


@location_kind MicroPlateSlot [:Slot] nothing nothing nothing nothing nothing



#biospa
@location_kind BioSpaDrawer [:Rack] (1,2) :MicroPlateSlot nothing "Agilent" "n/a"
@location_kind BioSpa [:Incubator,:Instrument] (4,1) :BioSpaDrawer nothing "Agilent" "n/a" 0//1 0//1 Set([:Temperature,:Humidity,:CO2,:LinearShaking]) Set{Function}([move_into!,set_attribute!]) Set{Symbol}() true

# Biotek

@location_kind Epoch2 [:PlateReader,:Instrument] (1,1) :MicroPlateSlot nothing "BioTek" "Epoch2" 0//1 0//1 Set{Symbol}() Set{Function}([record_read!]) Set([:Absorbance,:Fluorescence]) true
@location_kind Cytation5 [:PlateReader,:Instrument] (1,1) :MicroPlateSlot nothing "BioTek" "Cytation5" 0//1 0//1 Set{Symbol}() Set{Function}([record_read!]) Set([:Absorbance,:Fluorescence]) true
@location_kind Cytation10 [:PlateReader,:Instrument] (1,1) :MicroPlateSlot nothing "BioTek" "Cytation10" 0//1 0//1 Set{Symbol}() Set{Function}([record_read!]) Set([:Absorbance,:Fluorescence]) true
@location_kind SynergyH1 [:PlateReader,:Instrument] (1,1) :MicroPlateSlot nothing "Biotek" "Synergy H1" 0//1 0//1 Set{Symbol}() Set{Function}([record_read!]) Set([:Absorbance,:Fluorescence]) true

#cobra
@location_kind CobraSlot [:Slot] nothing nothing nothing nothing nothing
@location_kind Cobra [:LiquidHandler,:Instrument] (2,1) :CobraSlot nothing "ARI" "Cobra" 0//1 0//1 Set{Symbol}() Set{Function}([transfer!]) Set{Symbol}() true




# gilson
@location_kind GilsonSlot [:Slot] nothing nothing nothing nothing nothing
@location_kind Gilson [:LiquidHandler,:Instrument] (2,2) :GilsonSlot nothing "Gilson" "PlateMaster" 0//1 0//1 Set{Symbol}() Set{Function}([transfer!]) Set{Symbol}() true


#incubator
@location_kind IncubatorShelf [:Slot] nothing nothing nothing nothing nothing
@location_kind Incubator [:Incubator,:Instrument] (3,1) :IncubatorShelf nothing "Thermo" "n/a" 0//1 0//1 Set([:Temperature,:Humidity,:CO2]) Set{Function}([set_attribute!]) Set{Symbol}() true

# mantis
@location_kind LC3Slot [:Slot] nothing nothing nothing nothing nothing
@location_kind LC3 Symbol[] (24,1) :LC3Slot nothing "Formulatrix" "Mantis"
@location_kind MantisConicalSlot [:Slot] nothing nothing nothing nothing nothing
@location_kind MantisConicalHolder [:Deck] (4,1) :MantisConicalSlot nothing "Formulatrix" "Mantis"
@location_kind MantisSlot [:Slot] nothing nothing nothing nothing nothing
@location_kind Mantis [:LiquidHandler,:Instrument] nothing nothing nothing nothing nothing 0//1 0//1 Set{Symbol}() Set{Function}([transfer!]) Set{Symbol}() true

#nimbus

@location_kind NimbusPosition [:Slot] nothing nothing nothing nothing nothing
@location_kind NimbusPlateRack [:NimbusRack,:Rack] nothing nothing nothing nothing nothing
@location_kind NimbusConical50Slot [:Slot] nothing nothing nothing nothing nothing
@location_kind NimbusConical15Slot [:Slot] nothing nothing nothing nothing nothing
@location_kind NimbusConical50Rack [:NimbusRack,:Rack] (2,3) :NimbusConical50Slot nothing "Hamilton" "Nimbus"
@location_kind NimbusConical15Rack [:NimbusRack,:Rack] (4,6) :NimbusConical15Slot nothing "Hamilton" "Nimbus"
@location_kind Nimbus [:LiquidHandler,:Instrument] (2,4) :NimbusPosition nothing "Hamilton" "Nimbus" 0//1 0//1 Set{Symbol}() Set{Function}([transfer!]) Set{Symbol}() true


# proflex PCR
@location_kind ProFlexSlot [:Slot] nothing nothing nothing nothing nothing
@location_kind ProFlex [:ThermalCycler,:Incubator,:Instrument] (1,3) :ProFlexSlot nothing "Thermo" "ProFlex" 0//1 0//1 Set([:Temperature]) Set{Function}([set_attribute!]) Set{Symbol}() true

# quantstudio qPCR
@location_kind QuantStudioSlot [:Slot] nothing nothing nothing nothing nothing
@location_kind QuantStudio [:ThermalCycler,:Incubator,:Instrument] (1,1) :QuantStudioSlot nothing "Thermo" "QuantStudio" 0//1 0//1 Set([:Temperature]) Set{Function}([set_attribute!]) Set{Symbol}() true

# simpliamp PCR
@location_kind SimpliAmpSlot [:Slot] nothing nothing nothing nothing nothing
@location_kind SimpliAmp [:ThermalCycler,:Incubator,:Instrument] (1,3) :SimpliAmpSlot nothing "Thermo" "SimpliAmp" 0//1 0//1 Set([:Temperature]) Set{Function}([set_attribute!]) Set{Symbol}() true

# tempest
@location_kind TempestMagazine [:Slot] nothing nothing nothing nothing nothing
@location_kind TempestSlot [:Slot] nothing nothing nothing nothing nothing
@location_kind TempestHolder [:Rack] (1,6) :TempestSlot nothing "Formulatrix" "Tempest"
@location_kind Tempest [:LiquidHandler,:Instrument] nothing nothing nothing nothing nothing 0//1 0//1 Set{Symbol}() Set{Function}([transfer!]) Set{Symbol}() true


# panopticon
@location_kind Panopticon [:Incubator] nothing nothing nothing nothing nothing 0//1 0//1 Set([:Temperature,:Humidity,:CO2]) Set{Function}([set_attribute!]) Set{Symbol}() true

@location_kind HudsonStack [:Rack] (15,1) :MicroPlateSlot nothing "Hudson" "Random Access Stack"
@location_kind CarouselBase [:Instrument] (1,10) :HudsonStack nothing "Hudson" "Carousel Base" 0//1 0//1 Set{Symbol}() Set{Function}() Set{Symbol}() true
@location_kind StackBase [:Instrument] (1,2) :HudsonStack nothing "Hudson" "Stack Base" 0//1 0//1 Set{Symbol}() Set{Function}() Set{Symbol}() true
@location_kind PlateCrane [:Instrument] (1,1) :MicroPlateSlot nothing "Hudson" "PlateCrane" 0//1 0//1 Set{Symbol}() Set{Function}([move_into!]) Set{Symbol}() true

