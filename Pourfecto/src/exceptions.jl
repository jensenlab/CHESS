    struct MixingError <:Exception
        msg::AbstractString
        constraints::Vector{JuMP.ConstraintRef}
     end
        
    struct OverdraftError <: Exception
        msg::AbstractString
        balances::Dict{CHESSCore.Stock,Unitful.Quantity}
    end



    struct ChemicalShortageError <: Exception
        msg::AbstractString
        balances::Dict{CHESSCore.Reagent,Unitful.Quantity}
    end
    
    
    struct StockCompatibilityError <: Exception 
        msg::AbstractString 
    end 
