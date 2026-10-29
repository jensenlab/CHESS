# The observations lookup of a deep transfer chain reads key first. It once fell back to the whole-ledger
# `ledger_subset` query whenever the closure had more than LOCAL_KEY_LIMIT wells; `plan_reconstruction` now decides
# by the rows the wells own. A short chain with a lowered key limit takes the same route as the 5000-step chain.
# Every location is new (prefixed `dc`). Defines a recording `query_db` for the rest of the run, so this file is included last.

import CHESSDatabase: get_content_observations, _get_content_observations_global, get_transfer_ancestors, LOCAL_KEY_LIMIT, BULK_FRACTION

const DC_CAPTURE = Ref{Union{Nothing,Vector{Tuple{String,Any}}}}(nothing)
@eval CHESSDatabase begin
    function query_db(query::String)
        cap = Main.DC_CAPTURE[]; cap === nothing || push!(cap,(query,()))
        db=_require_db()
        DBInterface.execute(db, "PRAGMA foreign_keys = ON;")
        return DataFrame(DBInterface.execute(db, query))
    end
    function query_db(query::String, params)
        cap = Main.DC_CAPTURE[]; cap === nothing || push!(cap,(query,params))
        db=_require_db()
        DBInterface.execute(db, "PRAGMA foreign_keys = ON;")
        DataFrame(DBInterface.execute(db, query, params))
    end
end

dc_src = commit_location!(build_location(Bottle1L,"dc bottle"))
observe(dc_src[1,1],rgt"water",900u"mL")
dc_plate = generate_location(WP96,"dc plate")
dc_wells = [dc_plate[1,k] for k in 1:12]
upload(transfer!,dc_src[1,1],dc_wells[1],100u"µL")
for k in 1:11
    upload(transfer!,dc_wells[k],dc_wells[k+1],40u"µL")
end
dc_tail = location_id(dc_wells[12])

# the two "newest entry" lookups walk an index from the top and stop at the first row, so they are not scans in cost
dc_trivial = ("SELECT ID FROM Ledger WHERE Time <= ? ORDER BY ID DESC LIMIT 1",
              "SELECT SequenceID FROM Ledger WHERE Time <= ? ORDER BY SequenceID DESC LIMIT 1")

@testset "deep chain: the observations lookup reads key first" begin
    old = LOCAL_KEY_LIMIT[]
    LOCAL_KEY_LIMIT[] = 5                                       # the chain has more wells than the limit
    try
        now_ = Dates.now(); last_ = get_last_sequence_id()
        transfers = get_transfer_ancestors([dc_tail],0,last_,now_)
        core = Set{Int}([dc_tail])
        for row in eachrow(transfers)
            row.Core == 1 && union!(core,ismissing(row.Destination) ? (row.Source,) : (row.Source,row.Destination))
        end
        core = sort!(collect(core))
        @test length(core) > LOCAL_KEY_LIMIT[]

        plan = plan_reconstruction(core;kind=:observations)
        @test plan.path === :local
        @test plan.rows == 1                                    # the one observation, on the source bottle's well
        @test plan.fraction < BULK_FRACTION[]
        @test !CHESSDatabase._use_global(false,core;kind=:observations)

        # forced global and the local lookup return the same rows
        loc = get_content_observations(core,0,last_,now_)
        glob = _get_content_observations_global(core,0,last_,now_)
        @test nrow(loc) == 1
        @test isequal(loc,glob)

        # the SQL of the whole reconstruction
        DC_CAPTURE[] = Tuple{String,Any}[]
        try
            reconstruct_contents(dc_tail)
        finally
            captured = DC_CAPTURE[]; DC_CAPTURE[] = nothing
            global dc_captured = captured
        end
        sqls = unique(first.(dc_captured))
        @test !isempty(sqls)
        @test !any(s -> occursin("ledger_subset",s),sqls)
        scans = String[]
        seen = Set{String}()
        for (sql,params) in dc_captured
            (sql in seen || strip(sql) in dc_trivial) && continue
            push!(seen,sql)
            occursin(r"^\s*(SELECT|WITH)"i,sql) || continue
            plan_lines = String.(query_db("EXPLAIN QUERY PLAN " * sql,params).detail)
            append!(scans,filter(l -> occursin(r"^SCAN (Ledger|vl|l)\b",l),plan_lines))
        end
        @test isempty(scans)
    finally
        LOCAL_KEY_LIMIT[] = old
    end
end
