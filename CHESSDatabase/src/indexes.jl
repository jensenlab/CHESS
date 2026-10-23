#=
Indexes that make a reconstruction cost depend on the history of the location it rebuilds instead of
on the size of the whole ledger. Without them every `ledger_subset` query scans `Ledger` and the
operation tables in full, and `get_last_sequence_id` (the default argument of every reconstruction)
scans `Ledger`.

The list below is the single definition: `create_db` creates it on a new database, `connect_SQLite`
adds it to an existing small database, and `create_indexes!` / `drop_indexes!` add or remove it by
hand. Every index is named `idx_chess_<table>_<columns>`; `drop_indexes!` removes only those, so
indexes made by other tools (for example the inventory's `idx_perf_*`) are never touched.
=#

# (table, columns). `Ledger(SequenceID, ID)` serves `get_last_sequence_id`, `visible_ledger_id` and the
# `visible_join` probe. A column written with parentheses is an expression (the Reads paging index).
const CHESS_INDEXES = Tuple{String,Vector{String}}[
    ("Ledger",["SequenceID","ID"]),

    ("Transfers",["Source","LedgerID"]),
    ("Transfers",["Destination","LedgerID"]),
    ("Transfers",["LedgerID"]),
    ("Movements",["Child","LedgerID"]),
    ("Movements",["Parent","LedgerID"]),
    ("Movements",["LedgerID"]),
    ("EnvironmentAttributes",["LocationID","Attribute","LedgerID"]),
    ("EnvironmentAttributes",["LedgerID"]),
    ("Locks",["LocationID","LedgerID"]),
    ("Activity",["LocationID","LedgerID"]),
    ("Reads",["LocationID","LedgerID"]),
    ("Reads",["LocationID","COALESCE(InstrumentTime, Time)"]),
    ("InstrumentSettings",["InstrumentID","Setting","LedgerID"]),

    ("ObservedParents",["Child","LedgerID"]),
    ("ObservedParents",["Parent","LedgerID"]),
    ("ObservedAttributes",["LocationID","Attribute","LedgerID"]),
    ("ObservedLocks",["LocationID","LedgerID"]),
    ("ObservedActivity",["LocationID","LedgerID"]),
    ("ObservedComponents",["LocationID","LedgerID"]),
    ("ObservedCosts",["LocationID","LedgerID"]),

    ("CachedContents",["LocationID","LedgerID"]),
    ("CachedAncestors",["LocationID","LedgerID"]),
    ("CachedDescendants",["LocationID","LedgerID"]),
    ("CachedEnvironments",["LocationID","LedgerID"]),
    ("CachedLockActivity",["LocationID","LedgerID"]),
    ("CachedChildren",["CachedChildSetID"]),
    ("CachedAttributes",["AttributeSetID"]),
    ("CachedComponents",["StockID"]),
    ("CachedStocks",["StockHash"]),
    ("CachedChildSets",["ChildSetHash"]),
    ("CachedAttributeSets",["AttributeSetHash"]),

    ("ProtocolEnforcement",["ProtocolID","LedgerID"]),
    ("EncumbranceCompletion",["EncumbranceID"]),
    ("EncumberedTransfers",["Source"]),
    ("EncumberedTransfers",["Destination"]),
    ("EncumberedTransfers",["EncumbranceID"]),
    ("EncumberedMovements",["EncumbranceID"]),
    ("EncumberedEnvironments",["EncumbranceID"]),
    ("EncumberedLocks",["EncumbranceID"]),
    ("EncumberedActivity",["EncumbranceID"]),
    ("EncumberedCachedContents",["EncumbranceID"]),
    ("EncumberedCachedAncestors",["EncumbranceID"]),
    ("EncumberedCachedDescendants",["EncumbranceID"]),
    ("EncumberedCachedEnvironments",["EncumbranceID"]),
    ("EncumberedCachedLockActivity",["EncumbranceID"]),

    ("Locations",["Name"]),
    ("Locations",["Type"]),
    ("Barcodes",["LocationID"]),
]

# Above this many ledger rows `connect_SQLite` does not build indexes by itself (decision D2): building
# them on a large database takes minutes to hours.
const AUTO_INDEX_LEDGER_ROWS = Ref(1_000_000) # a Ref so a test can lower it

_is_expression(col::AbstractString) = occursin('(',col)

_slug(c::AbstractString) = lowercase(strip(replace(c,r"[^A-Za-z0-9]+"=>"_"),'_'))
_index_name(table::AbstractString,cols::Vector{String}) = "idx_chess_" * lowercase(table) * "_" * join(_slug.(cols),"_")

_index_sql(table::AbstractString,cols::Vector{String}) =
    "CREATE INDEX IF NOT EXISTS $(_index_name(table,cols)) ON $table($(join(cols,", ")))"

# Raw-connection helpers, so the same code runs inside `create_db` (no current database yet) and on
# the connected database.
_rows(db,sql) = DBInterface.execute(db,sql) |> DataFrame
_db_table_exists(db,table) = nrow(_rows(db,"SELECT 1 FROM sqlite_master WHERE type='table' AND name='$table'")) > 0
_db_columns(db,table) = String.(_rows(db,"SELECT name FROM pragma_table_info('$table')").name)

# Column lists (in index order; `missing` for an expression) of every index on `table`.
function _existing_index_columns(db,table)
    out = Vector{Vector{Union{Missing,String}}}()
    for idx in eachrow(_rows(db,"SELECT name FROM pragma_index_list('$table')"))
        info = _rows(db,"SELECT name FROM pragma_index_info('$(idx.name)') ORDER BY seqno")
        push!(out,Vector{Union{Missing,String}}(info.name))
    end
    return out
end

# True when a usable index is already there: some existing index whose leading columns are exactly `cols`.
# An index built by another tool (the inventory's `idx_perf_*`) therefore counts, and no duplicate is made.
function _index_satisfied(existing::Vector{Vector{Union{Missing,String}}},cols::Vector{String})
    _is_expression(first(cols)) && return false
    for e in existing
        length(e) >= length(cols) || continue
        all(i -> !ismissing(e[i]) && lowercase(e[i]) == lowercase(cols[i]),eachindex(cols)) && return true
    end
    return false
end

# The CHESS_INDEXES entries still missing on `db`. A table or column the database lacks is skipped.
function _missing_indexes(db)
    todo = Tuple{String,Vector{String}}[]
    names = Set(String.(_rows(db,"SELECT name FROM sqlite_master WHERE type='index'").name))
    for (table,cols) in CHESS_INDEXES
        _index_name(table,cols) in names && continue
        _db_table_exists(db,table) || continue
        have = _db_columns(db,table)
        plain = filter(!_is_expression,cols)
        all(c -> c in have,plain) || continue
        # an expression index is judged only on the plain columns it mentions
        if any(_is_expression,cols)
            mentioned = [m.match for c in filter(_is_expression,cols) for m in eachmatch(r"[A-Za-z_]\w*",c)]
            all(c -> c in have || uppercase(c) in ("COALESCE",),mentioned) || continue
        end
        _index_satisfied(_existing_index_columns(db,table),cols) && continue
        push!(todo,(table,cols))
    end
    return todo
end

function _create_indexes!(db;progress::Bool=false)
    todo = _missing_indexes(db)
    t0 = time()
    for (i,(table,cols)) in enumerate(todo)
        t = time()
        DBInterface.execute(db,_index_sql(table,cols))
        progress && println("[$i/$(length(todo))] $(_index_name(table,cols)) ($(round(time()-t;digits=2)) s)")
    end
    if !isempty(todo)
        # the planner needs statistics for the new indexes to prefer them; sampled, so cheap on a large database
        DBInterface.execute(db,"PRAGMA analysis_limit = 1000")
        DBInterface.execute(db,"PRAGMA optimize(0x10002)")
        progress && println("created $(length(todo)) indexes in $(round(time()-t0;digits=2)) s")
    end
    return [_index_name(t,c) for (t,c) in todo]
end

"""
    create_indexes!(; progress=true) -> Vector{String}

Create the indexes that make reconstruction cost depend on a location's own history instead of the
size of the ledger, on the connected database, and return the names of the ones created. An index is
skipped when the table or a column is missing, or when an index with the same leading columns already
exists (for example one made by another tool). Statistics are refreshed afterwards (`PRAGMA optimize`).

[`connect_SQLite`](@ref) does this by itself for a database with fewer than 1,000,000
ledger rows. Build time grows with the database; `progress=true` prints each index as it finishes.
[`drop_indexes!`](@ref) removes them again.
"""
create_indexes!(;progress::Bool=true) = _create_indexes!(_require_db();progress=progress)

"""
    drop_indexes!() -> Vector{String}

Drop every index named `idx_chess_*` from the connected database (the ones [`create_indexes!`](@ref)
and [`create_db`](@ref) make) and return their names. Indexes with any other name are left alone.
"""
function drop_indexes!()
    db = _require_db()
    names = String.(_rows(db,"SELECT name FROM sqlite_master WHERE type='index' AND substr(name,1,10)='idx_chess_'").name)
    for n in names
        DBInterface.execute(db,"DROP INDEX IF EXISTS $n")
    end
    return names
end

const _warned_unindexed = Set{String}()

# Called by `connect_SQLite`. A small database gets the indexes at once; a large one is only warned about,
# once per file, because building them can take a long time.
function _ensure_indexes!()
    db = _require_db()
    try
        todo = _missing_indexes(db)
        isempty(todo) && return nothing
        rows = coalesce(_rows(db,"SELECT Max(ID) AS n FROM Ledger").n[1],0) # rowid: an upper bound on the row count, in O(1)
        if rows < AUTO_INDEX_LEDGER_ROWS[]
            _create_indexes!(db)
        elseif !(db.file in _warned_unindexed)
            push!(_warned_unindexed,db.file)
            @warn "This database has $rows ledger rows and is missing $(length(todo)) CHESS indexes, so reconstruction scans the whole ledger. Run create_indexes!() to build them (this can take a long time)."
        end
    catch err
        @warn "Could not check or create the CHESS indexes" exception=err
    end
    return nothing
end
