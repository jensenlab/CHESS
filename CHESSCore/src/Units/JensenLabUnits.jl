__precompile__(true)
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


 