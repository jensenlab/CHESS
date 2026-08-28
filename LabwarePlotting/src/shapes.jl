"""
    rectangle(x,y,w,h)

An axis-aligned `Plots.Shape` with lower-left corner `(x,y)`, width `w`, height `h`.
"""
rectangle(x,y,w,h) = Shape(x .+ [0,w,w,0], y .+ [0,0,h,h])

"""
    circle(x,y,d)

Coordinate vectors for a circle of diameter `d` centered at `(x,y)`.
"""
function circle(x,y,d)
    r = d/2
    θ = LinRange(0,2*π,500)
    return x .+ r*sin.(θ), y .+ r*cos.(θ)
end

"""
    square(x,y,d)

Coordinate vectors for a square of side `d` centered at `(x,y)`.
"""
square(x,y,d) = (x .+ [0,d,d,0] .- d/2, y .+ [0,0,d,d] .- d/2)

"""
    slas_rectangle(x,y,d)

Coordinate vectors for a SLAS-plate-proportioned rectangle (width = 1.5 * height `d`) centered at
`(x,y)`.
"""
function slas_rectangle(x,y,d)
    w = 3/2*d
    return x .+ [0,w,w,0] .- w/2, y .+ [0,0,d,d] .- d/2
end

"""
    place_shape!(plt, shape::Function, x, y, size; kwargs...)

Draw `shape(x,y,size)` (any of [`rectangle`](@ref)/[`circle`](@ref)/[`square`](@ref)/
[`slas_rectangle`](@ref), or a caller-supplied function with the same `(x,y,size) -> coords` contract)
onto `plt` at the given center/size, for cases that place individual markers rather than fill a whole
grid (well-highlighting, deck-slot outlines, non-wellplate labware).
"""
function place_shape!(plt,shape::Function,x,y,size;kwargs...)
    plot!(plt,Shape(shape(x,y,size)...);kwargs...)
    return plt
end
