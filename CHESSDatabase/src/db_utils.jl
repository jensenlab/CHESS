const _current_db = Ref{Union{Nothing,SQLite.DB}}(nothing)

function _require_db()
    db = _current_db[]
    db === nothing && error("use connect_SQLite to connect to a database")
    return db
end

function connect_SQLite(path)
    _current_db[] = SQLite.DB(path)
    return nothing
end

function execute_db(query::String)
    db=_require_db()
    DBInterface.execute(db, "PRAGMA foreign_keys = ON;") # when you open a connection, it defaults to turning foreign key constraints off.
    SQLite.execute(db, query)
end

function query_db(query::String)
    db=_require_db()
    DBInterface.execute(db, "PRAGMA foreign_keys = ON;") # when you open a connection, it defaults to turning foreign key constraints off.
    return DataFrame(DBInterface.execute(db, query))
end

function execute_db(query::String, params)
    db=_require_db()
    DBInterface.execute(db, "PRAGMA foreign_keys = ON;")
    SQLite.execute(db, query, params)
end

function query_db(query::String, params)
    db=_require_db()
    DBInterface.execute(db, "PRAGMA foreign_keys = ON;")
    DataFrame(DBInterface.execute(db, query, params))
end

function sql_transaction(f::Function)
    db=_require_db()
    SQLite.transaction(f,db)
end

function sql_commit(name::String)
    db=_require_db()
    SQLite.commit(db,name)
end

function sql_rollback(name::String)
    db=_require_db()
    SQLite.rollback(db,name)
end



function query_join_vector(entry::Vector{<:Number})
    return string("(",join(entry,","),")")
end

"""
    query_join_vector(entry::Vector{String})

Return `("(?,?,...)", Tuple(entry))` -- a parameterized `IN (...)` clause fragment (one `?` per
element) alongside the params to pass to [`execute_db`](@ref)/[`query_db`](@ref), instead of joining
raw strings directly into SQL text.
"""
function query_join_vector(entry::Vector{String})
    return string("(",join(fill("?",length(entry)),","),")"), Tuple(entry)
end


function db_time(time::Dates.DateTime)
    return Dates.datetime2unix(time)
end 


function julia_time(time::Float64)
    return Dates.unix2datetime(time)
end 

function get_all_attributes()
    x="SELECT * FROM Attributes"
    return query_db(x)
end

"""
    sql_where(pairs::Pair{String}...)

Build a parameterized WHERE-clause fragment from `(column, value)` pairs, returning
`(sql_fragment, params)` -- pass `sql_fragment` in the query text and `params` as
[`execute_db`](@ref)/[`query_db`](@ref)'s second argument. `missing` compiles to `"col IS NULL"` with
no bound parameter (`= ?` never matches `NULL` under SQL's three-valued logic, whether the `NULL`
comes from a literal or a bound value); every other value compiles to `"col = ?"` with the value
collected into `params`.
"""
function sql_where(pairs::Pair{String}...)
    conds = String[]
    params = Any[]
    for (col,val) in pairs
        if ismissing(val)
            push!(conds, "$col IS NULL")
        else
            push!(conds, "$col = ?")
            push!(params, val)
        end
    end
    return join(conds," AND "), Tuple(params)
end

"""
    hash_bytes(x)

Return `hash(x)` (a `UInt64`) as its raw 8 bytes (`Vector{UInt8}`), for binding as a `BLOB` parameter
in hash-dedup columns (`CachedStocks`/`CachedChildSets`/`CachedAttributeSets`). Binding this directly
(rather than interpolating `hash(x)` as a bare numeric literal) stores and compares the exact 64-bit
value regardless of magnitude -- interpolating a `UInt64` above `typemax(Int64)` as a literal silently
loses precision (SQLite coerces it to `REAL`).
"""
hash_bytes(x) = reinterpret(UInt8,[hash(x)])