using Documenter
using DocumenterMermaid
using CHESS
using CHESS.CHESSCore
using CHESS.CHESSDatabase
using CHESS.CHESSLabConstants
using CHESSParsers # not re-exported by CHESS (like Pourfecto/PlateMaps), so used directly

# register_format!'s jldoctest example (src/registry.jl) refers to CHESSParsers/register_format!/
# format_registry without importing them itself -- innocuous while CHESSParsers was outside
# `modules` (its doctests never ran), but now that it's included, Documenter needs this DocTestSetup
# to give the doctest's Main the same `using CHESSParsers` context a real user session would have.
Documenter.DocMeta.setdocmeta!(CHESSParsers, :DocTestSetup, :(using CHESSParsers); recursive=true)

makedocs(
    sitename="CHESS.jl",
    modules=[CHESS, CHESS.CHESSCore, CHESS.CHESSDatabase, CHESS.CHESSLabConstants, CHESSParsers],
    checkdocs=:none, # the manual/API pages are being built up incrementally -- don't fail the
    # build over docstring coverage gaps (CHESSLabConstants in particular is mostly generated
    # data with few standalone docstrings by design, see manual/registering-lab-constants.md)
    repo=Documenter.Remotes.GitHub("jensenlab", "CHESS"),
    # api/core-stocks.md and api/labconstants.md list hundreds of registered reagents and organisms.
    format=Documenter.HTML(size_threshold_warn=150_000),
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
                "Acid/Base Chemistry" => "manual/acid-base.md",
                "Wells: Depositing & Transferring Material" => "manual/wells.md",
            ],
            "Reads & Instrument Measurements" => "manual/reads.md",
            "Parsing Instrument Files" => "manual/parsing-instrument-files.md",
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
            "Troubleshooting" => "manual/troubleshooting.md",
        ],
        "API Reference" => [
            "CHESSCore" => [
                "Overview & Errors" => "api/core.md",
                "Locations & Operations" => "api/core-locations.md",
                "Stocks & Chemistry" => "api/core-stocks.md",
                "Attributes & Reads" => "api/core-environment.md",
                "Interop" => "api/core-interop.md",
            ],
            "CHESSDatabase" => "api/database.md",
            "CHESSLabConstants" => "api/labconstants.md",
            "CHESSParsers" => "api/parsers.md",
        ],
    ],
)

deploydocs(
    repo="github.com/jensenlab/CHESS.git",
    devbranch="main",
    push_preview=true,
)
