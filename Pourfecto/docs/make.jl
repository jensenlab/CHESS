using Documenter, Literate, Pourfecto

const EXAMPLES_DIR = joinpath(@__DIR__, "..", "examples")
const GENERATED_DIR = joinpath(@__DIR__, "src", "examples")

# Rendered as plain, non-executed code blocks (not `@example`) -- these examples build large
# combinatorial optimization models that require a real solver (Gurobi by default) to actually
# run, which the docs build environment shouldn't depend on.
for name in ("checkerboard", "combinatorial_media")
    Literate.markdown(
        joinpath(EXAMPLES_DIR, name, "$name.jl"),
        GENERATED_DIR;
        documenter=true,
        codefence = "```julia" => "```",
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
        "manual/pourcasts.md",
        "manual/compiling.md",
        "manual/instruments.md",
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

