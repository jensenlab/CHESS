using Documenter
using DocumenterMermaid
using CHESS
using CHESS.CHESSCore
using CHESS.CHESSDatabase
using CHESS.CHESSLabConstants

makedocs(
    sitename="CHESS.jl",
    modules=[CHESS, CHESS.CHESSCore, CHESS.CHESSDatabase, CHESS.CHESSLabConstants],
    checkdocs=:none, # the manual/API pages are being built up incrementally -- don't fail the
    # build over docstring coverage gaps (CHESSLabConstants in particular is mostly generated
    # data with few standalone docstrings by design, see manual/registering-lab-constants.md)
    remotes=nothing, # no git remote configured yet -- disable source-links until CI/deploy is set up
    warnonly=[:cross_references], # several existing docstrings across CHESSCore/CHESSDatabase have
    # stale @ref cross-references (renamed/unexported functions, typos) -- pre-existing docstring
    # hygiene debt uncovered by this being the first-ever Documenter build, not introduced here, and
    # out of scope for the docs scaffolding/manual pass. Downgrade to a build warning rather than a
    # hard failure; auditing/fixing these individually is a good follow-up task.
    pages=[
        "Home" => "index.md",
        "Manual" => [
            "Locations" => "manual/core-concepts.md",
            "Movement & Occupancy" => "manual/movement.md",
            "Environmental Attributes & Inheritance" => "manual/attributes.md",
            "Stocks & Chemistry" => [
                "Reagents & Chemicals" => "manual/reagents-chemicals.md",
                "Stocks" => "manual/stocks.md",
                "Organisms & Cultures" => "manual/organisms-cultures.md",
                "Recipes & Solution Chemistry" => "manual/recipes.md",
                "Wells: Depositing & Transferring Material" => "manual/wells.md",
            ],
            "Reads & Instrument Measurements" => "manual/reads.md",
            "Registering Lab Constants" => "manual/registering-lab-constants.md",
            "CHESS Databases" => [
                "Database Architecture" => "manual/db-architecture.md",
                "The Ledger" => "manual/ledger.md",
                "Committing & Uploading" => "manual/committing-uploading.md",
                "Reconstruction" => "manual/reconstruction.md",
                "Caching & Repair" => "manual/caching-repair.md",
                "Encumbrances" => "manual/encumbrances.md",
                "Instrument Interfaces" => "manual/instrument-interfaces.md",
            ],
            "Interop" => "manual/interop.md",
        ],
        "API Reference" => [
            "CHESSCore" => "api/core.md",
            "CHESSDatabase" => "api/database.md",
            "CHESSLabConstants" => "api/labconstants.md",
        ],
    ],
)
