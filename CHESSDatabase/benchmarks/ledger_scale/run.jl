# Smoke / baseline benchmark of the reconstruction queries against a synthetic ledger of N rows.
#
#   julia --project=CHESSDatabase CHESSDatabase/benchmarks/ledger_scale/run.jl
#
# Environment: BENCH_N (ledger rows, default 200000), BENCH_DIR (where the databases go, default a folder in
# the temp directory; never inside the repository), BENCH_OUT (results folder, default ./results),
# BENCH_VARIANTS (default "noidx,idx,cover"), BENCH_TARGETS (targets per query class, default 8).
#
# Variants of the same database:
#   noidx  the database as it was before the CHESS indexes (only the indexes create_db always made)
#   idx    + the idx_chess_* set of src/indexes.jl (Ledger index = (SequenceID, ID))
#   cover  the same with the Ledger index (SequenceID, ID, Time), for the comparison of decision D3
#   ledgeronly  only Ledger(SequenceID, ID), to separate its cost from that of the other indexes
#
# For every query it records p50/p95 wall time over BENCH_TARGETS random targets and EXPLAIN QUERY PLAN of the
# SQL the function ran, so a later phase can show that `SCAN Ledger` / `MATERIALIZE ledger_subset` are gone
# and that time stops growing with N. It also records the database size, the latency of appending an
# operation, and the time of a mid-ledger insert (which renumbers every later slot) per variant.
# Only the smoke size (200k) is meant to run in phase work; 500k and 1M belong to the final run.
#
# Output: results/baseline_<N>.csv (query timings and plan flags), results/costs_<N>.csv (size, append latency,
# mid insert, last-sequence-id time), results/plans_<N>.txt (the full plans).

using CHESSCore, CHESSDatabase, Unitful, DataFrames, Dates, Statistics, Random, SQLite, DBInterface, CSV, Printf, Logging

include("generate.jl")

const BENCH_N = parse(Int,get(ENV,"BENCH_N","200000"))
const BENCH_DIR = get(ENV,"BENCH_DIR",joinpath(tempdir(),"chess_ledger_scale"))
const BENCH_OUT = get(ENV,"BENCH_OUT",joinpath(@__DIR__,"results"))
const BENCH_VARIANTS = split(get(ENV,"BENCH_VARIANTS","noidx,idx,cover"),",")
const BENCH_TARGETS = parse(Int,get(ENV,"BENCH_TARGETS","8"))
const BENCH_RUNS = parse(Int,get(ENV,"BENCH_RUNS","0"))               # repeats per target (0: 3, heavy queries 2)
const BENCH_ONLY = Regex(get(ENV,"BENCH_ONLY",".*"))                     # run only the queries whose name matches
const BENCH_SKIP_QUERIES = get(ENV,"BENCH_SKIP_QUERIES","0") == "1"   # only the size and write costs

# location kinds the generated database uses
@location_kind Room Symbol[] nothing nothing nothing nothing nothing 0//1 0//1
@location_kind Incubator Symbol[] nothing nothing nothing nothing nothing 0//1 0//1
@location_kind Well200 Symbol[] nothing nothing 200u"µL" nothing nothing
@location_kind Reservoir Symbol[] nothing nothing 1000000000u"µL" nothing nothing
@location_kind WP96 [:Plate] (8,12) :Well200 nothing "Thermo" "123456"
@attribute Temperature u"°C"
@attribute Humidity u"percent"

# record the SQL the package runs, to explain it afterwards
const CAPTURE = Ref{Union{Nothing,Vector{Tuple{String,Any}}}}(nothing)
@eval CHESSDatabase begin
    function query_db(query::String)
        cap = Main.CAPTURE[]; cap === nothing || push!(cap,(query,()))
        db=_require_db()
        DBInterface.execute(db, "PRAGMA foreign_keys = ON;")
        return DataFrame(DBInterface.execute(db, query))
    end
    function query_db(query::String, params)
        cap = Main.CAPTURE[]; cap === nothing || push!(cap,(query,params))
        db=_require_db()
        DBInterface.execute(db, "PRAGMA foreign_keys = ON;")
        DataFrame(DBInterface.execute(db, query, params))
    end
