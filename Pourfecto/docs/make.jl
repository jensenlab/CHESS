using Documenter, Pourfecto

makedocs(sitename="Pourfecto.jl",
remotes=nothing,
pages = [
    "Home" => "index.md",
    "Quick Start Guide" => "quickstart.md",
    "Manual" => [
        "manual/reagents.md",
        "manual/stocks.md",
        "manual/labware.md",
        "manual/configurations.md",
        "manual/pourfecto_method.md",
        "manual/pourcasts.md"
    ],
    "API Reference" => "api_reference.md",
    "Citing Pourfecto" => "citation.md" ,
]

)

deploydocs(
    repo = "github.com/jensenlab/Pourfecto.git",
)

