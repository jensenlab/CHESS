# Shared harness for the CHESSDatabase reconstruction-scaling benchmarks. `include`d by scripts
# under CHESSDatabase/benchmarks/*/ -- not a package itself, mirroring the plain-script style of
# Pourfecto/benchmarks/*/generate_problem.jl.
#
# Builds lab fixtures against CHESSLabConstants (the registered template lab: real LocationKinds,
# reagents, and units -- no ad-hoc fixture registration needed, unlike
# CHESSDatabase/test/build_test_database.jl's custom TestChemOrg module) and drives them through
# CHESSDatabase's ledger via `upload`. Kinds/reagents/attributes registered by CHESSLabConstants are
# looked up with the collision-safe `loc"..."`/`rgt"..."`/`attr"..."` string macros, since
# `@location_kind`/`@reagent`/`@attribute` don't export the names they define.

using CHESSCore, CHESSDatabase, CHESSLabConstants, Unitful, Dates, Random

# CHESSLabConstants' own read kinds (Absorbance -> u"OD", Fluorescence -> u"RFU") use lab-specific
# units that Unitful.uparse can't resolve -- a pre-existing gap in reconstruct_reads! shared with
# reconstruct_attributes!/reconstruct_contents! (see CHESSDatabase/test/build_test_database.jl's
# comment on the same issue). Registering a standard-unit read kind here sidesteps it, exactly as
# that test fixture does.
@read BenchAbsorbance u"percent"

const DEPOSIT_QTY = 2.0u"µL"   # bottle (tier 0) -> intermediate well (tier 1)
const HOP_QTY = 0.5u"µL"       # intermediate well (tier 1) -> assay well (tier 2)
const CHAIN_HOP_QTY = 10.0u"µL"

"""
    fresh_db(path)

Remove `path` if it exists, create a new CHESS database there, and connect to it. Mirrors
CHESSDatabase/test/build_test_database.jl:1-8.
"""
function fresh_db(path)
    isfile(path) && rm(path)
    create_db(path)
    connect_SQLite(path)
    return path
end

"""
    RealisticLab

Handles into a simulated lab built by [`build_realistic_lab`](@ref): reagent bottles (tier 0),
intermediate plate wells (tier 1), assay plate wells (tier 2), a couple of ancestor locations whose
attributes can be changed, and two shelves a plate can be moved between. `tier1_ready` holds tier-1
wells that have received a tier-0 deposit and not yet been hopped onward -- each is popped (used at
most once as a hop source) by [`random_transfer!`](@ref), so a hop never has to guess whether a well
still holds enough to withdraw.
"""
struct RealisticLab
    lab::Location
    ancestors::Vector{Location}      # rotated through by random_env_change!
    bottles::Vector{CHESSCore.Well}  # tier 0
    intermediate_wells::Vector{CHESSCore.Well}  # tier 1
    assay_wells::Vector{CHESSCore.Well}         # tier 2
    shelf_a::Location
    shelf_b::Location
    mobile_plate::CHESSCore.Labware
    tier1_ready::Set{CHESSCore.Well}
end

