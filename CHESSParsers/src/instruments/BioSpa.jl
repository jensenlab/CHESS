# Parser for the BioTek/Agilent BioSpa automated incubator's .SES session file -- an XML document,
# structurally very different from the Gen5 .xlsx family: a <Plates> section maps each plate's real
# barcode to its carousel slot and the Gen5 plate number a linked Gen5 export uses internally, and
# the chamber's environmental history (O2/temperature/CO2/humidity) is logged as 5 parallel flat
# arrays -- <TimeStamps> plus one <DataSeries...> per reading kind -- all direct children of the
# <Session> root, in matching order, one entry per sample tick (typically one per minute). This is
# chamber-level data with no well to attach to, so it produces `EnvironmentLog`s, not `LabwareRead`s.
#
# Out of scope: <EventLog> (a free-text, per-message-format session audit trail) and <Assay> (protocol
# configuration detail) -- neither is "raw data" in the numeric sense this package otherwise deals in.

"""
    struct BioSpaFormat <: InstrumentFormat end

Export format for the BioTek/Agilent BioSpa automated incubator's `.SES` session file. See
[`InstrumentFormat`](@ref) and [`EnvironmentLog`](@ref) (the chamber-level result type this format
produces, distinct from the well-shaped [`LabwareRead`](@ref) the Gen5 formats produce).
"""
struct BioSpaFormat <: InstrumentFormat end

# The document node's last child isn't reliably the root Element (e.g. a trailing newline after
# </Session> becomes a trailing whitespace Text child) -- find it by node type instead.
function _xml_root_element(doc)
    for c in XML.children(doc)
        XML.nodetype(c) == XML.Element && return c
    end
    error("no root element found")
end

function _xml_children_named(node, tag::AbstractString)
    return [c for c in XML.children(node) if XML.nodetype(c) == XML.Element && XML.tag(c) == tag]
end

function _xml_text(node)
    kids = XML.children(node)
    isempty(kids) && return ""
    t = kids[1]
    return XML.nodetype(t) == XML.Text ? XML.value(t) : ""
end

function _xml_child_text(node, tag::AbstractString)
    matches = _xml_children_named(node, tag)
    isempty(matches) && return nothing
    return _xml_text(first(matches))
end

# .SES timestamps are ISO-8601 with a timezone offset and up to 7 fractional-second digits, e.g.
# "2026-02-12T14:39:50.1359865-05:00" -- Dates.DateTime only parses milliseconds, and every other
# timestamp in this package is already treated as naive/local, so the offset is dropped and the
# fraction truncated to milliseconds.
const _BIOSPA_DATETIME_RE = r"^([\d-]+T[\d:]+)(\.\d+)?([+-]\d{2}:\d{2})?$"

function _biospa_parse_datetime(s::AbstractString)
    m = match(_BIOSPA_DATETIME_RE, s)
    m === nothing && error("could not parse BioSpa timestamp \"$s\"")
    naive, frac = m.captures[1], m.captures[2]
    ms = frac === nothing ? "" : "." * first(frac[2:end], 3)
    return DateTime(naive * ms)
end

function _biospa_is_session_xml(path::AbstractString)
    try
        doc = XML.read(path, XML.Node)
        return XML.tag(_xml_root_element(doc)) == "Session"
    catch
        return false
    end
end

"""
    _biospa_plates(session) -> DataFrame

Parse `<Plates><PlateDetails>` into a table with columns `id` (real barcode), `slot`,
`experiment_name`, and `gen5_plate_number` -- the mapping a linked Gen5 `.xlsx` export alone can't
always provide (its own sheets are sometimes named by Gen5's internal plate number, not the barcode).
"""
function _biospa_plates(session)
    platesnode = only(_xml_children_named(session, "Plates"))
    details = _xml_children_named(platesnode, "PlateDetails")
    ids = String[]; slots = Int[]; names = String[]; gen5nums = Int[]
    for d in details
        push!(ids, something(_xml_child_text(d, "ID"), ""))
        push!(slots, parse(Int, _xml_child_text(d, "Slot")))
        datanode = only(_xml_children_named(d, "Data"))
        push!(names, something(_xml_child_text(datanode, "ExperimentName"), ""))
        push!(gen5nums, parse(Int, _xml_child_text(datanode, "Gen5PlateNumber")))
    end
    return DataFrame(id=ids, slot=slots, experiment_name=names, gen5_plate_number=gen5nums)
