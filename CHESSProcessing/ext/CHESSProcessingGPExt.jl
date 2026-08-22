"""
    CHESSProcessingGPExt

Adds `GPCorrection`, a `CHESSProcessing.CorrectionMethod` porting `CHESSQC`'s Gaussian-process
spatial plate-effect correction (`plateerrorGP`) onto `correct`'s `apply_correction` extension point.
Loads only when `GaussianProcesses` is also loaded -- `CHESSProcessing`'s base package has no
`GaussianProcesses`/`PDMats` dependency (the reason `CHESSQC` itself is excluded from the shared
CHESS workspace manifest), so this stays opt-in.
"""
module CHESSProcessingGPExt

using CHESSProcessing, GaussianProcesses, Statistics, DataFrames

import CHESSProcessing: GPCorrection

_absolute(x, y) = x - y
_relative(x, y) = (x - y) / x

function _build_df(data::Matrix{Float64}, controls::BitMatrix, present::BitMatrix)
    values, rows, cols, is_control = Float64[], Int[], Int[], Bool[]
    for idx in CartesianIndices(data)
        present[idx] || continue
        push!(values, data[idx])
        push!(is_control, controls[idx])
        push!(rows, idx[1])
        push!(cols, idx[2])
    end
    return DataFrame(Value=values, Row=rows, Column=cols, Control=is_control)
end

function _calculate_controls_error(avg_control::Real, df::DataFrame, correction::Function)
    corr_val = Float64[]
    for row in eachrow(df)
        push!(corr_val, row.Control ? correction(row.Value, avg_control) : NaN64)
    end
    df.CorrectionValue_Train = corr_val
    return df
end

function _makeGP(train_in, train_out; lengthscale=3.0, sd_guess=std(train_out), lb_lengthscale=2.0, ub_lengthscale=6.0,
                  lb_std=std(train_out) / 5, ub_std=std(train_out) * 3, noise=-2.0, kwargs...)
    kern = Matern(5 / 2, log(lengthscale), log(sd_guess))
    gp = GP(train_in, train_out, MeanZero(), kern, noise)
    kb = [[log(lb_lengthscale), log(lb_std)], [log(ub_lengthscale), log(ub_std)]]
    GaussianProcesses.optimize!(gp; domean=false, kernbounds=kb, kwargs...)
    return gp
end

# Ported from CHESSQC.plateerrorGP, adapted to only fit/correct over `present` wells (a well with no
# resolved value has nothing to train on or predict for) rather than assuming every plate position
# carries real data.
function _plateerrorGP(data::Matrix{Float64}, controls::BitMatrix, present::BitMatrix, correction::Function;
                        lengthscale=3.0, lb_lengthscale=2.0, ub_lengthscale=6.0, kwargs...)
    df = _build_df(data, controls, present)
    any(df.Control) || return data # no controls present on this plate for this relation -- nothing to fit

    avg_control = median(df.Value[df.Control])
    df = _calculate_controls_error(avg_control, df, correction)

    train_df = df[df.Control, :]
    train_out = Float64.(train_df.CorrectionValue_Train)
    train_in = permutedims(Matrix{Float64}(train_df[:, [:Column, :Row]]))

    gp = _makeGP(train_in, train_out; lengthscale, lb_lengthscale, ub_lengthscale, kwargs...)

    corrected = copy(data)
    for row in eachrow(df)
        pred_pt = reshape(Float64[row.Column, row.Row], 2, 1)
        pred_error_μ, _ = predict_y(gp, pred_pt)
        adjustby = correction === _absolute ? pred_error_μ[1] : row.Value * pred_error_μ[1]
        corrected[row.Row, row.Column] = row.Value - adjustby
    end
    return corrected
end

function CHESSProcessing.apply_correction(method::GPCorrection, data::Matrix{Float64}, present::BitMatrix,
                                           role_masks::Dict{Symbol,BitMatrix})
    haskey(role_masks, method.negative) || throw(ArgumentError("role_masks has no :$(method.negative) entry -- pass it in `relations`"))
    haskey(role_masks, method.positive) || throw(ArgumentError("role_masks has no :$(method.positive) entry -- pass it in `relations`"))
    kwargs = (; lengthscale=method.lengthscale, lb_lengthscale=method.lb_lengthscale, ub_lengthscale=method.ub_lengthscale)
    neg_corrected = _plateerrorGP(data, role_masks[method.negative] .& present, present, _absolute; kwargs...)
    return _plateerrorGP(neg_corrected, role_masks[method.positive] .& present, present, _relative; kwargs...)
end

end # module CHESSProcessingGPExt
