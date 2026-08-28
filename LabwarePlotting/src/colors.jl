"""
    role_palette(roles::AbstractVector{Symbol}; overrides::Dict{Symbol,<:Any}=Dict{Symbol,Any}())
        -> Dict{Symbol,Any}

A consistent role-to-color mapping for any distinct set of role symbols, built from a `ColorBrewer`
"Set2" palette (clamped to 3-8 colors) and cycled via `mod1` for larger role sets. `overrides` pins
specific roles to specific colors, taking precedence over the palette assignment. Shared by every
package that colors wells/nodes by role, so the same role always renders the same color everywhere in
the CHESS ecosystem.
"""
function role_palette(roles::AbstractVector{Symbol};overrides::Dict{Symbol,<:Any}=Dict{Symbol,Any}())
    palette = ColorBrewer.palette("Set2",max(3,min(8,length(roles))))
    return Dict(r=>get(overrides,r,palette[mod1(i,length(palette))]) for (i,r) in enumerate(roles))
end