end

ms(t) = 1000t
function timeit(f,runs)
    f()                                   # warm the page cache and compile
    return [(@elapsed f()) for _ in 1:runs]
end
q50(x) = quantile(x,0.5); q95(x) = quantile(x,0.95)

# --------------------------------------------------------------------------------------------- the queries

function targets(lay,rng)
    pick(r,n=BENCH_TARGETS) = rand(rng,r,n)
    chain(col) = [lay.exp_base + rand(rng,0:lay.n_exp-2)*96 + rand(rng,0:7)*12 + col for _ in 1:BENCH_TARGETS]
    return (
        incubator = pick(lay.incubators), room = pick(lay.rooms), reservoir = pick(lay.reservoirs[1:5]), instrument = pick(1:3),
        plate = pick(lay.plates), plate_well = pick(lay.plate_wells),
        chain1 = chain(1), chain6 = chain(6), chain12 = chain(11),
    )
end

# (name, target class, heavy?, call(id))
function query_list(seq)
    now_ = Dates.now()
    vec(x) = [x]
    return [
        ("get_content_caches","chain12",false,id->CHESSDatabase.get_content_caches(id,0,seq,now_)),
        ("get_parent_caches","plate",false,id->CHESSDatabase.get_parent_caches(id,0,seq,now_)),
        ("get_child_caches","plate",false,id->CHESSDatabase.get_child_caches(id,0,seq,now_)),
        ("get_attribute_caches","room",false,id->CHESSDatabase.get_attribute_caches(id,0,seq,now_)),
        ("get_lock_caches","plate",false,id->CHESSDatabase.get_lock_caches(id,0,seq,now_)),
        ("get_activity_caches","plate",false,id->CHESSDatabase.get_activity_caches(id,0,seq,now_)),
        ("get_last_movement_as_child","plate",false,id->CHESSDatabase.get_last_movement_as_child(vec(id),0,seq,now_)),
        ("get_last_movements_as_parent","incubator",false,id->CHESSDatabase.get_last_movements_as_parent(vec(id),0,seq,now_)),
        ("get_locks","plate",false,id->CHESSDatabase.get_locks(vec(id),0,seq,now_)),
        ("get_activity","plate",false,id->CHESSDatabase.get_activity(vec(id),0,seq,now_)),
        ("get_environment_attributes","room",false,id->CHESSDatabase.get_environment_attributes(vec(id),0,seq,now_)),
        ("get_environment_attributes","incubator",false,id->CHESSDatabase.get_environment_attributes(vec(id),0,seq,now_)),
        ("get_transfer_ancestors","chain1",true,id->CHESSDatabase.get_transfer_ancestors(vec(id),0,seq,now_)),
        ("get_transfer_ancestors","chain6",true,id->CHESSDatabase.get_transfer_ancestors(vec(id),0,seq,now_)),
        ("get_transfer_ancestors","chain12",true,id->CHESSDatabase.get_transfer_ancestors(vec(id),0,seq,now_)),
        ("get_transfer_descendents","chain6",true,id->CHESSDatabase.get_transfer_descendents(vec(id),0,seq,now_)),
        ("get_transfer_descendents","reservoir",true,id->CHESSDatabase.get_transfer_descendents(vec(id),0,seq,now_)),
        ("get_instrument_settings","instrument",false,id->CHESSDatabase.get_instrument_settings(id,seq,now_)),
        ("get_reads","plate_well",false,id->CHESSDatabase.get_reads(id,seq,now_)),
        ("get_content_observations","chain6",false,id->CHESSDatabase.get_content_observations(vec(id),0,seq,now_)),
        ("reconstruct_environment","room",false,id->CHESSDatabase.reconstruct_environment(id,seq,now_)),
        ("reconstruct_lock","plate",false,id->CHESSDatabase.reconstruct_lock(id,seq,now_)),
        ("reconstruct_activity","plate",false,id->CHESSDatabase.reconstruct_activity(id,seq,now_)),
        ("reconstruct_parent","plate",false,id->CHESSDatabase.reconstruct_parent(id,seq,now_)),
        ("reconstruct_lot","plate",false,id->CHESSDatabase.reconstruct_lot(id,seq,now_)),
        ("find_locations(parent)","incubator",false,id->CHESSDatabase.find_locations(;parent=id,sequence_id=seq,time=now_)),
        ("descendants","incubator",false,id->CHESSDatabase.descendants(id;sequence_id=seq,time=now_)),
        ("trace_forward(well)","chain6",true,id->CHESSDatabase.trace_forward(id,seq,now_)),
        ("reconstruct_contents","chain12",true,id->CHESSDatabase.reconstruct_contents(id,seq,now_)),
        ("reconstruct_contents","chain1",true,id->CHESSDatabase.reconstruct_contents(id,seq,now_)),
    ]
