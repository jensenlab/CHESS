"""
    transfers_by_config(pc::Pourcast) -> Vector{Matrix{Float64}}

Compute well-to-well transfer volumes per configuration.

This function aggregates the global flow matrix `flows(pc)` into per-configuration
transfer matrices between **source wells** and **target wells**.

For each configuration `c` in `configs(pc)`, it returns an `S×T` matrix
`trfs_by_config[c]` where:

- `S` is the total number of
  source wells across all source labware.
- `T` is the total number of
  target wells across all target labware.
- Entry `trfs_by_config[c][s, t]` equals the sum of all flows (from `flows(pc)`)
  along aspiration/dispense node pairs that:
  1) connect source well `s` to target well `t` (via
     `Pourfecto.compute_flow_connections`), and
  2) belong to configuration `c` (i.e., both nodes have `.configuration == cons[c]`).

# Arguments
- `pc::Pourcast`: A pour/transfer plan providing configurations, labware, well
  names, and a global flow matrix via `flows(pc)`.

# Returns
- `Vector{Matrix{Float64}}`: A length-`C` vector where `C == length(configs(pc))`.
  Each element is an `S×T` dense matrix of aggregated transfer amounts.
"""
function transfers_by_config(pc::Pourcast) 
    src_labware = source_labware(pc) 
    tgt_labware = target_labware(pc)
    cons = configs(pc) 



    src_wellnames = vcat(well_names.(src_labware)...)
    tgt_wellnames = vcat(well_names.(tgt_labware)...)
    asp_nodes = Pourfecto.compute_flow_nodes(Pourfecto.AspNode,cons,src_labware)
    disp_nodes = Pourfecto.compute_flow_nodes(Pourfecto.DispNode,cons,tgt_labware)

    S = length(src_wellnames)
    T = length(tgt_wellnames)
    C = length(cons) 

    flow_connections = Pourfecto.compute_flow_connections(src_wellnames,tgt_wellnames,asp_nodes,disp_nodes) # compute all flow pairs that connect each pair of wells (regardless of if they are physically possible or not) 

    f = flows(pc) 

    trfs_by_config = [ zeros(S,T) for _ in 1:C]

    asp_node_config_idxs = map(y-> findfirst(x->x==y.configuration,cons),asp_nodes)
    disp_node_config_idxs = map(y-> findfirst(x->x==y.configuration,cons),disp_nodes)


    for s in 1:S 
      for t in 1:T 
        for conn in flow_connections[s,t]
          if asp_node_config_idxs[conn[1]] == disp_node_config_idxs[conn[2]]
            c = asp_node_config_idxs[conn[1]]
            #flows connect with configuration c
            trfs_by_config[c][s,t] += f[conn]
          end 
        end 
      end 
    end 

    #=
    for c in 1:C 
        asp_nodes_config = findall(x->x.configuration == cons[c], asp_nodes)
        disp_nodes_config = findall(x-> x.configuration ==cons[c], disp_nodes) 

        config_idxs = [ CartesianIndex(a,d) for a in asp_nodes_config, d in disp_nodes_config]

        for s in 1:S 
            for t in 1:T 
                config_flows = intersect(flow_connections[s,t],config_idxs)
                trfs_by_config[c][s,t] = sum(f[config_flows])
            end 
        end 
    end 
    =#
    return trfs_by_config 
end 


"""
    flows_by_config(pc::Pourcast) -> Vector{Matrix{Float64}}

Partition the full flow matrix into one flow matrix per configuration.

This function computes aspiration and dispense flow nodes across all
configurations, then slices the global flow matrix `flows(pc)` into `C` matrices
(one per configuration in `configs(pc)`). For configuration `c`, only entries
corresponding to aspiration/dispense nodes whose `configuration` equals
`configs(pc)[c]` are copied from the global flow matrix; all other entries remain
zero.

# Arguments
- `pc::Pourcast`: A pour/transfer plan providing configurations, labware, and a
  global flow matrix via `flows(pc)`.

# Returns
- `Vector{Matrix{Float64}}`: A length-`C` vector `flws_by_config` where
  `C == length(configs(pc))`. Each entry `flws_by_config[c]` is an `A×D` matrix
  (`A == length(asp_nodes)`, `D == length(disp_nodes)`) whose nonzero entries
  represent flows for configuration `c`.
"""
function flows_by_config(pc::Pourcast) 

    src_labware = source_labware(pc) 
    tgt_labware = target_labware(pc)
    cons = configs(pc) 

    asp_nodes = Pourfecto.compute_flow_nodes(Pourfecto.AspNode,cons,src_labware)
    disp_nodes = Pourfecto.compute_flow_nodes(Pourfecto.DispNode,cons,tgt_labware)

    A = length(asp_nodes)
    D = length(disp_nodes)
    C = length(cons) 



    f = flows(pc) 

    flws_by_config = [ zeros(A,D) for _ in 1:C]

        for c in 1:C 
        asp_nodes_config = findall(x->x.configuration == cons[c], asp_nodes)
        disp_nodes_config = findall(x-> x.configuration ==cons[c], disp_nodes) 

        for a in asp_nodes_config
            for d in disp_nodes_config
                
                flws_by_config[c][a,d] = f[a,d]
            end 
        end 
    end 

    return flws_by_config
end 


