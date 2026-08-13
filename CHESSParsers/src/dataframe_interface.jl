"""
    DataFrame(lr::LabwareRead) -> DataFrame

Return the tidy, long-format measurement table underlying `lr`. Metadata (instrument, protocol,
export datetime, ...) is not included -- see `lr.metadata` for that.
"""
DataFrames.DataFrame(lr::LabwareRead) = lr.data
