"""
    struct Lot

The provenance of a received [`Labware`](@ref) such as a reagent bottle: which product it is, which
manufacturing lot, how much was purchased, and when it arrived. A lot is recorded once, with
[`observe!`](@ref), and does not change as the bottle is used. What remains in the bottle is its stock,
which the ledger tracks.

The product is named by its `supplier` and `catalog_number`, matching a [`ReagentProduct`](@ref). The
`lot` is the manufacturer's lot number. The optional `gtin` is the product's global trade item number
from the barcode, `quantity` is the nominal amount purchased (a mass, volume, or amount), `cost` is what
the whole quantity cost, `received` is the date it arrived, and `notes` is free text. The cost is a plain
number in whatever currency the lab uses. The cost of material made from the lot is the cost of the
quantity of it that went in, found by tracing the material back to the lot.

```julia
julia> Lot("Sigma-Aldrich","258148","MKCS9055";quantity=2.5u"L",gtin="04061837736162")
Sigma-Aldrich 258148 lot MKCS9055

julia> Lot(ReagentProduct("Sigma-Aldrich";catalog_number="258148"),"MKCS9055")
Sigma-Aldrich 258148 lot MKCS9055
```
"""
struct Lot
    supplier::String
    catalog_number::String
    lot::String
    gtin::Union{String,Missing}
    quantity::Union{Unitful.Quantity,Missing}
    cost::Union{Float64,Missing}
    received::Union{Date,Missing}
    notes::Union{String,Missing}
    function Lot(supplier::AbstractString,catalog_number::AbstractString,lot::AbstractString,gtin,quantity,cost,received,notes)
        for (field,value) in (("supplier",supplier),("catalog number",catalog_number),("lot",lot))
            isempty(strip(value)) && throw(ArgumentError("a Lot needs a $field"))
        end
        ismissing(quantity) || Unitful.dimension(quantity) in (Unitful.𝐌,Unitful.𝐋^3,Unitful.𝐍) ||
            throw(ArgumentError("a Lot's quantity is a mass, volume, or amount, not $quantity"))
        ismissing(quantity) || ustrip(quantity) > 0 || throw(DomainError(quantity,"a Lot's quantity must be positive"))
        ismissing(cost) || cost >= 0 || throw(DomainError(cost,"a Lot's cost must not be negative"))
        optional(x) = ismissing(x) ? missing : String(x)
        new(String(supplier),String(catalog_number),String(lot),optional(gtin),quantity,ismissing(cost) ? missing : Float64(cost),received,optional(notes))
    end
end

function Lot(supplier::AbstractString,catalog_number::AbstractString,lot::AbstractString;
        gtin=missing,quantity=missing,cost=missing,received=missing,notes=missing)
    return Lot(supplier,catalog_number,lot,gtin,quantity,cost,received,notes)
end

Base.:(==)(a::Lot,b::Lot) = all(f->isequal(getfield(a,f),getfield(b,f)),fieldnames(Lot))
Base.hash(a::Lot,h::UInt) = foldl((acc,f)->hash(getfield(a,f),acc),fieldnames(Lot);init=hash(:Lot,h))

function Base.show(io::IO,l::Lot)
    print(io,l.supplier," ",l.catalog_number," lot ",l.lot)
end
