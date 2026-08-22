"""
    struct ProcessingRecord

The `Experiment`-level analog of `CHESSCore.Read`: an append-only entry describing one call to a
`CHESSProcessing` operation (`aggregate`, `normalize`, `correct`, `flag`, `merge`). Never overwritten
or removed -- an `Experiment`'s full processing history is legible by reading its accumulated records,
the same way a `Well`'s history is legible by reading its accumulated `Read`s. Recorded purely for
provenance/audit: nothing in `CHESSProcessing` reads a record back out to decide what to compute next
(the sole, deliberate exception is `merge`, which reads `flag` records to add trust columns -- see
`flag`'s docstring).

Fields:
- `operation`: which operation produced this record (`:aggregate`, `:normalize`, `:correct`, `:flag`).
- `params`: the keyword arguments the call ran with (e.g. `relation`, `fn`, `on_missing`), so the
  record is self-describing without needing the original call site.
- `timestamp`: when the operation ran.
- `values`: the operation's output `values` `Dict`, stored on the record itself so an `Experiment` is
  replayable/inspectable without the caller having kept the value set around.
- `upstream`: indices into `processing_log(experiment)` (as it stood immediately before this record
  was appended) identifying which prior records fed this call's input, if any -- provenance only, e.g.
  to reconstruct "this `normalize` call used `aggregate`-record #2" after the fact.
"""
struct ProcessingRecord
    operation::Symbol
    params::Dict{Symbol,Any}
    timestamp::DateTime
    values::AbstractDict
    upstream::Vector{Int}
end

# Registered in __init__, not here at top level -- CHESSExperiments.parameter_registry is a
# separately-precompiled foreign package's Dict; only __init__ (which runs every time
# CHESSProcessing is loaded) reliably re-populates it into a fresh runtime session. Mirrors
# CHESSQC's __register_qc_methods__ pattern for the same reason.
function __register_parameters__()
    haskey(CHESSExperiments.parameter_registry, :processing_log) ||
        CHESSExperiments.register_parameter!(:processing_log, Vector{ProcessingRecord}; default=ProcessingRecord[])
    return nothing
end

"""
    processing_log(experiment::Experiment) -> Vector{ProcessingRecord}

Convenience accessor for `get_parameter(experiment, :processing_log)`.
"""
processing_log(experiment::Experiment) = CHESSExperiments.get_parameter(experiment, :processing_log)

"""
    append_record(experiment::Experiment, operation::Symbol, params::AbstractDict, values::AbstractDict;
                  upstream::AbstractVector{Int}=Int[]) -> Experiment

Append a new [`ProcessingRecord`](@ref) to `experiment`'s `:processing_log` and return the updated
`Experiment` (copy-on-write, like every other `CHESSExperiments` parameter write). Every
`CHESSProcessing` operation calls this internally as its side effect; callers of the six operations
never need to call it directly.
"""
function append_record(experiment::Experiment, operation::Symbol, params::AbstractDict, values::AbstractDict;
                        upstream::AbstractVector{Int}=Int[])
    log = processing_log(experiment)
    record = ProcessingRecord(operation, Dict{Symbol,Any}(params), now(), values, collect(Int, upstream))
    return CHESSExperiments.with_parameter(experiment, :processing_log, vcat(log, [record]))
end