"""
    build_realistic_lab(; n_bottles=20, n_intermediate_plates=60, n_assay_plates=20)

Build a location tree modeling a typical experiment: `n_bottles` reagent bottles, each holding a
distinct reagent, feeding `n_intermediate_plates` 96-well intermediate plates, which in turn feed
`n_assay_plates` assay plates -- default counts total 100 labware objects (bottles + plates),
matching the "~100 labware in a typical experiment" estimate. Also includes two ancestor locations
for environmental changes and two shelves for movement.

Every bottle's initial stock is set with `deposit!`/`cache` directly (not through the ledger), the
same pattern `CHESSDatabase/test/build_test_database.jl` uses for a well's starting content -- it
establishes a baseline the reconstruction algorithm can build forward from, without needing a
`Transfers` row for material that was never actually transferred into the bottle. Deliberately
deferred to *after* every other location in the lab has been created: `reconstruct_contents`
bootstraps an ancestor's cache using a query window lower-bounded by the *target's own* creation-time
cache point, so an ancestor cached earlier than a later-created target's own baseline is invisible to
that query and reconstructs as incorrectly empty. Caching every bottle last, once nothing else will
ever be created afterward, keeps every bottle's real cache point at or after every possible target's
own baseline, sidestepping that ordering trap for any well this lab ever reconstructs.
"""
function build_realistic_lab(; n_bottles::Int=20, n_intermediate_plates::Int=60, n_assay_plates::Int=20)
    lab = generate_location(loc"Lab", "Benchmark Lab")
    reagent_room = generate_location(loc"Room", "Reagent Room")
    intermediate_bench = generate_location(loc"Bench", "Intermediate Bench")
    assay_bench = generate_location(loc"Bench", "Assay Bench")
    shelf_a = generate_location(loc"Shelf", "Shelf A")
    shelf_b = generate_location(loc"Shelf", "Shelf B")
    upload(move_into!, lab, reagent_room)
    upload(move_into!, lab, intermediate_bench)
    upload(move_into!, lab, assay_bench)
    upload(move_into!, lab, shelf_a)
    upload(move_into!, lab, shelf_b)

    reagent_names = [:water, :acetic_acid, :butyric_acid, :diacetyl, :dmso, :ethanol,
                      :ethanolamine, :glycerol, :hydrogen_peroxide]
    bottles = CHESSCore.Well[]
    for i in 1:n_bottles
        bottle = generate_location(loc"Bottle1L", "Bottle $i")
        upload(move_into!, reagent_room, bottle)
        well = bottle[1, 1]
        reagent = getfield(CHESSLabConstants, reagent_names[mod1(i, length(reagent_names))])
        deposit!(well, 500_000u"µL" * reagent, 1)
        push!(bottles, well)
    end

    intermediate_wells = CHESSCore.Well[]
    mobile_plate = nothing
    for i in 1:n_intermediate_plates
        plate = generate_location(loc"WP96", "Intermediate Plate $i")
        upload(move_into!, intermediate_bench, plate)
        i == 1 && (mobile_plate = plate)
        append!(intermediate_wells, vec(children(plate)))
    end

    assay_wells = CHESSCore.Well[]
    for i in 1:n_assay_plates
        plate = generate_location(loc"WP96", "Assay Plate $i")
        upload(move_into!, assay_bench, plate)
        append!(assay_wells, vec(children(plate)))
    end

    cache.(bottles)  # see the docstring above for why this has to happen last

    return RealisticLab(lab, Location[lab, reagent_room, intermediate_bench, assay_bench],
        bottles, intermediate_wells, assay_wells, shelf_a, shelf_b, mobile_plate,
        Set{CHESSCore.Well}())
end

"""
    random_transfer!(rng, lab::RealisticLab)

Apply one transfer along the tier-0 (bottle) -> tier-1 (intermediate well) -> tier-2 (assay well)
DAG. Transfers never go backward or sideways within a tier, so the transfer-ancestor chain feeding
any well is at most 2 hops deep regardless of how many operations have run -- this is what makes the
"realistic" sweep safe to run to very high operation counts without the recursive ancestor query
degrading on chain *depth* (see [`ChainState`](@ref) for the scenario that isolates depth).

With some probability, hops a random tier-1 well that's ready (received at least one tier-0 deposit,
not yet hopped onward) to a random tier-2 well, withdrawing its *entire* current stock -- an exact
factor-1.0 drain, regardless of how many separate deposits (possibly of different reagents) it has
accumulated, which sidesteps floating-point residue that a fixed partial withdrawal can leave behind
after many multi-reagent top-ups. Otherwise tops up a random tier-1 well from a random tier-0 bottle
and marks it ready (idempotently -- a well already marked ready that gets topped up again just
accumulates more stock for its eventual single hop).
"""
function random_transfer!(rng::AbstractRNG, lab::RealisticLab; p_hop_to_assay::Real=0.3)
    if !isempty(lab.tier1_ready) && rand(rng) < p_hop_to_assay
        src = rand(rng, lab.tier1_ready)
        delete!(lab.tier1_ready, src)
        dst = rand(rng, lab.assay_wells)
        qty = CHESSCore.quantity(CHESSCore.stock(src))
        upload(transfer!, src, dst, qty)
    else
        src = rand(rng, lab.bottles)
        dst = rand(rng, lab.intermediate_wells)
        upload(transfer!, src, dst, DEPOSIT_QTY)
        push!(lab.tier1_ready, dst)
    end
    return nothing
end

"""
    random_move!(rng, lab::RealisticLab)

Move `lab.mobile_plate` to whichever of `shelf_a`/`shelf_b` it isn't currently in.
"""
function random_move!(rng::AbstractRNG, lab::RealisticLab)
    target = parent(lab.mobile_plate) === lab.shelf_a ? lab.shelf_b : lab.shelf_a
    upload(move_into!, target, lab.mobile_plate)
    return nothing
end

"""
    random_read!(rng, lab::RealisticLab)

Record a `BenchAbsorbance` read on a random assay well.
"""
function random_read!(rng::AbstractRNG, lab::RealisticLab)
    well = rand(rng, lab.assay_wells)
    upload(record_read!, well, BenchAbsorbance(rand(rng) * 100u"percent"))
    return nothing
end

