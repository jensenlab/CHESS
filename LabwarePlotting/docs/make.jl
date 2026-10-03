using Documenter, LabwarePlotting

makedocs(sitename="LabwarePlotting.jl",
repo=Documenter.Remotes.GitHub("jensenlab", "CHESS"),
pages = [
    "Home" => "index.md",
    "Quick Start" => "quickstart.md",
    "API Reference" => "api-reference.md"
]
)

deploydocs(
    repo="github.com/jensenlab/CHESS.git",
    dirname="labwareplotting",
    devbranch="main",
    push_preview=true,
)
