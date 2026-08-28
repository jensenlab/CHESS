"""
    CHESSProcessingPlottingExt

Restores the `CHESSQC`-era QC plotting (`plot_plate_data`/`plot_control_data`), generalized onto
the `(data, present, role_masks)` shape `correct.jl`'s `_plate_role_data` already builds, and drawn
on `LabwarePlotting`'s shared grid skeleton rather than a bare `heatmap`/categorical `scatter`. Loads
only when `LabwarePlotting` is also `using`'d -- `CHESSProcessing`'s base package has no `Plots`
dependency.
"""
module CHESSProcessingPlottingExt

using CHESSProcessing, LabwarePlotting, PlateMaps, RunMaps, Plots

import CHESSProcessing: _plate_role_data

function CHESSProcessing.plot_plate_data(run_map::RunMap, plate_maps::AbstractVector{<:Pair},
                                          values::AbstractDict;
                                          relations::AbstractVector=[:positive,:negative],
                                          nodes::Union{Nothing,AbstractVector}=nothing)
    relation_types = Symbol.(relations)
    allowed = nodes === nothing ? nothing : Set(nodes)
    results = Dict{String,Plots.Plot}()

    for (label,pm) in plate_maps
        data,present,_,_ = _plate_role_data(pm,run_map,values,relation_types,allowed)
        any(present) || continue
        masked = [present[I] ? data[I] : NaN for I in CartesianIndices(data)]
        plt = LabwarePlotting.plot_grid(pm.wells)
        LabwarePlotting.plot_heatmap!(plt,masked)
        results[string(label)] = plt
    end
    return results
end

function CHESSProcessing.plot_control_data(run_map::RunMap, plate_maps::AbstractVector{<:Pair},
                                            values::AbstractDict;
                                            relations::AbstractVector=[:positive,:negative],
                                            nodes::Union{Nothing,AbstractVector}=nothing)
    relation_types = Symbol.(relations)
    allowed = nodes === nothing ? nothing : Set(nodes)
    categories = vcat(relation_types,[:run])
    colors = LabwarePlotting.role_palette(categories)
    results = Dict{String,Plots.Plot}()

    for (label,pm) in plate_maps
        data,present,role_masks,_ = _plate_role_data(pm,run_map,values,relation_types,allowed)
        any(present) || continue

        xs = Int[]; ys = Float64[]; cs = Any[]
        for I in CartesianIndices(present)
            present[I] || continue
            ridx = findfirst(r->role_masks[r][I],relation_types)
            category = ridx === nothing ? :run : relation_types[ridx]
            push!(xs,findfirst(==(category),categories))
            push!(ys,data[I])
            push!(cs,colors[category])
        end

        plt = Plots.scatter(xs,ys;color=cs,legend=false,grid=false,
                             xticks=(1:length(categories),string.(categories)),
                             xlims=(0.5,length(categories)+0.5))
        results[string(label)] = plt
    end
    return results
end

end # module CHESSProcessingPlottingExt
