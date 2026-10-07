using Documenter, Literate, Pourfecto

const EXAMPLES_DIR = joinpath(@__DIR__, "..", "examples")
const GENERATED_DIR = joinpath(@__DIR__, "src", "examples")

# Rendered as plain, non-executed code blocks (not `@example`) -- these examples build large
# combinatorial optimization models that require a real solver (Gurobi by default) to actually
# run, which the docs build environment shouldn't depend on.
for name in ("checkerboard", "combinatorial_media", "priority", "in_place")
    Literate.markdown(
        joinpath(EXAMPLES_DIR, name, "$name.jl"),
        GENERATED_DIR;
        documenter=true,
        codefence = "```julia" => "```",
    )
end

makedocs(sitename="Pourfecto.jl",
repo=Documenter.Remotes.GitHub("jensenlab", "CHESS"),
# The single API page lists every documented name, with a source link on each.
format=Documenter.HTML(size_threshold=300_000, size_threshold_warn=250_000),
warnonly=[:cross_references],
pages = [
    "Home" => "index.md",
    "Quick Start" => "quickstart.md",
    "Manual" => [
        "manual/reagents.md",
        "manual/stocks.md",
        "manual/labware.md",
        "manual/configurations.md",
        "manual/pourfecto_method.md",
        "manual/pourcasts.md",
        "manual/compiling.md",
        "manual/instruments.md",
        "manual/complexity.md",
        "manual/troubleshooting.md",
    ],
    "Examples" => [
        "examples/checkerboard.md",
        "examples/combinatorial_media.md",
        "examples/priority.md",
        "examples/in_place.md",
    ],
    "API Reference" => "api_reference.md",
    "Citing Pourfecto" => "citation.md" ,
]

)

# The CHESS, Pourfecto, PlateMaps, and LabwarePlotting workflows all push to the same gh-pages
# branch, so a push can lose a race with another workflow. deploydocs fetches the current gh-pages
# on every call, so calling it again picks up the other push.
for attempt in 1:5
    try
        deploydocs(
            repo="github.com/jensenlab/CHESS.git",
            dirname="pourfecto",
            devbranch="main",
            push_preview=true,
        )
        break
    catch err
        attempt == 5 && rethrow()
        @warn "deploydocs failed; retrying" attempt exception=err
        sleep(5 * attempt + 10 * rand())
    end
end

