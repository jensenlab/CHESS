"""
    module TestUtils

Reusable conformance checks for a `Configuration`, callable from a third-party instrument package's
own test suite (e.g. `using Pourfecto.TestUtils`). Kept as a separate submodule -- rather than
top-level `Pourfecto` exports -- so its dependency on `Test` (`@test`/`@testset`) doesn't leak into
the namespace of ordinary (non-test) users of `Pourfecto`. `Test` is already a Pourfecto dependency,
so no new dependency is introduced by using this module.

Checks are split into two tiers by cost:

* **Tier 1** (no solver required): [`test_mask_coverage`](@ref), [`test_json_roundtrip`](@ref), and
  the [`test_instrument_interface`](@ref) convenience wrapper running both. Safe to run in any CI
  environment.
* **Tier 2** (solver required): [`test_pourcast_compilation`](@ref) -- requires an already-solved
  `Pourcast` (obtained however the caller likes, e.g. `pourfecto(...; optimizer=SCIP.Optimizer)`,
  SCIP already being a Pourfecto dependency).

These are the same checks Pourfecto's own test suite (`test/masks.jl`,
`test/test_problems/test_compilation.jl`) runs against its seven built-in instruments -- moving the
logic here means Pourfecto's own tests and any third party's tests exercise identical code.
"""
module TestUtils

using Test
using ..Pourfecto
import ..Pourfecto: get_config_type, slotting_requirements
import Random

"""
    default_test_labware_kinds() -> Vector{Symbol}

The default set of `CHESSCore.LocationKind` names used to probe an instrument's `Mask` coverage in
[`test_mask_coverage`](@ref). Mirrors the fixture Pourfecto's own `test/masks.jl` uses against its
built-in instruments. Pass a narrower/wider `kinds` list to `test_mask_coverage` if your instrument
only supports a subset, or supports lab-specific labware kinds this default doesn't include.
"""
function default_test_labware_kinds()
    return [:WP96,:WP384,:DeepWP96,:DeepReservoir,:DeepWellColumn,:DeepWellRow,:brPCR96,
            :Bottle1L,:Bottle500mL,:Bottle250mL,:FilterBottle1L,:MantisBottle,:Conical50,:Conical15]
end

function _well_index_matrix(r::Integer,c::Integer)
    return reshape(1:prod((r,c)),r,c)
end

"""
    _reference_1d_hits(raw_H,Heff,L,spacing,out) -> Vector{Int}

Per-well hit-count profile, in one dimension, for a sliding window of `Heff` channels spaced
`spacing` wells apart, sliding over `L` wells, optionally overhanging the edge (`out`). Brute-force:
enumerate every candidate window offset over a generously wide range and tally which wells each
channel lands on -- an independent reference oracle, not a re-typing of `sliding_window_mask`'s own
closed-form position-count shortcut.

`raw_H` is the *real* channel count in this dimension, which may exceed `Heff` when the dimension is
collapsed (`effective_head_size` clamped it because the head is wider/taller than the labware in this
dimension) -- every raw channel in a collapsed dimension maps onto whichever well the (degenerate)
window covers, so the per-well count multiplies by `raw_H` rather than iterating `1:Heff` for the
channel term (matching `sliding_window_mask`'s own predicate, which drops the channel term entirely
for a collapsed dimension).
"""
function _reference_1d_hits(raw_H::Integer,Heff::Integer,L::Integer,spacing::Integer,out::Bool)
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
    _reference_1d_position_count(Heff,L,spacing,out) -> Int

Number of valid window placements in one dimension, by the same brute-force validity rule as
[`_reference_1d_hits`](@ref), without tallying per-well hits -- used by `:blanket`, whose predicate
doesn't discriminate by well at all.
"""
function _reference_1d_position_count(Heff::Integer,L::Integer,spacing::Integer,out::Bool)
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
    _reference_visits(H,Heff,L,archetype;v_spacing,h_spacing,v_out,h_out) -> Matrix{Int}

Expected r x c per-well visit-count matrix for a labware of shape `L`, given raw head size `H`,
effective head size `Heff` (post row/col-collapsing, if any), and a `MaskRule`'s `archetype`/kwargs.
Row and column dimensions are independent by construction (`sliding_window_mask`/`compute_positions`
already decompose them this way), so the two 1-D profiles combine via outer product. `:blanket`
ignores spacing/overhang entirely (matching `blanket_mask`, which passes no kwargs).
"""
function _reference_visits(H::Tuple{Int,Int},Heff::Tuple{Int,Int},L::Tuple{Int,Int},archetype::Symbol;
        v_spacing::Integer=1,h_spacing::Integer=1,v_out::Bool=false,h_out::Bool=false)
    if archetype == :blanket
        row_positions = _reference_1d_position_count(Heff[1],L[1],1,false)
        col_positions = _reference_1d_position_count(Heff[2],L[2],1,false)
        return fill(row_positions*col_positions*H[1]*H[2],L...)
    elseif archetype == :sliding_window
        row_hits = _reference_1d_hits(H[1],Heff[1],L[1],v_spacing,v_out)
        col_hits = _reference_1d_hits(H[2],Heff[2],L[2],h_spacing,h_out)
        return row_hits * col_hits'
    else
        error("_reference_visits: unknown archetype $archetype")
    end
