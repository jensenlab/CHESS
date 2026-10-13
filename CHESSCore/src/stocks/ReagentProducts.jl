"""
    struct ReagentProduct

A product that a [`Reagent`](@ref) is obtained as: who supplies it and how they identify it. A reagent is
a material identified by its composition, and a product is one source of it, so a reagent can have no
product, one, or several. Two vendors' urea are two products of one reagent. The in-house water supply is
a product with no catalog number.

A product holds the facts that stay true across purchases: the `supplier`, the `catalog_number`, the
vendor's `product_name`, the `manufacturer_number`, the `grade` as the vendor states it, and free-text
`notes`. Only the supplier is required. Price, quantity, received date, lot, and shelf location describe a
purchase or a bottle, not the product, and are not held here. A stated purity is information only: the
reagent is the pure composition, and nothing reads the grade.

```julia
julia> ReagentProduct("Sigma-Aldrich";catalog_number="U5128",product_name="Urea ACS reagent",grade="ACS reagent")
Sigma-Aldrich U5128

julia> ReagentProduct("in-house";product_name="deionized water")
in-house
```

Register products with [`@reagent_product`](@ref) or [`add_reagent_product!`](@ref), and read them with
[`reagent_products`](@ref).
"""
struct ReagentProduct
    supplier::String
    catalog_number::Union{String,Missing}
    product_name::Union{String,Missing}
    manufacturer_number::Union{String,Missing}
    grade::Union{String,Missing}
    notes::Union{String,Missing}
    function ReagentProduct(supplier::AbstractString,catalog_number,product_name,manufacturer_number,grade,notes)
        isempty(strip(supplier)) && throw(ArgumentError("a ReagentProduct needs a supplier name"))
        optional(x) = ismissing(x) ? missing : String(x)
        new(String(supplier),optional(catalog_number),optional(product_name),optional(manufacturer_number),optional(grade),optional(notes))
    end
end

function ReagentProduct(supplier::AbstractString;catalog_number=missing,product_name=missing,
        manufacturer_number=missing,grade=missing,notes=missing)
    return ReagentProduct(supplier,catalog_number,product_name,manufacturer_number,grade,notes)
end

# Value equality: `missing` fields compare equal to each other, which `==` would not do.
Base.:(==)(a::ReagentProduct,b::ReagentProduct) = all(f->isequal(getfield(a,f),getfield(b,f)),fieldnames(ReagentProduct))
Base.hash(a::ReagentProduct,h::UInt) = foldl((acc,f)->hash(getfield(a,f),acc),fieldnames(ReagentProduct);init=hash(:ReagentProduct,h))

function Base.show(io::IO,p::ReagentProduct)
    print(io,p.supplier)
    ismissing(p.catalog_number) || print(io," ",p.catalog_number)
end

"""
    const product_registry

Registry mapping a [`Reagent`](@ref) to the vector of its [`ReagentProduct`](@ref)s, in the order they were
registered. Prefer [`add_reagent_product!`](@ref) and [`reagent_products`](@ref) to using it directly.
"""
const product_registry = Dict{Reagent,Vector{ReagentProduct}}()

"""
    add_reagent_product!(reagent::Reagent,product::ReagentProduct)

Register `product` as a product of `reagent`. Registering a product that is already registered for the
reagent does nothing. Inside a lab module, use [`@reagent_product`](@ref), which also keeps the product with
the module so that it survives precompilation.
"""
function add_reagent_product!(reagent::Reagent,product::ReagentProduct)
    products = get!(product_registry,reagent,ReagentProduct[])
    product in products || push!(products,product)
    return nothing
end

"""
    reagent_products(reagent::Reagent)

The [`ReagentProduct`](@ref)s registered for `reagent`, in registration order. The vector is empty for a
reagent with no registered product.
"""
reagent_products(reagent::Reagent) = copy(get(product_registry,reagent,ReagentProduct[]))

# Each lab module keeps its own dictionary of the products it registers, merged into `product_registry`
# by `register_lab`, for the same reason as `_dissolutions`: state written into CHESSCore's registry while a
# dependent package precompiles is not saved with that package, but the module's own dictionary is.
function _reagent_products(m::Module)
    name = Symbol("#JLIMS_reagent_products")
    if isdefined(m,name)
        getproperty(m,name)
    else
        Core.eval(m,:(const $name = Dict{$Reagent,Vector{$ReagentProduct}}()))
    end
end

"""
    @reagent_product reagent supplier [option=value ...]

Register a [`ReagentProduct`](@ref) of the reagent bound to `reagent`. The options are `catalog_number`,
`product_name`, `manufacturer_number`, `grade`, and `notes`. Like [`@reagent`](@ref), it keeps the product
with the calling module, so it survives precompilation.

```julia
julia> @reagent urea "Urea" Solid "CH4N2O" 1.34u"g/mL" 1176
Urea

julia> @reagent_product urea "Sigma-Aldrich" catalog_number="U5128" product_name="Urea ACS reagent"

julia> reagent_products(urea)
1-element Vector{ReagentProduct}:
 Sigma-Aldrich U5128
```
"""
macro reagent_product(reagent,supplier,options...)
    keywords = map(options) do option
        (option isa Expr && option.head === :(=) && option.args[1] isa Symbol) || throw(ArgumentError(
            "@reagent_product options are written name=value, as in catalog_number=\"U5128\""))
        Expr(:kw,option.args[1],option.args[2])
    end
    keep_with_module = __module__ === CHESSCore ? nothing : quote
        let products = get!($(_reagent_products(__module__)),rgt,$ReagentProduct[])
            src in products || push!(products,src)
        end
    end
    esc(quote
        let rgt = $reagent, src = $CHESSCore.ReagentProduct($supplier;$(keywords...))
            $CHESSCore.add_reagent_product!(rgt,src)
            $keep_with_module
            nothing
        end
    end)
end