"""
    random_env_change!(rng, lab::RealisticLab)

Set `Temperature` on a random ancestor location (rotates through `lab.ancestors`), exercising the
environment-inheritance chain every descendant well has to walk during reconstruction.
"""
function random_env_change!(rng::AbstractRNG, lab::RealisticLab)
    loc = rand(rng, lab.ancestors)
    upload(set_attribute!, loc, attr"Temperature"(20.0u"°C" + rand(rng) * 20 * u"K"))
    return nothing
end

"""
    run_operations!(rng, lab::RealisticLab, n::Int; weights=(transfer=1.0, move=0.0, read=0.0, env=0.0))

Apply `n` operations to `lab`, drawn independently from the given weighted mix of the four
generators above. `weights` need not sum to 1 -- they're normalized internally. Isolation sweeps set
one weight to `1.0`; the realistic sweep uses a mix approximating an actual day's work.
"""
function run_operations!(rng::AbstractRNG, lab::RealisticLab, n::Int;
        weights::NamedTuple=(transfer=1.0, move=0.0, read=0.0, env=0.0))
    kinds = collect(keys(weights))
    probs = collect(values(weights)) ./ sum(values(weights))
    cum = cumsum(probs)
    generators = Dict(:transfer => random_transfer!, :move => random_move!,
        :read => random_read!, :env => random_env_change!)
    for _ in 1:n
        r = rand(rng)
        idx = searchsortedfirst(cum, r)
        idx = min(idx, length(kinds))
        generators[kinds[idx]](rng, lab)
    end
    return nothing
end

"""
    ChainState

Handle into a growable linear transfer chain (see [`start_transfer_chain`](@ref)/
[`extend_chain!`](@ref)): a source bottle followed by wells `w1, w2, ...` where each `wi` is filled
entirely from `w[i-1]`. Isolates transfer-ancestor *chain depth* as a controlled variable, independent
of the DAG-restricted (depth <= 2) transfers `random_transfer!` produces -- see
`get_transfer_ancestors`'s recursive CTE in
CHESSDatabase/src/reconstruction/reconstruct_contents.jl, which walks exactly this kind of
`Source = previous Destination` chain backward from the target well.
"""
mutable struct ChainState
    room::Location
    tail::CHESSCore.Well
    spare_wells::Vector{CHESSCore.Well}  # pre-generated, not yet chained into
    n_done::Int
end

"""
    start_transfer_chain(max_n::Int)

Set up a transfer chain able to grow to `max_n` hops: a fresh `Lab`/`Room`, a source `Bottle1L`, and
enough WP384 plates (80 uL wells) pre-generated up front to supply `max_n` unique wells. Extend it
with [`extend_chain!`](@ref).

The source bottle's stock is `deposit!`ed/`cache`d directly (not through the ledger), the same
pattern `build_realistic_lab` uses -- and, like there, deliberately done *after* every WP384 plate
has already been generated, for the same reason documented on `build_realistic_lab`: caching the
source only once nothing else in this chain will ever be created keeps its real cache point at or
after every well's own creation-time baseline, which is what `reconstruct_contents`'s ancestor
bootstrap needs to actually find it. `max_n` has to be fixed up front (rather than growing plates
on demand as `extend_chain!` is called) specifically so this ordering can hold for every well in the
chain, not just the ones that existed when the source was cached.
"""
function start_transfer_chain(max_n::Int)
    lab = generate_location(loc"Lab", "Chain Lab")
    room = generate_location(loc"Room", "Chain Room")
    upload(move_into!, lab, room)

    bottle = generate_location(loc"Bottle1L", "Chain Source Bottle")
    upload(move_into!, room, bottle)
    source_well = bottle[1, 1]

    spare_wells = CHESSCore.Well[]
    for p in 1:cld(max_n, 384)
        plate = generate_location(loc"WP384", "Chain Plate $p")
        upload(move_into!, room, plate)
        append!(spare_wells, vec(children(plate)))
    end

    deposit!(source_well, 500_000u"µL" * CHESSLabConstants.water, 1)
    cache(source_well)  # last, once every plate above already exists -- see docstring

    return ChainState(room, source_well, spare_wells, 0)
end

"""
    extend_chain!(state::ChainState, n_additional::Int; hop_qty=CHAIN_HOP_QTY)

Extend `state`'s chain by `n_additional` more hops, drawn from the wells `start_transfer_chain`
pre-generated. Returns the new tail well -- the one whose reconstruction should be timed to measure a
chain of total length `state.n_done` (after this call).
"""
function extend_chain!(state::ChainState, n_additional::Int; hop_qty=CHAIN_HOP_QTY)
    n_additional <= length(state.spare_wells) ||
        error("chain exhausted its pre-generated wells -- raise max_n in start_transfer_chain")
    for _ in 1:n_additional
        w = popfirst!(state.spare_wells)
        upload(transfer!, state.tail, w, hop_qty)
        state.tail = w
    end
    state.n_done += n_additional
    return state.tail
end
