"""
    check_single_plate(layout::DataFrame)

GP correction is inherently a single-plate spatial model (it fits over one plate's `row`/`col` grid),
and a `CHESSExperiments.Experiment`'s `:layout` metadata can span multiple plates -- so every entry point
into `CHESSQC` requires a single-plate `layout`. Errors if `layout` has a `labware` column naming more
than one distinct plate; the caller is responsible for grouping (e.g. `groupby(design.layout,
:labware)`) and calling once per plate. A `layout` with no `labware` column, or one where it's all
`missing`, is treated as already single-plate.
"""
function check_single_plate(layout::DataFrame)
    hasproperty(layout, :labware) || return nothing
    distinct = unique(skipmissing(layout.labware))
    length(distinct) <= 1 || error("layout spans multiple plates ($(join(distinct, ", "))) -- group design.layout by :labware and call CHESSQC once per plate")
    return nothing
end

function size_data_plate_check(data::Matrix{T}, layout::DataFrame) where T <: Real
    check_single_plate(layout)
    R, C = maximum(layout.row), maximum(layout.col)
    size(data) == (R, C) || error("Size of data matrix ($(size(data))) must equal the layout's plate shape (($R, $C))")
    return nothing
end

"""
    control_bitmatrix(layout::DataFrame, column::Symbol) -> BitMatrix

Place `layout`'s `column` (`:positive` or `:negative`) into the `BitMatrix` shape the GP correction
machinery operates on internally, positioned by `layout`'s own `row`/`col` columns (not assumed row
order -- robust regardless of how `layout`'s rows happen to be sorted).
"""
function control_bitmatrix(layout::DataFrame, column::Symbol)
    R, C = maximum(layout.row), maximum(layout.col)
    mask = falses(R, C)
    values = getproperty(layout, column)
    for i in 1:nrow(layout)
        mask[layout.row[i], layout.col[i]] = values[i]
    end
    return mask
end
