# Produces a structurally-identical but content-scrubbed, downsampled copy of a real BioSpa .SES
# session file, safe to commit as a regression fixture. Plate barcodes and experiment names are
# replaced with fixed placeholders; the session's real start date is replaced with a placeholder date
# (every kept TimeStamps entry shifted by the same offset, so relative spacing/order is preserved);
# every DataSeriesO2/Temp/CO2/Humidity value is replaced with a random value at roughly the same
# order of magnitude as the original (same 0.3x-1.7x seeded-multiplier convention as
# dev/deidentify_fixture.jl). <EventLog> and <Assay> are stripped entirely -- neither is parsed by
# CHESSParsers, and both can carry identifying free text (protocol names, file paths) not worth
# writing per-message-format scrubbing rules for. <PlatesTimeLines>/<AssaysDisplayDates> (per-plate
# scheduling detail, not identifying but also not parsed) are stripped too, purely for size. The 5
# parallel time-series arrays (typically ~12000 samples) are downsampled to a small, evenly-spaced
# subset -- a committed fixture doesn't need full fidelity to exercise the parser, and it keeps the
# file small (real ones run several MB).
#
# BioSpa pre-allocates its sample buffer for the session's maximum duration and leaves unused
# trailing slots at .NET's default DateTime (0001-01-01) with value 0 -- those sentinel entries are
# left untouched (not shifted, not fuzzed) so the downsampled fixture still exercises
# _biospa_valid_count's truncation logic, not just the "real" samples.
#
# Usage:
#   julia --project=CHESSParsers CHESSParsers/dev/deidentify_biospa_fixture.jl <source.SES> <dest.SES>

using XML, Dates, Random

const PLACEHOLDER_START = DateTime(2020, 1, 1, 9, 0, 0)
const SENTINEL_TIME = DateTime(1, 1, 1)
const SERIES_TAGS = ("TimeStamps", "DataSeriesO2", "DataSeriesTemp", "DataSeriesCO2", "DataSeriesHumidity")
const _BIOSPA_DATETIME_RE = r"^([\d-]+T[\d:]+)(\.\d+)?([+-]\d{2}:\d{2})?$"

function _parse_datetime(s::AbstractString)
    m = match(_BIOSPA_DATETIME_RE, s)
    m === nothing && error("could not parse BioSpa timestamp \"$s\"")
    naive, frac = m.captures[1], m.captures[2]
    ms = frac === nothing ? "" : "." * first(frac[2:end], 3)
    return DateTime(naive * ms)
end

_fuzz(rng, v::Real) = round(abs(v) * (0.3 + 1.4rand(rng)), digits=3)

_children_named(node, tag::AbstractString) = [c for c in XML.children(node) if XML.nodetype(c) == XML.Element && XML.tag(c) == tag]

function _text(node)
    kids = XML.children(node)
    isempty(kids) && return ""
    t = kids[1]
    return XML.nodetype(t) == XML.Text ? XML.value(t) : ""
end

function _set_text!(node, newvalue::AbstractString)
    kids = XML.children(node)
    isempty(kids) ? push!(kids, XML.Text(newvalue)) : (kids[1] = XML.Text(newvalue))
    return node
end

# The document node's last child isn't reliably the root Element (e.g. a trailing newline after
# </Session> becomes a trailing whitespace Text child) -- find it by node type instead.
function _root_element(doc)
    for c in XML.children(doc)
        XML.nodetype(c) == XML.Element && return c
    end
    error("no root element found")
end

function _scrub_plates!(session)
    platesnode = only(_children_named(session, "Plates"))
    for (i, d) in enumerate(_children_named(platesnode, "PlateDetails"))
        _set_text!(only(_children_named(d, "ID")), "SIM" * lpad(string(i), 5, '0'))
        datanode = only(_children_named(d, "Data"))
        _set_text!(only(_children_named(datanode, "ExperimentName")), "deidentified_session")
    end
end

function _scrub_start_times!(session)
    for tag in ("SessionActualStartTime",)
        matches = _children_named(session, tag)
        isempty(matches) || _set_text!(only(matches), string(PLACEHOLDER_START))
    end
    startnode = only(_children_named(session, "StartTime"))
    at = _children_named(startnode, "At")
    isempty(at) || _set_text!(only(at), string(PLACEHOLDER_START))
end

# Downsamples and scrubs the 5 parallel series, strips EventLog/Assay, and updates CurrentIndex to
# match how many of the *kept* samples were real (not sentinel). Returns the new children vector.
# Operates on Element-only children (real XML has whitespace Text nodes interleaved between every
# sibling element, which would otherwise break contiguous-run detection below) -- the output is
# re-indented by XML.write regardless, so dropping that original whitespace is harmless.
function _rebuild_children(session, rng)
    kids = filter(c -> XML.nodetype(c) == XML.Element, XML.children(session))
    n = length(kids)

    ts_nodes = _children_named(session, "TimeStamps")
    nfull = length(ts_nodes)
    original_times = [_parse_datetime(_text(c)) for c in ts_nodes]
    is_real = original_times .!= SENTINEL_TIME
    real_start = original_times[1]

    stride = max(1, nfull ÷ 100)
    keep_idx = collect(1:stride:nfull)
    keep_real = is_real[keep_idx]
    new_current_index = count(keep_real)

    new_children = eltype(kids)[]
    i = 1
    while i <= n
        node = kids[i]
        tag = XML.nodetype(node) == XML.Element ? XML.tag(node) : nothing
        if tag in ("EventLog", "Assay", "PlatesTimeLines", "AssaysDisplayDates")
            i += 1
        elseif tag in SERIES_TAGS
            j = i
            while j <= n && XML.nodetype(kids[j]) == XML.Element && XML.tag(kids[j]) == tag
                j += 1
            end
            run = kids[i:(j-1)]
            kept = run[keep_idx]
            for (k, node) in enumerate(kept)
                if !keep_real[k]
                    push!(new_children, node) # sentinel entry -- leave untouched
                elseif tag == "TimeStamps"
                    shifted = PLACEHOLDER_START + (original_times[keep_idx[k]] - real_start)
                    push!(new_children, XML.Element("TimeStamps", XML.Text(string(shifted))))
                else
                    fuzzed = _fuzz(rng, parse(Float64, _text(node)))
                    push!(new_children, XML.Element(tag, XML.Text(string(fuzzed))))
                end
            end
            i = j
        elseif tag == "CurrentIndex"
            push!(new_children, XML.Element("CurrentIndex", XML.Text(string(new_current_index))))
            i += 1
        else
            push!(new_children, node)
            i += 1
        end
    end
    return new_children
end

"""
    deidentify_biospa_fixture(src::AbstractString, dest::AbstractString) -> String

Write a de-identified, downsampled copy of the BioSpa `.SES` session at `src` to `dest`, safe to
commit. See module docstring above for exactly what's scrubbed/downsampled vs. preserved.
"""
function deidentify_biospa_fixture(src::AbstractString, dest::AbstractString)
    mkpath(dirname(dest))
    doc = XML.read(src, XML.Node)
    session = _root_element(doc)
    rng = MersenneTwister(hash(basename(src)))

    _scrub_plates!(session)
    _scrub_start_times!(session)
    new_children = _rebuild_children(session, rng)
    empty!(XML.children(session))
    append!(XML.children(session), new_children)

    XML.write(dest, doc)
    return dest
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 2 || error("usage: julia deidentify_biospa_fixture.jl <source.SES> <dest.SES>")
    out = deidentify_biospa_fixture(ARGS[1], ARGS[2])
    println("wrote ", out)
end