"""
    labware_indices(pc::Pourcast) -> Tuple{Dict,Dict}

Construct dictionaries mapping each source/target labware item to the vector of
indices it occupies in the flattened transfer indexing scheme.

This function expands `source_labware(pc)` and `target_labware(pc)` into
“by-index” vectors where each labware object is repeated `length(x)` times, then
computes, for each labware object `x`, the positions (via `findall`) at which it
appears in that expanded vector. The result is two dictionaries:

- `src_dict`: maps each `source` labware object to a vector of integer indices
  into the expanded source index space.
- `tgt_dict`: maps each `target` labware object to a vector of integer indices
  into the expanded target index space.

These index vectors are intended to be used as selectors when indexing transfer
data.

# Arguments
- `pc::Pourcast`: A pour/transfer plan providing `source_labware(pc)` and
  `target_labware(pc)`.

# Returns
- `(src_dict, tgt_dict)`: A 2-tuple of dictionaries:
  - `src_dict::Dict{<:Any, <:AbstractVector{Int}}` mapping each element of
    `source_labware(pc)` to a vector of indices.
  - `tgt_dict::Dict{<:Any, <:AbstractVector{Int}}` mapping each element of
    `target_labware(pc)` to a vector of indices.
"""
function labware_indices(pc::Pourcast) 
    sources = source_labware(pc)
    targets = target_labware(pc)
    srcs_by_idx = vcat(map(x->fill(x,length(CHESSCore.children(x))),sources)...)
    tgts_by_idx = vcat(map(x->fill(x,length(CHESSCore.children(x))),targets)...)

    src_idxs = map(x-> findall(y -> y == x,srcs_by_idx),sources)
    tgt_idxs = map(x-> findall(y -> y == x,tgts_by_idx),targets)

    return Dict(sources .=>src_idxs) , Dict(targets .=>  tgt_idxs)
end 



"""
    transfer_indices(pc::Pourcast, source::Labware, target::Labware) -> Tuple{AbstractVector,AbstractVector}

Return the transfer index selectors for a given `source`→`target` labware pair.

This function validates that `source` is present in `source_labware(pc)` and
that `target` is present in `target_labware(pc)`. If either is missing, it
throws an `ArgumentError`. On success, it retrieves index selectors from
`labware_indices(pc)` and returns the pair associated with the requested
`source` and `target`.


# Arguments
- `pc::Pourcast`: A pour/transfer plan containing source/target labware lists and
  index mappings.
- `source::Labware`: Source labware to look up.
- `target::Labware`: Target labware to look up.

# Returns
- `(src_inds, tgt_inds)`: A 2-tuple of vectors:
  - `src_inds`: index selector(s) associated with `source`
  - `tgt_inds`: index selector(s) associated with `target`

  These are intended to be used together for indexing transfer arrays/tensors.

# Throws
- `ArgumentError`: If `source` is not in `source_labware(pc)` or `target` is not
  in `target_labware(pc)`.

"""
function transfer_indices(pc::Pourcast, source::Labware, target::Labware)
    sources = source_labware(pc)
    targets = target_labware(pc)
    if !in(source,sources) 
        throw(ArgumentError("source $(source) not in the Pourcast"))
    end 
    if !in(target,targets) 
        throw(ArgumentError("target $(target) not in the Pourcast"))
    end 

    src_dict ,tgt_dict = labware_indices(pc) 
    return src_dict[source],tgt_dict[target] 
end 


"""
    slotting_requirements(pc::Pourcast) -> Vector{BitMatrix}

Compute per-configuration source→target “slotting” requirements from a `Pourcast`
plan by marking which source labware must be able to transfer to which target
labware.

For each configuration `c`, this function returns a boolean matrix `M = slotting_matrices[c]`
of size `(S, T)` where:

- `S == length(source_labware(pc))` (number of source labware items)
- `T == length(target_labware(pc))` (number of target labware items)
- `M[s, t] == true` if **any** transfer value associated with transfers from
  `sources[s]` to `targets[t]` in configuration `c` is greater than `0`.
  Otherwise `M[s, t] == false`.

This is useful for determining which source/target pairs must be physically
co-slotted/accessible in each configuration.

# Returns
- `Vector{BitMatrix}`: A length-`C` vector of boolean matrices, one per configuration,
  where `C == length(configs(pc))`. Each matrix has shape `(S, T)`.

# Notes
- The comparison is strictly greater than (`>`) `0`.
- Requires the following `Pourcast`-related functions to be defined:
  `transfers_by_config`, `configs`, `source_labware`, `target_labware`,
  `transfer_indices`.

# Examples
```julia
reqs = slotting_requirements(pc)
"""
function slotting_requirements(pc::Pourcast)
    trfs_by_config = transfers_by_config(pc) 
    sources = source_labware(pc) 
    targets = target_labware(pc) 


    C = length(configs(pc)) 
    S  = length(source_labware(pc)) 
    T = length(target_labware(pc))

    slotting_matrices = [ falses(S,T) for _ in 1:C] 

    for c in 1:C 
        for s in 1:S 
            for t in 1:T 
                if any(trfs_by_config[c][transfer_indices(pc,sources[s],targets[t])...] .> 0) 
                    slotting_matrices[c][s,t] = true 
                end 
            end 
        end 
    end 
    return slotting_matrices

end 









  function labware_well_names(lw::Labware) 

    wellnames = vec(CHESSCore.name.(children(lw)))
    lw_names = fill(CHESSCore.name(lw),length(wellnames))

    return DataFrame(labware = lw_names, well = wellnames)
  end 



  function transfer_table(design::DataFrame, protocol_sources::Vector{<:Labware},protocol_targets::Vector{<:Labware})

    src_names = vcat(labware_well_names.(protocol_sources)...)
    tgt_names = vcat(labware_well_names.(protocol_targets)...)

    tt = DataFrame(source_labware=String[],source_well=String[],target_labware=String[],target_well=String[],volume=Real[])

    for i in 1:nrow(design) 
      for j in 1:ncol(design)
        if design[i,j] > 0 
            push!(tt,[src_names[i,1],src_names[i,2],tgt_names[j,1],tgt_names[j,2],design[i,j]])
        end 
      end 
    end 


    
    return tt 
  end


    
