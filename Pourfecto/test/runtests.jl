using Pourfecto
using Test, CHESSCore, Unitful, AbstractTrees, CSV, DataFrames , Random
using SCIP

Pourfecto._default_optimizer[] = SCIP.Optimizer

# The solver-backed test_problems/*.jl files below each call pourfecto(...) (a real SCIP/HiGHS
# solve) at file top level, outside any @testset -- so their cost doesn't show up in the per-testset
# Time column, but dominates the full suite's wall-clock time. Set POURFECTO_SKIP_SOLVER_TESTS=true
# locally to skip them while iterating on source code; unset (or "false") runs everything, matching
# today's full/CI behavior.
const RUN_SOLVER_TESTS = get(ENV, "POURFECTO_SKIP_SOLVER_TESTS", "false") != "true"

import Pourfecto: # from instruments folder
    SingleChannel, EightChannel

import Pourfecto: # from types
    Configuration, Mask,
    head,pistons,aspirate_channels,dispense_channels,aspirate_mask,dispense_mask, asp, disp ,asp_positions, disp_positions, labware,
    AspNode, DispNode,
    Pourcast, transfers, flows

import Pourfecto: # default_labware
    well_to_cartesian, cartesian_to_well

import Pourfecto: #mask utils
    compute_positions, compute_mask_sizes, effective_head_size, mask_rules_for

import CHESSCore: # primitives now live in CHESSCore
    vc_to_stock, stock_to_vc, q_to_stock, stock_to_q

import Pourfecto: # dataframe_interface.jl (Pourfecto-only composites)
    vc_to_q, q_to_vc

import Pourfecto: # pourfecto_algorithms/helpers.jl
    normalize_inputs , check_inputs, well_connections, compute_flow_nodes





include("compute_positions.jl")
include("masks.jl")
include("dataframe_interface.jl")
include("well_connections.jl")

function all_planned_approx_target(p::Pourcast;kwargs...)
    ps = planned_stocks(p)
    ts = target_stocks(p)

    return all([isapprox(ps[i],ts[i];kwargs...) for i in eachindex(ps)])
end

include("test_problems/test_compilation.jl")

if RUN_SOLVER_TESTS
    include("json_interface.jl")
    include("test_problems/checkerboard.jl")
    #include("test_problems/combinatorial_media.jl")
    include("test_problems/labware_stamping.jl")
    include("test_problems/mantis_pcr.jl")
    include("test_problems/minimum_shot.jl")
    include("test_problems/tempest_compilation.jl")
    include("test_problems/cobra_compilation.jl")
    include("test_problems/nimbus_compilation.jl")
end


