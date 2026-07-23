
"""
    get_reads(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now())

Return every `Reads` row for `location_id` up to `sequence_id`/`time`, as a `DataFrame`. Unlike
`get_*_caches` (e.g. [`get_attribute_caches`](@ref)), there is no latest-wins collapsing here -- reads
never supersede each other, only accumulate (see [`Read`](@ref)'s docstring).
"""
function get_reads(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now())
    ledger_time=db_time(time)
    return query_db("""
        SELECT r.* FROM Reads r INNER JOIN Ledger l ON r.LedgerID = l.ID
        WHERE l.SequenceID BETWEEN 0 AND ? AND l.Time <= ? AND r.LocationID = ?
        """,(sequence_id,ledger_time,location_id))
end

_reads_sort_key(row) = something(row.InstrumentTime,row.Time)

"""
    reconstruct_reads!(loc::Location,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)

Populate `loc`'s [`reads`](@ref) collection from the database, up to `sequence_id`/`time`, sorted by
`InstrumentTime` (falling back to the upload `Time` when `InstrumentTime` is unavailable) -- the sort
is what makes `reads(loc)` interpretable as a time series. `max_cache`/`encumbrances` are accepted (and
ignored) purely so [`reconstruct_location!`](@ref) can call every `reconstruct_*!` uniformly -- reads
have no cache/encumbrance layer (see [`get_reads`](@ref)).
"""
function reconstruct_reads!(loc::Location,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)
    rows=get_reads(CHESSCore.location_id(loc),sequence_id,time)
    for row in sort(collect(eachrow(rows));by=_reads_sort_key)
        rk=read_kinds[Symbol(row.Type)]
        val = ismissing(row.Value) ? missing :
              ismissing(row.Unit)  ? row.Value :
              parse(Float64,row.Value)*Unitful.uparse(row.Unit)
        rd_time = ismissing(row.InstrumentTime) ? nothing : julia_time(row.InstrumentTime)
        record_read!(loc,rk(val,rd_time))
    end
    return nothing
end

"""
    reconstruct_reads(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)

Reconstruct a location by `location_id` and populate its [`reads`](@ref). See [`reconstruct_reads!`](@ref).
"""
function reconstruct_reads(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)
    n,t=get_location_info(location_id)
    loc=t(location_id,n)
    reconstruct_reads!(loc,sequence_id,time,max_cache;encumbrances=encumbrances)
    return loc
end
