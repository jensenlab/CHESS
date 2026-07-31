const all_labware_kinds = [:WP96,:WP384,:DeepWP96,:DeepReservoir,:DeepWellColumn,:DeepWellRow,:brPCR96,:Bottle1L,:Bottle500mL,:Bottle250mL,:FilterBottle1L,:MantisBottle,:Conical50,:Conical15]
all_labware = build_location.(getindex.(Ref(location_kinds),all_labware_kinds))

function well_index_matrix(r::Integer,c::Integer)
    return reshape(1:prod((r,c)),r,c)
end

# ---------------------------------------------------------------------------------------------
# Independent reference oracle for expected per-well visit counts, derived from each instrument's
# own declared MaskRule table (kind -> archetype/spacing/overhang), NOT by calling
# sliding_window_mask/compute_positions directly -- a brute-force re-derivation of the same physical
# spec (standard model-based-testing practice: a different, more obviously-correct implementation of
# the same rule is what catches bugs in the fast/production path, not a re-typing of it). Replaces
# every hand-typed "visits" Dict that used to live in this file, one per instrument -- a new
# instrument gets full, automatic coverage the moment it defines its own mask_rules_for method.
# ---------------------------------------------------------------------------------------------

"""
    reference_1d_hits(raw_H,Heff,L,spacing,out) -> Vector{Int}

Per-well hit-count profile, in one dimension, for a sliding window of `Heff` channels spaced
`spacing` wells apart, sliding over `L` wells, optionally overhanging the edge (`out`). Brute-force:
enumerate every candidate window offset over a generously wide range and tally which wells each
channel lands on, rather than using compute_positions's closed-form position-count shortcut.

`raw_H` is the *real* channel count in this dimension, which may exceed `Heff` when the dimension is
collapsed (effective_head_size clamped it because the head is wider/taller than the labware in this
dimension, per a specific instrument's override) -- every raw channel in a collapsed dimension maps
onto whichever well the (degenerate) window covers, so the per-well count multiplies by `raw_H`
rather than iterating 1:Heff for the channel term (matching sliding_window_mask's own predicate,
which drops the channel term entirely for a collapsed dimension).
"""
function reference_1d_hits(raw_H::Integer,Heff::Integer,L::Integer,spacing::Integer,out::Bool)
    hits = zeros(Int,L)
    collapsed = Heff != raw_H
    mult = collapsed ? raw_H : 1
    for p in (1-(Heff-1)*spacing):(L+(Heff-1)*spacing)
        touched = Int[]
        for c in 1:Heff
            w = p + spacing*(c-1)
            1 <= w <= L && push!(touched,w)
        end
        valid = out ? !isempty(touched) : length(touched) == Heff
        valid || continue
        for w in touched
            hits[w] += mult
        end
    end
    return hits
end

"""
    reference_1d_position_count(Heff,L,spacing,out) -> Int

Number of valid window placements in one dimension, by the same brute-force validity rule as
`reference_1d_hits` (all channels in bounds if `out=false`, at least one if `out=true`), without
tallying per-well hits -- used by `:blanket`, whose predicate doesn't discriminate by well at all.
"""
function reference_1d_position_count(Heff::Integer,L::Integer,spacing::Integer,out::Bool)
    count = 0
    for p in (1-(Heff-1)*spacing):(L+(Heff-1)*spacing)
        touched = 0
        for c in 1:Heff
            w = p + spacing*(c-1)
            (1 <= w <= L) && (touched += 1)
        end
        valid = out ? touched > 0 : touched == Heff
        valid && (count += 1)
    end
    return count
end

"""
    reference_visits(H,Heff,L,archetype;v_spacing,h_spacing,v_out,h_out) -> Matrix{Int}

Expected r x c per-well visit-count matrix for a labware of shape `L`, given raw head size `H`,
effective head size `Heff` (post row/col-collapsing, if any), and a MaskRule's `archetype`/kwargs.
Row and column dimensions are independent by construction (sliding_window_mask/compute_positions
already decompose them this way), so the two 1-D profiles combine via outer product. `:blanket`
ignores spacing/overhang entirely (matching `blanket_mask`, which passes no kwargs).
"""
function reference_visits(H::Tuple{Int,Int},Heff::Tuple{Int,Int},L::Tuple{Int,Int},archetype::Symbol;
        v_spacing::Integer=1,h_spacing::Integer=1,v_out::Bool=false,h_out::Bool=false)
    if archetype == :blanket
        # blanket_mask's predicate is well-independent (in_mask_bounds only range-checks well/position/
        # channel separately, never matching a channel to a specific well) -- so every well gets the
        # *same* total visit count: (# valid positions, using Heff with blanket_mask's own no-kwargs
        # default of spacing=1/no-overhang) x (the *raw*, uncollapsed channel count in each dimension).
        row_positions = reference_1d_position_count(Heff[1],L[1],1,false)
        col_positions = reference_1d_position_count(Heff[2],L[2],1,false)
        return fill(row_positions*col_positions*H[1]*H[2],L...)
    elseif archetype == :sliding_window
        row_hits = reference_1d_hits(H[1],Heff[1],L[1],v_spacing,v_out)
        col_hits = reference_1d_hits(H[2],Heff[2],L[2],h_spacing,h_out)
        return row_hits * col_hits'
    else
        error("reference_visits: unknown archetype $archetype")
    end
end

"""
    tally_actual_visits(predicate,P,C,W) -> Matrix{Int}

Tally the real Mask predicate's output over every (position,channel) combination, per well -- the
same computation every per-instrument testset in this file used to do inline.
"""
function tally_actual_visits(predicate::Function,P::Tuple{Int,Int},C::Tuple{Int,Int},W::AbstractMatrix)
    Pn,Cn = prod(P),prod(C)
    PC = Tuple.(collect.(Iterators.product(1:Pn,1:Cn)))
    if length(PC) == 0
        PC = [(0,0)]
    end
    return map(x -> sum(map(y -> predicate(x,y...),PC)),W)
end

@testset "Masks" begin

    @testset "Mask coverage (generic, per-instrument mask_rules)" begin
        for (name,conf) in configurations
            rules = mask_rules_for(conf)
            if rules === nothing
                @warn "no mask_rules_for method defined for configuration \"$name\" -- skipped by the generic Mask-coverage test" maxlog=1
                continue
            end
            for lw in all_labware
                k = kind(lw).name
                r,c = CHESSCore.shape(lw)
                W = well_index_matrix(r,c)
                mask = Mask(head(conf),lw)

                for direction in (:aspirate,:dispense)
                    rule_idx = findfirst(rule -> rule.direction==direction && (rule.kinds===:all || k in rule.kinds),rules)

                    H = compute_mask_sizes(head(conf),lw,direction)[1]
                    Heff = effective_head_size(head(conf),lw,direction)
                    raw_C = direction == :aspirate ? size(aspirate_channels(head(conf))) : size(dispense_channels(head(conf)))
                    raw_C = length(raw_C)==1 ? (raw_C[1],1) : raw_C
                    P = direction == :aspirate ? asp_positions(mask) : disp_positions(mask)
                    predicate = direction == :aspirate ? asp(mask) : disp(mask)

                    actual = tally_actual_visits(predicate,P,raw_C,W)
                    expected = isnothing(rule_idx) ? zeros(Int,r,c) :
                        reference_visits(H,Heff,(r,c),rules[rule_idx].archetype;rules[rule_idx].kwargs...)
                    @test actual == expected
                end
            end
        end
    end

end
