
function in_mask_bounds(L::Tuple{Integer,Integer},P::Tuple{Integer,Integer},H::Tuple{Integer,Integer},w::Integer,p::Integer,c::Integer)
    1 <= w <= prod(L) || return false 
    1 <= p <= prod(P) || return false 
    1 <= c <= prod(H) || return false 
    return true 
end 

function cartesian(x::Tuple{Integer,Integer},i::Integer)
    return Tuple(CartesianIndices(x)[i])
end 


function linear_to_cartesian(L::Tuple{Integer,Integer},P::Tuple{Integer,Integer},H::Tuple{Integer,Integer},w::Integer,p::Integer,c::Integer)
        wi,wj = cartesian(L,w) 
        pm,pn = cartesian(P,p) # not using pi and pj because of the constant pi 
        ci,cj = cartesian(H,c)
        return wi,wj,pm,pn,ci,cj 
end 



"""
    effective_head_size(h::Head,l::Labware,direction::Symbol)

The effective channel-grid size to use when computing positions/masks for `h`/`l` in `direction`.
Defaults to the raw head size (no collapsing). Some instruments (e.g. `EightChannel`/`PlateMaster`)
are sometimes paired with a labware kind whose grid is smaller than the head's channel count in some
dimension -- only ever for a `(head,labware kind)` pairing already declared safe by the calling `Mask`
branch's own kind list -- and override this to clamp the effective size down to the labware's own
extent in that dimension. `compute_positions` and `sliding_window_mask` both consult this single
function, so the position-count and the mask predicate can never drift out of sync with each other.
"""
effective_head_size(h::Head,l::Labware,direction::Symbol) = compute_mask_sizes(h,l,direction)[1]

function compute_positions(h::Head,l::Labware,direction::Symbol;kwargs...)
    return compute_positions(effective_head_size(h,l,direction), CHESSCore.shape(l);kwargs...)
end



function compute_positions(H::Tuple{Int64,Int64}, L::Tuple{Int64,Int64}; v_out::Bool=false,h_out::Bool=false, v_spacing::Integer = 1, h_spacing::Integer=1)




r_adj = v_out ? v_spacing * H[1] -1 - (v_spacing-1) : - v_spacing *H[1] + 1 + (v_spacing -1)
c_adj = h_out ? h_spacing * H[2] -1 -(h_spacing-1) : -h_spacing * H[2] + 1 +(h_spacing -1)

return max.(L .+ (r_adj,c_adj), (0,0))
    


end 


function compute_mask_sizes(h::Head, l::Labware, direction::Symbol)
        direction in (:aspirate,:dispense) || error("direction must be :aspirate or :dispense, got $direction")
        ch = direction == :aspirate ? aspirate_channels(h) : dispense_channels(h)
        H = size(ch)
        if H isa Tuple{Integer} # finds case where the channels are just a vector. Size returns a tuple (x,)
            H = (H[1],1)
        end
        L = CHESSCore.shape(l) # CHESSCore function
        return H,L
end


"""
    sliding_window_mask(h::Head,l::Labware,direction::Symbol; v_spacing=1,h_spacing=1,v_out=false,h_out=false)

Build the `(predicate,positions)` pair for the sliding-window mask archetype -- the head's channel
grid (spaced `v_spacing`/`h_spacing` well-units apart, optionally overhanging the labware edge via
`v_out`/`h_out`) slides across the labware's well grid. Covers every `Mask` branch except the
undifferentiated-well case (see `blanket_mask`); a single-channel head reduces to a plain point match
automatically (the spacing term vanishes when `H[d]=1`), so there is no separate case to hand-write.

Per dimension, if `effective_head_size` collapsed (the head is wider/taller than the labware in that
dimension -- only for a pairing already declared safe by the calling `Mask` branch's kind list), the
channel term is dropped from the predicate: any channel is valid, matching the position-count that
already clamped for the same reason.
"""
function sliding_window_mask(h::Head,l::Labware,direction::Symbol; v_spacing::Integer=1,h_spacing::Integer=1,v_out::Bool=false,h_out::Bool=false)
    H,L = compute_mask_sizes(h,l,direction)
    Heff = effective_head_size(h,l,direction)
    positions = compute_positions(Heff,L;v_spacing,h_spacing,v_out,h_out)
    predicate = function(well::Integer,position::Integer,channel::Integer)
        in_mask_bounds(L,positions,H,well,position,channel) || return false
        wi,wj,pm,pn,ci,cj = linear_to_cartesian(L,positions,H,well,position,channel)
        wi_expected = Heff[1]==H[1] ? pm + v_spacing*(ci-1) - (v_out ? v_spacing*(H[1]-1) : 0) : pm
        wj_expected = Heff[2]==H[2] ? pn + h_spacing*(cj-1) - (h_out ? h_spacing*(H[2]-1) : 0) : pn
        return wi == wi_expected && wj == wj_expected
    end
    return predicate, positions