end

"""
    _tally_actual_visits(predicate,P,C,W) -> Matrix{Int}

Tally the real `Mask` predicate's output over every (position,channel) combination, per well.
"""
function _tally_actual_visits(predicate::Function,P::Tuple{Int,Int},C::Tuple{Int,Int},W::AbstractMatrix)
    Pn,Cn = prod(P),prod(C)
    PC = Tuple.(collect.(Iterators.product(1:Pn,1:Cn)))
    if length(PC) == 0
        PC = [(0,0)]
    end
    return map(x -> sum(map(y -> predicate(x,y...),PC)),W)
end

"""
    test_mask_coverage(config::Configuration; kinds=default_test_labware_kinds()) -> Bool

Brute-force-verify that `Mask(head(config), labware)` for every kind in `kinds` produces exactly the
per-well visit counts implied by `mask_rules_for(config)`. Requires no optimizer.

If `mask_rules_for(config) === nothing` (no `MaskRule` table defined), emits a warning and returns
`true` without testing anything -- your `Mask` method exists and is used for scheduling, but hasn't
opted into `MaskRule`-based coverage verification. Define `mask_rules_for(::Configuration{YourInstrument})`
to enable this check.

Uses `@test` internally (so it reports through any enclosing `@testset`), and also returns a `Bool`
so it can be checked directly (e.g. `@test test_mask_coverage(config)`).
"""
function test_mask_coverage(config::Pourfecto.Configuration; kinds=default_test_labware_kinds())
    rules = Pourfecto.mask_rules_for(config)
    if rules === nothing
        @warn "no mask_rules_for method defined for this configuration -- skipped by test_mask_coverage" maxlog=1
        return true
    end

    ok = true
    labware = Pourfecto.CHESSCore.build_location.(getindex.(Ref(Pourfecto.CHESSCore.location_kinds),kinds))
    for lw in labware
        k = Pourfecto.CHESSCore.kind(lw).name
        r,c = Pourfecto.CHESSCore.shape(lw)
        W = _well_index_matrix(r,c)
        mask = Pourfecto.Mask(Pourfecto.head(config),lw)

        for direction in (:aspirate,:dispense)
            rule_idx = findfirst(rule -> rule.direction==direction && (rule.kinds===:all || k in rule.kinds),rules)

            H = Pourfecto.compute_mask_sizes(Pourfecto.head(config),lw,direction)[1]
            Heff = Pourfecto.effective_head_size(Pourfecto.head(config),lw,direction)
            raw_C = direction == :aspirate ? size(Pourfecto.aspirate_channels(Pourfecto.head(config))) : size(Pourfecto.dispense_channels(Pourfecto.head(config)))
            raw_C = length(raw_C)==1 ? (raw_C[1],1) : raw_C
            P = direction == :aspirate ? Pourfecto.asp_positions(mask) : Pourfecto.disp_positions(mask)
            predicate = direction == :aspirate ? Pourfecto.asp(mask) : Pourfecto.disp(mask)

            actual = _tally_actual_visits(predicate,P,raw_C,W)
            expected = isnothing(rule_idx) ? zeros(Int,r,c) :
                _reference_visits(H,Heff,(r,c),rules[rule_idx].archetype;rules[rule_idx].kwargs...)
            result = @test actual == expected
            ok &= result isa Test.Pass
        end
    end
    return ok
end

