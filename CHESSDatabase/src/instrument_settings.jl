
"""
    get_instrument_settings(instrument_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now())

Resolve `instrument_id`'s current value per `Setting` name as of `sequence_id`/`time`, as a
`DataFrame` (columns `Setting`, `Value`, `SequenceID`). Unlike [`get_reads`](@ref), this *does*
collapse to latest-wins per `Setting` -- instrument settings behave like [`Attribute`](@ref) (a single
current value), not like [`Read`](@ref) (many coexisting values) -- mirroring
[`get_attribute_caches`](@ref)'s `ledger_subset` idiom.
"""
function get_instrument_settings(instrument_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now())
    ledger_time=db_time(time)
    return query_db("""
        WITH ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID), SequenceID,Time FROM Ledger WHERE Time <= ? AND SequenceID BETWEEN 0 AND ? GROUP BY SequenceID
        ),
        y (LedgerID,SequenceID,InstrumentID,Setting,Value)
        AS( SELECT s.LedgerID,l.SequenceID,s.InstrumentID,s.Setting,s.Value FROM InstrumentSettings s INNER JOIN ledger_subset l ON s.LedgerID = l.ID WHERE s.InstrumentID = ? )
        SELECT Setting,Value,Max(SequenceID) as SequenceID FROM y GROUP BY Setting
        """,(ledger_time,sequence_id,instrument_id))
end