end

_biospa_timestamps(session) = [_biospa_parse_datetime(_xml_text(c)) for c in _xml_children_named(session, "TimeStamps")]
_biospa_floats(session, tag::AbstractString) = [parse(Float64, _xml_text(c)) for c in _xml_children_named(session, tag)]

# BioSpa pre-allocates its sample buffer for the session's maximum possible duration and fills it in
# as data actually arrives -- unused trailing slots are .NET's default DateTime, 0001-01-01, not real
# readings. <CurrentIndex> states how many samples are real; used when it's consistent with that
# sentinel actually starting where claimed, otherwise found by scanning for it directly.
const _BIOSPA_UNSET_TIME = DateTime(1, 1, 1)

function _biospa_valid_count(session, times::Vector{DateTime})
    text = _xml_child_text(session, "CurrentIndex")
    if text !== nothing
        n = parse(Int, text)
        if 0 <= n <= length(times) && (n == length(times) || times[n+1] == _BIOSPA_UNSET_TIME)
            return n
        end
    end
    i = findfirst(==(_BIOSPA_UNSET_TIME), times)
    return i === nothing ? length(times) : i - 1
end

function _biospa_setpoint(envnode, tag::Union{AbstractString,Nothing})
    tag === nothing && return missing
    text = _xml_child_text(envnode, tag)
    text === nothing && return missing
    return parse(Float64, text)
end

"""
    parse_raw(::Type{BioSpaFormat}, path::AbstractString; kwargs...) -> Vector{EnvironmentLog}

Parse a BioSpa `.SES` session file into one [`EnvironmentLog`](@ref) per reading kind
(`Temperature`/`O2`/`CO2`/`Humidity`), each sharing the same `time` vector and the session's plate
slot/barcode mapping (`metadata["plates"]`).
"""
function parse_raw(::Type{BioSpaFormat}, path::AbstractString; kwargs...)
    doc = XML.read(path, XML.Node)
    session = _xml_root_element(doc)

    plates = _biospa_plates(session)

    times = _biospa_timestamps(session)
    o2 = _biospa_floats(session, "DataSeriesO2")
    temp = _biospa_floats(session, "DataSeriesTemp")
    co2 = _biospa_floats(session, "DataSeriesCO2")
    humidity = _biospa_floats(session, "DataSeriesHumidity")
    n = length(times)
    all(==(n), length.((o2, temp, co2, humidity))) ||
        error("TimeStamps/DataSeriesO2/DataSeriesTemp/DataSeriesCO2/DataSeriesHumidity have mismatched lengths ($(length(times)), $(length(o2)), $(length(temp)), $(length(co2)), $(length(humidity)))")

    nvalid = _biospa_valid_count(session, times)
    times, o2, temp, co2, humidity = times[1:nvalid], o2[1:nvalid], temp[1:nvalid], co2[1:nvalid], humidity[1:nvalid]

    envnode = only(_xml_children_named(session, "Environment"))
    session_start_text = _xml_child_text(session, "SessionActualStartTime")
    session_start = session_start_text === nothing ? missing : _biospa_parse_datetime(session_start_text)

    common = Dict{String,Any}("format" => BioSpaFormat, "session_start" => session_start, "plates" => plates)

    results = EnvironmentLog[]
    for (read_kind, unit, values, setpointtag) in (
        ("Temperature", "°C", temp, "TempValue"),
        ("O2", "percent", o2, "O2Value"),
        ("CO2", "percent", co2, "CO2Value"),
        ("Humidity", "percent", humidity, nothing),
    )
        meta = copy(common)
        meta["read_kind"] = read_kind
        meta["unit"] = unit
        meta["setpoint"] = _biospa_setpoint(envnode, setpointtag)
        push!(results, EnvironmentLog(meta, DataFrame(time=times, value=values)))
    end
    return results
end

detect(::Type{BioSpaFormat}, path::AbstractString) = endswith(lowercase(path), ".ses") && _biospa_is_session_xml(path)

register_format!(BioSpaFormat; name="biospa")
