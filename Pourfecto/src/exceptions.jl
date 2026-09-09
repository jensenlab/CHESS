    struct MixingError <:Exception
        msg::AbstractString
        constraints::Vector{JuMP.ConstraintRef}
     end
        
    struct OverdraftError <: Exception
        msg::AbstractString
        balances::Dict{CHESSCore.Stock,Unitful.Quantity}
    end



    struct ComponentShortageError <: Exception
        msg::AbstractString
        balances::Dict{CHESSCore.StockComponent,Unitful.Quantity}
    end
    
    
    struct StockCompatibilityError <: Exception 
        msg::AbstractString 
    end 
