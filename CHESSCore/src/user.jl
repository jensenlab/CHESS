


"""
    register_lab(lab_module::Module)

Makes CHESSCore aware of lab objects defined in a new lab module and allows the string macros [`@chem_str`](@ref) and [`@org_str`](@ref) to work with the objects.
When defining new lab objects, make sure to call `register_lab`.

Example:

```julia
# in a custom module
module MyLab
using CHESSCore

function __init__()
    ...
    CHESSCore.register_lab(MyLab)
    ...
end
end #module
```

"""
function register_lab(lab_module::Module)
    push!(CHESSCore.labmodules,lab_module)
    if lab_module !== CHESSCore
        merge!(CHESSCore.chemprops,_chemprops(lab_module))
        merge!(CHESSCore.orgprops,_orgprops(lab_module))
        merge!(CHESSCore.location_kinds,_locationkinds(lab_module))
        merge!(CHESSCore.attribute_kinds,_attributekinds(lab_module))
        merge!(CHESSCore.read_kinds,_readkinds(lab_module))
        merge!(CHESSCore.stock_recipes,_stockrecipes(lab_module))
    end


end