"""
    test_json_roundtrip(config::Configuration) -> Bool

Verify that `config` survives a JSON serialize/deserialize round trip
(`json_to_config(config_to_json(config))`), catching serialization bugs in a custom instrument's
types before they surface at `Pourcast`-save time. Requires no optimizer.

`Configuration` has no `==` method (its `settings::Dict` field defaults to reference equality), so
this checks structural equivalence field-by-field instead of a single `==`: instrument type, `kind`,
deck (names/labware-kinds/slots per position), head (piston/channel counts and aspirate/dispense
masks), and `settings` keys.
"""
function test_json_roundtrip(config::Pourfecto.Configuration)
    j = Pourfecto.config_to_json(config)
    r = Pourfecto.json_to_config(j)

    ok = true
    ok &= (@test Pourfecto.get_config_type(r) == Pourfecto.get_config_type(config)) isa Test.Pass
    ok &= (@test r.kind === config.kind) isa Test.Pass
    ok &= (@test length(Pourfecto.deck(r)) == length(Pourfecto.deck(config))) isa Test.Pass
    for (dr,dc) in zip(Pourfecto.deck(r),Pourfecto.deck(config))
        ok &= (@test dr.name == dc.name) isa Test.Pass
        ok &= (@test Pourfecto.labware(dr) == Pourfecto.labware(dc)) isa Test.Pass
        ok &= (@test Pourfecto.slots(dr) == Pourfecto.slots(dc)) isa Test.Pass
    end
    hr,hc = Pourfecto.head(r), Pourfecto.head(config)
    ok &= (@test length(Pourfecto.pistons(hr)) == length(Pourfecto.pistons(hc))) isa Test.Pass
    ok &= (@test Pourfecto.aspirate_mask(hr) == Pourfecto.aspirate_mask(hc)) isa Test.Pass
    ok &= (@test Pourfecto.dispense_mask(hr) == Pourfecto.dispense_mask(hc)) isa Test.Pass
    ok &= (@test Set(keys(Pourfecto.settings(r))) == Set(keys(Pourfecto.settings(config)))) isa Test.Pass
    return ok
end

"""
    test_instrument_interface(config::Configuration; kwargs...) -> Bool

Convenience wrapper running all Tier-1 (no-solver) checks: [`test_mask_coverage`](@ref) and
[`test_json_roundtrip`](@ref). This is the recommended entry point for a quick, solver-free sanity
check on a newly-registered `Configuration` -- e.g. `@test test_instrument_interface(my_config)` in
your own package's test suite. `kwargs` are forwarded to `test_mask_coverage` (e.g. `kinds=...`).
"""
function test_instrument_interface(config::Pourfecto.Configuration; kwargs...)
    ok = true
    ok &= test_mask_coverage(config; kwargs...)
    ok &= test_json_roundtrip(config)
    return ok
end

"""
    test_pourcast_compilation(name::AbstractString, pourcast::Pourcast) -> Nothing

Solver-backed integration check: compiles `pourcast` to a temporary directory and asserts the
expected output structure (`pourcast.json`, a directory per config type, at least one non-empty
protocol subfolder per config with slotting requirements) -- verifies your instrument's
`write_instrument_files` method actually produces files, not just that its `Mask`/deck logic is
internally consistent.

This function does **not** run a solver itself -- `pourcast` must already be a *solved* `Pourcast`
(i.e. you called `pourfecto(...)` yourself with a real optimizer beforehand, e.g.
`pourfecto(...; optimizer=SCIP.Optimizer)` -- SCIP is already a Pourfecto dependency, or any other
JuMP-compatible MILP solver you have configured/licensed).

Runs inside its own `@testset "\$name"` block, so wrap the call in your own enclosing `@testset` if
you want it nested under a named group.
"""
function test_pourcast_compilation(name::AbstractString,pourcast::Pourfecto.Pourcast)
    @testset "$name" begin
        Random.seed!(1234)

        mktempdir() do outroot
            @test Pourfecto.compile(outroot, pourcast) === nothing

            @test isdir(outroot)
            @test isfile(joinpath(outroot, "pourcast.json"))

            cfgs = Pourfecto.configs(pourcast)
            @test !isempty(cfgs)
            config_slotting = slotting_requirements(pourcast)

            for c in eachindex(cfgs)
                if sum(config_slotting[c]) > 0
                    cfgtype = string(nameof(get_config_type(cfgs[c])))
                    cfgdir  = joinpath(outroot, cfgtype)
                    @test isdir(cfgdir)

                    protos = filter(name -> isdir(joinpath(cfgdir, name)), readdir(cfgdir))
                    @test length(protos) ≥ 1

                    for pname in protos
                        pdir = joinpath(cfgdir, pname)
                        @test length(readdir(pdir)) ≥ 1
                    end
                end
            end
        end
    end
    return nothing
end

export test_instrument_interface, test_mask_coverage, test_json_roundtrip, default_test_labware_kinds
export test_pourcast_compilation

end # module TestUtils
