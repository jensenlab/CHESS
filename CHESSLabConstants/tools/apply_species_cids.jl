# Apply PubChem ID decisions to the `@species` definitions of CHESSLabConstants.
#
#   julia --project=CHESSLabConstants CHESSLabConstants/tools/apply_species_cids.jl decisions.csv            # dry run
#   julia --project=CHESSLabConstants CHESSLabConstants/tools/apply_species_cids.jl decisions.csv --write    # edit the files
#   julia --project=CHESSLabConstants CHESSLabConstants/tools/apply_species_cids.jl decisions.csv --write --audit
#
# `decisions.csv` has a header row and the columns `label`, `decision`, and `cid` (other columns are
# ignored), for example the review sheet saved as CSV. A row with the decision `cid` adds its `cid` as the
# last argument of the species' `@species` line. Any other decision leaves the line alone. A line that
# already carries a PubChem ID is never changed: the script reports it instead.
#
# `--audit` runs `audit_pubchem` on the species that were changed (it asks PubChem for each distinct ID, paced
# by the audit) and prints every finding above information level. Run it before keeping the edit.

const SPECIES_LINE = r"^@species\s+(?<label>\S+)\s+(?<name>\"(?:[^\"\\]|\\.)*\")\s+(?<charge>-?\d+)\s+(?<formula>\"(?:[^\"\\]|\\.)*\"|\S+)(?<cid>\s+\d+)?(?<tail>\s*(?:#.*)?)$"

"""
    add_cid(line, label, cid)

The `@species` line `line` with `cid` added as its last argument, ahead of any trailing comment. Returns
`nothing` if `line` is not the definition of `label`, and `:has_cid` if it already carries an ID.
"""
function add_cid(line::AbstractString, label::AbstractString, cid::Integer)
    m = match(SPECIES_LINE, line)
    (m === nothing || m[:label] != label) && return nothing
    m[:cid] === nothing || return :has_cid
    tail = m[:tail]
    start = m.match[1:end-ncodeunits(tail)] # everything before the trailing whitespace and comment
    return string(start, " ", cid, tail)
end

# The fields of a CSV text: fields may be quoted, a quoted field may hold commas, doubled quotes, and newlines.
function parse_csv(text::AbstractString)
    rows = Vector{Vector{String}}()
    row, field, quoted, i = String[], IOBuffer(), false, 1
    chars = collect(text)
    function end_row!()
        push!(row, String(take!(field)))
        !(length(row) == 1 && isempty(row[1])) && push!(rows, row)
        row = String[]
    end
    while i <= length(chars)
        c = chars[i]
        if quoted
            if c == '"' && i < length(chars) && chars[i+1] == '"'
                print(field, '"'); i += 1
            elseif c == '"'
                quoted = false
            else
                print(field, c)
            end
        elseif c == '"'
            quoted = true
        elseif c == ','
            push!(row, String(take!(field)))
        elseif c == '\n' || c == '\r'
            c == '\r' && i < length(chars) && chars[i+1] == '\n' && (i += 1)
            end_row!()
        else
            print(field, c)
        end
        i += 1
    end
    (position(field) > 0 || !isempty(row)) && end_row!()
    return rows
end

function read_decisions(path::AbstractString)
    rows = parse_csv(read(path, String))
    isempty(rows) && error("$path is empty")
    header = rows[1]
    function col(name)
        i = findfirst(==(name), header)
        i === nothing && error("$path has no \"$name\" column")
        return i
    end
    labels, decisions, cids = col("label"), col("decision"), col("cid")
    out = Dict{String,Int}()
    for (n, row) in enumerate(rows[2:end])
        length(row) >= max(labels, decisions, cids) || continue
        strip(row[decisions]) == "cid" || continue
        label, text = strip(row[labels]), strip(row[cids])
        id = tryparse(Int, replace(text, r"\.0$" => "")) # a spreadsheet may write 594 as 594.0
        (id === nothing || id <= 0) && error("row $(n + 1): the decision for \"$label\" is cid but the cid \"$text\" is not a positive integer")
        haskey(out, label) && error("the label \"$label\" appears twice")
        out[label] = id
    end
    return out
end

function apply_decisions(decisions::Dict{String,Int}, files::Vector{String}; write::Bool)
    remaining = copy(decisions)
    changed = String[]
    for file in files
        lines = readlines(file; keep=true)
        modified = false
        for (i, line) in enumerate(lines)
            m = match(SPECIES_LINE, line)
            (m === nothing || !haskey(remaining, m[:label])) && continue
            label = String(m[:label])
            new = add_cid(rstrip(line, ['\n', '\r']), label, remaining[label])
            if new === :has_cid
                println("kept   ", label, ": already has a PubChem ID (", strip(m[:cid]), ")")
            else
                println("add    ", rstrip(new))
                lines[i] = new * (endswith(line, "\n") ? "\n" : "")
                modified = true
                push!(changed, label)
            end
            delete!(remaining, label)
        end
        modified && write && Base.write(file, join(lines))
    end
    for label in keys(remaining)
        println("missing ", label, ": no @species line with that label")
    end
    return changed
end

function main(args)
    isempty(args) && error("usage: apply_species_cids.jl decisions.csv [--write] [--audit]")
    decisions = read_decisions(args[1])
    write = "--write" in args
    dir = joinpath(@__DIR__, "..", "src", "chemicals")
    files = [joinpath(dir, f) for f in ("ions.jl", "pKa_data.jl", "electrolytes.jl", "solids.jl", "liquids.jl")]
    changed = apply_decisions(decisions, filter(isfile, files); write)
    println(length(changed), " species ", write ? "changed" : "would change (dry run; add --write to edit the files)")
    if "--audit" in args
        write || println("(the audit reads the files as they are, so it needs --write)")
        @eval using CHESSLabConstants, CHESSCore
        found = Base.invokelatest() do
            species = [Symbol(l) => getfield(CHESSLabConstants, Symbol(l)) for l in changed]
            CHESSLabConstants.audit_pubchem(species; include_info=false)
        end
        println(isempty(found) ? "audit: no findings" : found)
    end
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
