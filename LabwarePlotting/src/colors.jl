"""
    role_palette(keys::AbstractVector; palette::String="Set2", overrides::Dict=Dict())
        -> Dict{eltype(keys),Any}

A consistent category-to-color mapping for any distinct set of keys (relation-type roles, group/component
indices, ...), built from a named `ColorBrewer` palette (clamped to 3-8 colors) and cycled via `mod1` for
larger key sets. `overrides` pins specific keys to specific colors, taking precedence over the palette
assignment. Shared by every package that colors wells/nodes categorically, so the same key always renders
the same color everywhere in the CHESS ecosystem -- e.g. `palette="Set2"` (the default) for relation-type
roles, `palette="Pastel2"` for separable-group coloring.
"""
function role_palette(keys::AbstractVector;palette::String="Set2",overrides::Dict=Dict())
    colors = ColorBrewer.palette(palette,max(3,min(8,length(keys))))
    return Dict(k=>get(overrides,k,colors[mod1(i,length(colors))]) for (i,k) in enumerate(keys))
end
