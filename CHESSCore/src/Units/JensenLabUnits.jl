__precompile__(true)
"""
    JensenLabUnits

Unitful units used by CHESS that are not in Unitful itself: optical density `OD` (dimension
absorbance), relative fluorescence `RFU`, an unspecified concentration `X` (as in "2X media"), and
relative centrifugal force `xg`. It also defines the derived dimension `AbsorbanceVolume`
(absorbance times volume), which `CHESSCore.Biomass` uses. The units are registered with Unitful when
the module loads, so `u"OD"` and friends work after `using CHESSCore`.
"""
module JensenLabUnits

using Unitful 


@dimension 𝐀𝐛 "𝐀b" Absorbance false

@refunit OD "OD" OpticalDesnity 𝐀𝐛 false

@dimension 𝐗 "𝐗"   UndefinedConcentration  false 

@refunit X "X" XConcentration 𝐗 false

@dimension 𝐅𝐥𝐮𝐨𝐫 "Fluor" Fluorescence false 

@refunit RFU "RFU" RelativeFluorescenceUnit 𝐅𝐥𝐮𝐨𝐫 false


@derived_dimension AbsorbanceVolume 𝐀𝐛*Unitful.𝐋^3 true 

@unit xg "xg" GravityUnits Unitful.gn false 

const localpromotion=copy(Unitful.promotion)
function __init__()
Unitful.register(JensenLabUnits)
merge!(Unitful.promotion,localpromotion)
end 




end 


 
 function round(q::Unitful.Quantity;kwargs...)
    return round(unit(q),q;kwargs...)
 end 


 