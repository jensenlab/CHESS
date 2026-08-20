"""
    CHESSQCCoreExt

The adapter between `CHESSQC` (pure `Matrix`+`DataFrame` layout) and `CHESSCore.Labware`. `CHESSQC` stays
fully independent of `CHESSCore` -- this extension only loads when both packages are loaded, and
provides `to_plate_matrix`/`record_qc_reads!` as the explicit conversion boundary. Since `layout`'s
`row`/`col` columns already give real plate grid coordinates, `labware[row,col]` resolves a well
directly -- no `location_id` matching is needed for the round trip, though `location_id` is still
opportunistically filled in on `layout` when a well happens to already be committed.
"""
module CHESSQCCoreExt

using CHESSQC, CHESSCore, CHESSExperiments, DataFrames

"""
    to_plate_matrix(labware::CHESSCore.Labware, layout::DataFrame, read_kind::Symbol) -> Matrix

Pull `read_kind` values off every well in `labware` at the grid positions `layout` marks active
(`run`/`positive`/`negative`), into the `Matrix` shape `CHESSQC.data_correction` operates on. Also fills
in `layout.location_id` for any well that's already been committed to a real `CHESSCore.Location`.
Wells with no recorded `read_kind` value are left as `0.0`.
"""
function CHESSQC.to_plate_matrix(labware::CHESSCore.Labware, layout::DataFrame, read_kind::Symbol)
    CHESSQC.check_single_plate(layout)
    kind = CHESSCore.read_kinds[read_kind]
    R, C = maximum(layout.row), maximum(layout.col)
    data = zeros(Float64, R, C)
    for i in 1:nrow(layout)
        (layout.run[i] || layout.positive[i] || layout.negative[i]) || continue
        well = labware[layout.row[i], layout.col[i]]
        loc_id = CHESSCore.location_id(well)
        isnothing(loc_id) || (layout.location_id[i] = loc_id)
        kind_reads = filter(r -> r.kind === kind, CHESSCore.reads(well))
        isempty(kind_reads) && continue
        data[layout.row[i], layout.col[i]] = Float64(kind_reads[end].value)
    end
    return data
end

"""
    record_qc_reads!(labware::CHESSCore.Labware, corrected::AbstractMatrix, layout::DataFrame, read_kind::Symbol, method::CHESSExperiments.QCMethod)

Write `corrected` back onto `labware` as new `CHESSCore.Read`s (never overwriting the raw reads --
consistent with `Read`'s existing "many coexisting values" semantics), and attach QC provenance
(`"chessqc.correction_method"`) onto each active well's `layout.metadata`. Returns `labware`.
"""
function CHESSQC.record_qc_reads!(labware::CHESSCore.Labware, corrected::AbstractMatrix, layout::DataFrame, read_kind::Symbol, method::CHESSExperiments.QCMethod)
    CHESSQC.check_single_plate(layout)
    kind = CHESSCore.read_kinds[read_kind]
    for i in 1:nrow(layout)
        (layout.run[i] || layout.positive[i] || layout.negative[i]) || continue
        well = labware[layout.row[i], layout.col[i]]
        value = CHESSCore.is_quantitative(kind) ? corrected[layout.row[i], layout.col[i]] * kind.unit : corrected[layout.row[i], layout.col[i]]
        CHESSCore.record_read!(well, CHESSCore.Read(kind, value))
        layout.metadata[i][Symbol("chessqc.correction_method")] = string(typeof(method))
    end
    return labware
end

end # module CHESSQCCoreExt