end

# reservoirs need real contents for reconstruct_contents to replay transfers out of them
function stock_reservoirs!(lay)
    water = Liquid("bench water",18.015u"g/mol",1.0u"g/mL")
    sid = CHESSDatabase.cache(5.0e8u"µL"*water)
    for r in lay.reservoirs
        execute_db("INSERT INTO CachedContents(LocationID,StockID,LedgerID,Time) Values(?,?,?,?)",(r,sid,1,LS_ORIGIN))
    end
end

function plan_of(sql,params)
    CAPTURE[] = nothing
    plan = query_db("EXPLAIN QUERY PLAN " * sql,params)
    return String.(plan.detail)
end

function run_queries(variant,lay)
    rng = Xoshiro(2026)
    t = targets(lay,rng)
    seq = get_last_sequence_id()
    rows = NamedTuple[]
    plans = String[]
    for (name,cls,heavy,call) in query_list(seq)
        occursin(BENCH_ONLY,name) || continue
        ids = getproperty(t,Symbol(cls))
        runs = BENCH_RUNS > 0 ? BENCH_RUNS : (heavy ? 2 : 3)
        samples = Float64[]; mins = Float64[]
        for id in ids
            s_id = timeit(()->call(id),runs)
            append!(samples,s_id); push!(mins,minimum(s_id))
        end
        # the SQL this function ran
        CAPTURE[] = Tuple{String,Any}[]
        call(ids[1])
        captured = CAPTURE[]; CAPTURE[] = nothing
        sqls = unique(first.(captured))
        plan_lines = String[]
        for (sql,params) in unique(captured)
            occursin("SELECT",sql) || continue
            lines = try
                plan_of(sql,params)
            catch err
                ["(plan unavailable: $(typeof(err)))"]
            end
            append!(plan_lines,lines)
        end
        # a scan of the whole Ledger table (or of its copy ledger_subset) that no index orders or bounds. The tick walk of
        # latest_visible_event scans Ledger through its index and stops at the first hit, which is not counted.
        scan_ledger = any((occursin(r"^SCAN (Ledger|vl|l|ledger_subset)\b",l) && !occursin("INDEX",l)) for l in plan_lines)
        materializes = any(occursin("MATERIALIZE ledger_subset",l) for l in plan_lines)
        n_chess = count(l->occursin("idx_chess",l),plan_lines)
        push!(rows,(; n=lay.N,variant,query=name,target=cls,targets=length(ids),runs,p50_ms=ms(q50(samples)),p95_ms=ms(q95(samples)),p50_of_min_ms=ms(q50(mins)),
            plan_scans_ledger=scan_ledger,plan_materializes_ledger_subset=materializes,plan_chess_index_uses=n_chess,sql_statements=length(sqls)))
        push!(plans,"=== $variant | $name | $cls\n" * join(plan_lines,"\n") * "\n")
        @printf("%-6s %-32s %-10s p50 %9.3f ms  p95 %9.3f ms  scan-ledger=%s cte=%s\n",variant,name,cls,ms(q50(samples)),ms(q95(samples)),scan_ledger,materializes)
    end
    return DataFrame(rows),plans
end

# ------------------------------------------------------------------------------------------------ costs

