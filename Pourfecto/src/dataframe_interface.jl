## Composite stock/dataframe format conversions specific to Pourfecto.
##
## The primitive conversions (df_to_stock, stock_to_df, vc_to_stock, stock_to_vc, q_to_stock,
## stock_to_q, ...) now live in CHESSCore itself (CHESSCore/src/interop/dataframe_interface.jl) and
## are brought in via `using CHESSCore`. vc_to_q/q_to_vc are Pourfecto-only composites (round-tripping
## between the two stock table formats) with no equivalent in CHESSCore, so they stay here.

function vc_to_q(vc::DataFrame,units::DataFrame;kwargs...)
    s = vc_to_stock(vc,units;kwargs...)
    return stock_to_q(s;kwargs...)
end

function q_to_vc(quant::DataFrame,units::DataFrame;kwargs...)
    s= q_to_stock(quant,units;kwargs...)
    return stock_to_vc(s;kwargs...)
end
