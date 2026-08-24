# Persists CHESSExperiments.Experiment into the Designs/RunAssignments tables (see database.jl).
# `design`/`metadata` are open-ended, so they round-trip through JSON rather than a normalized schema.
# `metadata[:layout]`, once scheduled, gets one RunAssignments row per well -- it's excluded from
# MetadataJSON and persisted losslessly via RunAssignments instead, so it's never double-stored.
# RunAssignments.LocationID is the literal fusion point with CHESSCore: nullable until a real
# Location/well is committed.

function _rowdicts_to_json(df::DataFrame)
    return JSON.json([Dict(String(k) => v for (k, v) in pairs(row)) for row in eachrow(df)])
end

function _json_to_dataframe(str::AbstractString)
    rows = JSON.parse(str)
    isempty(rows) && return DataFrame()
    return DataFrame(rows)
end

_metadata_dict_to_json(d::AbstractDict) = JSON.json(Dict(String(k) => v for (k, v) in d))
_json_to_metadata_dict(str::AbstractString) = Dict{Symbol,Any}(Symbol(k) => v for (k, v) in JSON.parse(str))

"""
    upload_design(experiment::CHESSExperiments.Experiment, exp_id::Integer) -> Integer

Persist `experiment` (design matrix, layout if scheduled, metadata) under the given `Experiments` row
and return the new `Designs.ID`. If `CHESSExperiments.layout(experiment)` is set, one `RunAssignments`
row is uploaded per well.
"""
function upload_design(experiment::CHESSExperiments.Experiment, exp_id::Integer)
    matrix_json = _rowdicts_to_json(experiment.design)
    name = get(experiment.metadata, :name, nothing)
    metadata_for_json = filter(kv -> kv.first !== :layout, experiment.metadata)
    metadata_json = _metadata_dict_to_json(metadata_for_json)
    execute_db(
        "INSERT INTO Designs(ExperimentID,Name,MatrixJSON,MetadataJSON) Values(?,?,?,?)",
        (exp_id, name, matrix_json, metadata_json),
    )
    design_id = query_db("SELECT Max(ID) as ID FROM Designs")[1, :ID]

    lay = CHESSExperiments.layout(experiment)
    if !isnothing(lay)
        for row in eachrow(lay)
            upload_layout_row(design_id, row)
        end
    end

    return design_id
end

function upload_layout_row(design_id::Integer, row)
    execute_db(
        "INSERT INTO RunAssignments(DesignID,Well,Row,Col,IsRun,IsPositive,IsNegative,RunIndex,Labware,LocationID,MetadataJSON) Values(?,?,?,?,?,?,?,?,?,?,?)",
        (
            design_id, row.well, row.row, row.col,
            Int(row.run), Int(row.positive), Int(row.negative),
            ismissing(row.run_index) ? nothing : row.run_index,
            ismissing(row.labware) ? nothing : row.labware,
            ismissing(row.location_id) ? nothing : row.location_id,
            _metadata_dict_to_json(row.metadata),
        ),
    )
    return query_db("SELECT Max(ID) as ID FROM RunAssignments")[1, :ID]
end

"""
    commit_run_location!(design_id::Integer, labware::AbstractString, well::AbstractString, location_id::Integer)

Fuse a scheduled well with a real, committed `CHESSCore.Location` by updating its `RunAssignments`
row's `LocationID` -- the opportunistic-fusion update: nothing else about the row changes. `(labware,
well)` together identify the row -- `well` names (e.g. `"A1"`) repeat across plates once a design spans
more than one, so `labware` is required to disambiguate.
"""
function commit_run_location!(design_id::Integer, labware::AbstractString, well::AbstractString, location_id::Integer)
    execute_db(
        "UPDATE RunAssignments SET LocationID = ? WHERE DesignID = ? AND Labware = ? AND Well = ?",
        (location_id, design_id, labware, well),
    )
    return nothing
end

"""
    get_design(design_id::Integer) -> CHESSExperiments.Experiment

Reconstruct the `Experiment` persisted under `design_id`, including its `:layout` metadata (built from
`RunAssignments`) if it was scheduled.
"""
function get_design(design_id::Integer)
    info = query_db("SELECT * FROM Designs WHERE ID = ?", (design_id,))
    nrow(info) == 0 && error("design id not found")
    row = info[1, :]
    matrix = _json_to_dataframe(row["MatrixJSON"])
    metadata = _json_to_metadata_dict(row["MetadataJSON"])
    ismissing(row["Name"]) || (metadata[:name] = row["Name"])

    assignments = query_db("SELECT * FROM RunAssignments WHERE DesignID = ? ORDER BY ID", (design_id,))
    if nrow(assignments) > 0
        metadata[:layout] = DataFrame(
            well = assignments.Well,
            row = assignments.Row,
            col = assignments.Col,
            run = Bool.(assignments.IsRun),
            positive = Bool.(assignments.IsPositive),
            negative = Bool.(assignments.IsNegative),
            run_index = [ismissing(x) ? missing : Int(x) for x in assignments.RunIndex],
            labware = [ismissing(x) ? missing : x for x in assignments.Labware],
            location_id = [ismissing(x) ? missing : Int(x) for x in assignments.LocationID],
            metadata = [_json_to_metadata_dict(x) for x in assignments.MetadataJSON],
        )
    end

    return CHESSExperiments.Experiment(matrix, metadata)
end
