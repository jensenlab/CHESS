# Run Maps

```@meta
DocTestSetup = :(using RunMaps, DataFrames)
```

`RunMaps` records how the runs of an experiment relate to each other: which controls validate which
sample, and which wells are duplicates of the same treatment. It says nothing about where anything
goes on a plate; [`PlateMaps`](https://jensenlab.github.io/CHESS/platemaps/dev/) places a run map
onto plates, and [Experimental Designs](experiments.md) builds run maps from a design automatically.
It is a separate package that is loaded separately from `CHESS`.

## Runs and links

A [`RunMap`](@ref) is a set of nodes (runs) joined by directed, labeled links. A node can be any
value: an integer design row, a symbol, a tuple. [`add_run!`](@ref) adds a node and
[`link!`](@ref) adds a link from a run to the node it relates to, labeled with a relation type such
as `:positive`, `:negative`, or `:duplicate`:

```jldoctest runmaps
julia> using RunMaps

julia> rm = RunMap{Symbol}();

julia> for r in (:A, :B, :pos, :neg); add_run!(rm, r); end

julia> link!(rm, :A, :pos, :positive);

julia> link!(rm, :A, :neg, :negative);

julia> link!(rm, :B, :pos, :positive);
```

Here samples `A` and `B` share a positive control, and only `A` has a negative control. Links point
from the sample to its control: [`linked_runs`](@ref) follows them forward and
[`linking_runs`](@ref) backward. Both return the nodes in no particular order, so the examples sort
them:

```jldoctest runmaps
julia> sort(linked_runs(rm, :A))
2-element Vector{Symbol}:
 :neg
 :pos

julia> sort(linked_runs(rm, :A; type = :positive))
1-element Vector{Symbol}:
 :pos

julia> sort(linking_runs(rm, :pos))
2-element Vector{Symbol}:
 :A
 :B

julia> n_runs(rm), n_edges(rm)
(4, 3)
```

[`relation_types`](@ref), [`roles`](@ref RunMaps.roles), [`has_link`](@ref), and [`edges`](@ref) answer other
questions about the same links, and links can carry a metadata `Dict`.

## Scheduling controls and duplicates

Three functions build run maps for common layouts instead of linking by hand:

- [`schedule_uniform_controls`](@ref) splits runs into groups no larger than a cap, creates new
  control nodes for each group, and links every run in the group to them.
- [`schedule_duplicates`](@ref) creates duplicate nodes for each run, linked with `:duplicate`.
- [`schedule_controls!`](@ref) adds controls drawn from pools of existing runs to a map, keeping any
  already-linked runs (such as a run and its duplicates) in the same group.

Six runs with one positive and one negative control per group, at most five nodes per group, gives
two groups of three runs and two controls each:

```jldoctest runmaps
julia> u = schedule_uniform_controls([1, 2, 3, 4, 5, 6], Dict(:positive => 1, :negative => 1), 5);

julia> n_components(u), component_sizes(u)
(2, [5, 5])

julia> sort(linked_runs(u, 1))
2-element Vector{Any}:
 :negative_g1_1
 :positive_g1_1
```

Each group is its own connected component of the map: controls are never shared between groups.
`solver = "MILP"` uses an optimization model instead of the default greedy grouping and needs a
Gurobi license. [`group_solvers`](@ref) maps the name of each predefined grouping solver to its
function.

The new nodes are named by an ID factory. The keyword `linked_run_id_factory` of
`schedule_uniform_controls` and the keyword `duplicate_id_factory` of `schedule_duplicates` take a
function to replace the default naming. [`default_linked_run_id_factory`](@ref) produces names such as
`:positive_g1_1`, and [`default_duplicate_id_factory`](@ref) produces names such as `:A_dup1`:

```jldoctest runmaps
julia> sort(collect(keys(group_solvers)))
2-element Vector{String}:
 "MILP"
 "greedy"

julia> default_linked_run_id_factory(1, :positive, 1)
:positive_g1_1

julia> default_duplicate_id_factory(:A, 1)
:A_dup1
```

## Editing a map

[`has_run`](@ref) tests whether a node is registered, and [`n_nodes`](@ref) counts the registered
nodes. [`unlink!`](@ref) removes the links between two nodes, either every link or only those of a
given relation type. The nodes stay registered. [`remove_run!`](@ref) removes a node and every link
that touches it. Links can carry metadata. [`set_metadata!`](@ref) merges a dictionary into the
metadata of an existing link and raises an error if the link does not exist, and
[`edge_metadata`](@ref) returns the metadata of a link, an empty dictionary for a link without
metadata, or `nothing` for a link that does not exist:

```jldoctest runmaps
julia> edited = RunMap{Symbol}();

julia> for r in (:A, :B, :ctl); add_run!(edited, r); end

julia> link!(edited, :A, :ctl, :positive);

julia> link!(edited, :B, :ctl, :positive);

julia> set_metadata!(edited, :A, :ctl, :positive, Dict(:note => "plate edge"));

julia> edge_metadata(edited, :A, :ctl, :positive)
Dict{Symbol, Any} with 1 entry:
  :note => "plate edge"

julia> edge_metadata(edited, :B, :ctl, :positive)
Dict{Symbol, Any}()

julia> edge_metadata(edited, :A, :B, :positive) === nothing
true

julia> unlink!(edited, :B, :ctl);

julia> has_run(edited, :B), n_nodes(edited)
(true, 3)

julia> remove_run!(edited, :ctl);

julia> has_run(edited, :ctl), n_edges(edited)
(false, 0)
```

## Tables and JSON

`DataFrame(map)` lists every link, one per row:

```jldoctest runmaps
julia> sort(DataFrame(rm), [:run, :linked_run])
3×4 DataFrame
 Row │ run     linked_run  relation_type  metadata
     │ Symbol  Symbol      Symbol         Dict…
─────┼────────────────────────────────────────────────────────
   1 │ A       neg         negative       Dict{Symbol, Any}()
   2 │ A       pos         positive       Dict{Symbol, Any}()
   3 │ B       pos         positive       Dict{Symbol, Any}()
```

[`runmap_to_json`](@ref) and [`json_to_runmap`](@ref) (or [`write_json`](@ref) and
[`read_runmap_json`](@ref) for files) convert a map to and from JSON. JSON has no symbols, so
symbol nodes come back as strings (relation types are converted back to symbols):

```jldoctest runmaps
julia> rm2 = json_to_runmap(runmap_to_json(rm));

julia> sort(linked_runs(rm2, "A"))
2-element Vector{Any}:
 "neg"
 "pos"
```

The [RunMaps API reference](../api/runmaps.md) lists every function.