function run_costs(variant,path,lay)
    # last sequence id and last ledger id, 1000 calls each
    tseq = timeit(()->get_last_sequence_id(),1000)
    tled = timeit(()->get_last_ledger_id(),1000)
    tseq_past = timeit(()->get_last_sequence_id(Dates.unix2datetime(LS_ORIGIN + 0.7*lay.N*0.01)),50)  # a time-travel cutoff
    size_mb = filesize(path)/2^20
    # appending an operation: upload (one transaction), and update (append with validation and cache repair)
    room = reconstruct_location(first(lay.rooms))
    up = [(@elapsed upload(set_attribute!,room,Temperature((10+i%30)*u"°C"))) for i in 1:200]
    upd = [(@elapsed update(set_attribute!,room,Temperature((10+i%30)*u"°C"))) for i in 1:10]
    # a mid-ledger insert renumbers every later slot
    ins = @elapsed insert_ledger(2)
    return (; n=lay.N,variant,size_mb,last_sequence_id_us_p50=1e6*q50(tseq),last_ledger_id_us_p50=1e6*q50(tled),
        last_sequence_id_past_time_us_p50=1e6*q50(tseq_past),upload_ms_p50=ms(q50(up)),upload_ms_p95=ms(q95(up)),
        update_ms_p50=ms(q50(upd)),insert_ledger_s=ins)
end

# ------------------------------------------------------------------------------------------------- main

function prepare_variant(variant,base,path)
    cp(base,path;force=true)
    saved = CHESSDatabase.AUTO_INDEX_LEDGER_ROWS[]
    if variant in ("noidx","ledgeronly")
        CHESSDatabase.AUTO_INDEX_LEDGER_ROWS[] = 0          # connect_SQLite must not add them
        with_logger(NullLogger()) do; connect_SQLite(path); end
        variant == "ledgeronly" && execute_db("CREATE INDEX idx_chess_ledger_sequenceid_id ON Ledger(SequenceID, ID)")
    else
        connect_SQLite(path)                                  # adds the idx_chess_* set below 1M rows
        if variant == "cover"
            execute_db("DROP INDEX idx_chess_ledger_sequenceid_id")
            execute_db("CREATE INDEX idx_chess_ledger_sequenceid_id_time ON Ledger(SequenceID, ID, Time)")
            execute_db("PRAGMA optimize(0x10002)")
        end
    end
    CHESSDatabase.AUTO_INDEX_LEDGER_ROWS[] = saved
end

function main()
    mkpath(BENCH_DIR); mkpath(BENCH_OUT)
    base = joinpath(BENCH_DIR,"ledger_$(BENCH_N)_base.db")
    lay = ls_layout(BENCH_N)
    if !isfile(base)
        t = @elapsed counts = generate_ledger_scale(base,BENCH_N)
        println("generated $base in $(round(t;digits=1)) s: $counts")
    end
    all_rows = DataFrame[]; all_plans = String[]; costs = NamedTuple[]
    for variant in BENCH_VARIANTS
        path = joinpath(BENCH_DIR,"ledger_$(BENCH_N)_$variant.db")
        prepare_variant(variant,base,path)
        stock_reservoirs!(lay)
        println("\n== $variant: $(round(filesize(path)/2^20;digits=1)) MB, $(length(String.(query_db("SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx\\_chess\\_%' ESCAPE '\\'").name))) CHESS indexes")
        if !BENCH_SKIP_QUERIES
            df,plans = run_queries(variant,lay)
            push!(all_rows,df); append!(all_plans,plans)
        end
        push!(costs,run_costs(variant,path,lay))   # last: it modifies the ledger
        println(costs[end])
    end
    isempty(all_rows) || CSV.write(joinpath(BENCH_OUT,"baseline_$(BENCH_N).csv"),reduce(vcat,all_rows))
    CSV.write(joinpath(BENCH_OUT,"costs_$(BENCH_N).csv"),DataFrame(costs))
    isempty(all_plans) || write(joinpath(BENCH_OUT,"plans_$(BENCH_N).txt"),join(all_plans,"\n"))
    println("\nwrote results to $BENCH_OUT")
end

abspath(PROGRAM_FILE) == (@__FILE__) && main()