end

"""
    blanket_mask(h::Head,l::Labware,direction::Symbol)

Build the `(predicate,positions)` pair for the blanket mask archetype: any in-bounds
`(well,position,channel)` combination is valid, with no further geometric discrimination -- for a
single, undifferentiated well (e.g. a deep reservoir) that multiple channels/positions may validly
touch at once.
"""
function blanket_mask(h::Head,l::Labware,direction::Symbol)
    H,L = compute_mask_sizes(h,l,direction)
    positions = compute_positions(h,l,direction)
    predicate = (well::Integer,position::Integer,channel::Integer) -> in_mask_bounds(L,positions,H,well,position,channel)
    return predicate, positions
end

"""
    MaskRule(kinds, direction, archetype, kwargs)

One declarative rule in an instrument's admissibility/geometry table: `kinds` (a `Set{Symbol}` of
`LocationKind` names, or the sentinel `:all` for an instrument with no kind-based restriction, e.g.
`SingleChannel`) may be used in `direction` (`:aspirate`/`:dispense`) via `archetype`
(`:sliding_window`/`:blanket`), built with `kwargs` (spacing/overhang kwargs for `:sliding_window`;
ignored for `:blanket`). An instrument's full admissibility+geometry definition is a
`Vector{MaskRule}`; `build_mask_from_rules` consumes it to build a real `Mask`, and the same table can
be walked generically (by kind, by direction) to derive that instrument's overall admissible-kind set
or to independently verify its `Mask` output -- see `Pourfecto/test/masks.jl`.
"""
struct MaskRule
    kinds::Union{Set{Symbol},Symbol}
    direction::Symbol
    archetype::Symbol
    kwargs::NamedTuple
end

"""
    build_mask_from_rules(h::Head,l::Labware,rules::Vector{MaskRule}) -> Mask

Build a real `Mask` for `(h,l)` by finding, per direction, the first rule in `rules` whose `kinds`
admits `kind(l).name` (or is `:all`) and building that rule's archetype. A direction with no matching
rule defaults to the trivial always-false mask, exactly matching every instrument's existing
"unsupported kind" fallback.
"""
function build_mask_from_rules(h::Head,l::Labware,rules::Vector{MaskRule})
    k = kind(l).name
    asp, asp_positions = (x,y,z)->false, (0,0)
    disp, disp_positions = (x,y,z)->false, (0,0)
    for rule in rules
        (rule.kinds === :all || k in rule.kinds) || continue
        pred, positions = rule.archetype == :sliding_window ? sliding_window_mask(h,l,rule.direction;rule.kwargs...) :
                           rule.archetype == :blanket ? blanket_mask(h,l,rule.direction) :
                           error("MaskRule archetype must be :sliding_window or :blanket, got $(rule.archetype)")
        if rule.direction == :aspirate
            asp, asp_positions = pred, positions
        elseif rule.direction == :dispense
            disp, disp_positions = pred, positions
        else
            error("MaskRule direction must be :aspirate or :dispense, got $(rule.direction)")
        end
    end
    return Mask(h,l,asp,disp,asp_positions,disp_positions)
end

"""
    mask_rules_for(config::Configuration) -> Union{Vector{MaskRule},Nothing}

Return the `MaskRule` table backing `config`'s instrument, for generic (test-time) inspection --
e.g. `Pourfecto/test/masks.jl`'s single generic Mask-coverage testset walks this to independently
verify any registered instrument's `Mask` output, including a new instrument added later, as long as
it defines its own `mask_rules_for(::Configuration{X}) = x_mask_rules` method alongside its `Mask`.
Defaults to `nothing` for instruments with no kind-based rule table (e.g. `SingleChannel`, which is
deliberately unconstrained -- see its own `Mask` method).
"""
mask_rules_for(::Configuration) = nothing


