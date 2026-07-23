# Starter ReadKind registry, covering the measurements the BioTek plate-reader instruments already
# defined in locations/instruments.jl can produce. Wiring these onto individual instruments'
# readable_types is separate, later work.

@read Absorbance u"OD" # BioTek plate readers (Epoch2/Cytation5/Cytation10/SynergyH1)
@read Fluorescence u"RFU" # same plate readers
