using Documenter, Literate, Pourfecto

const EXAMPLES_DIR = joinpath(@__DIR__, "..", "examples")
const GENERATED_DIR = joinpath(@__DIR__, "src", "examples")

for name in ("checkerboard", "combinatorial_media")
    Literate.markdown(
        joinpath(EXAMPLES_DIR, name, "$name.jl"),
        GENERATED_DIR;
        documenter=true,
    )
end

makedocs(sitename="Pourfecto.jl",
remotes=nothing,
warnonly=[:cross_references],
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
    "Examples" => [
        "examples/checkerboard.md",
        "examples/combinatorial_media.md",
    ],
    "API Reference" => "api_reference.md",
    "Citing Pourfecto" => "citation.md" ,
]

)

deploydocs(
    repo="github.com/jensenlab/CHESS.git",
    dirname="pourfecto",
    devbranch="main",
    push_preview=true,
)

