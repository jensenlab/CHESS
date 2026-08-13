"""
    DataFrame(lr::LabwareRead) -> DataFrame

Return the tidy, long-format measurement table underlying `lr`. Metadata (instrument, protocol,
export datetime, ...) is not included -- see `lr.metadata` for that.
"""
DataFrames.DataFrame(lr::LabwareRead) = lr.data

"""
    DataFrame(el::EnvironmentLog) -> DataFrame

Return the `time`/`value` table underlying `el`. Metadata (reading kind, unit, plate mapping, ...)
is not included -- see `el.metadata` for that.
"""
DataFrames.DataFrame(el::EnvironmentLog) = el.data
