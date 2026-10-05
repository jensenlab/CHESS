# Unitful prints superscript exponents (mL⁻¹) by default only on macOS. Doctests record the superscript
# form, so turn it on for every platform.
ENV["UNITFUL_FANCY_EXPONENTS"] = "true"

using Documenter
using DocumenterMermaid
using CHESS
using CHESS.CHESSCore
using CHESS.CHESSDatabase
using CHESS.CHESSLabConstants
using CHESSParsers # not re-exported by CHESS (like Pourfecto/PlateMaps), so used directly
using CHESSExperiments, RunMaps, PlateMaps, CHESSProcessing # also separate packages; PlateMaps
# loads CHESSExperiments' scheduling extension, and has its own docs site

# register_format!'s jldoctest example (src/registry.jl) refers to CHESSParsers/register_format!/
# format_registry without importing them itself -- innocuous while CHESSParsers was outside
# `modules` (its doctests never ran), but now that it's included, Documenter needs this DocTestSetup
# to give the doctest's Main the same `using CHESSParsers` context a real user session would have.
Documenter.DocMeta.setdocmeta!(CHESSParsers, :DocTestSetup, :(using CHESSParsers); recursive=true)

makedocs(
    sitename="CHESS.jl",
    modules=[CHESS, CHESS.CHESSCore, CHESS.CHESSDatabase, CHESS.CHESSLabConstants, CHESSParsers,
        CHESSExperiments, RunMaps, CHESSProcessing],
    checkdocs=:exports, # every exported name must have a docstring included on some page
    repo=Documenter.Remotes.GitHub("jensenlab", "CHESS"),
    # api/labconstants.md lists hundreds of registered reagents and organisms.
    format=Documenter.HTML(size_threshold_warn=150_000),
    pages=[
        "Home" => "index.md",
        "Quick Start" => "quickstart.md",
        "Tutorial" => "tutorial.md",
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
            "Experiments & Data" => [
                "Experimental Designs" => "manual/experiments.md",
                "Run Maps" => "manual/runmaps.md",
                "Processing Experiment Data" => "manual/processing.md",
            ],
            "Registering Lab Constants" => "manual/registering-lab-constants.md",
            "CHESS Databases" => [
                "Database Architecture" => "manual/db-architecture.md",
                "The Ledger" => "manual/ledger.md",
                "Committing & Uploading" => "manual/committing-uploading.md",
                "Observations" => "manual/observations.md",
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
                "Stocks" => "api/core-stocks.md",
                "Solution Chemistry" => "api/core-chemistry.md",
                "Attributes & Reads" => "api/core-environment.md",
                "Interop" => "api/core-interop.md",
            ],
            "CHESSDatabase" => "api/database.md",
            "CHESSLabConstants" => "api/labconstants.md",
            "CHESSParsers" => "api/parsers.md",
            "CHESSExperiments" => "api/experiments.md",
            "RunMaps" => "api/runmaps.md",
            "CHESSProcessing" => "api/processing.md",
        ],
    ],
)

deploydocs(
    repo="github.com/jensenlab/CHESS.git",
    devbranch="main",
    push_preview=true,
)
