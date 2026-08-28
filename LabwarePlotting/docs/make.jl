using Documenter, LabwarePlotting

makedocs(sitename="LabwarePlotting.jl",
remotes=nothing,
pages = [
    "Home" => "index.md",
    "Quick Start Guide" => "quickstart.md",
    "API Reference" => "api-reference.md"
]
)

deploydocs(
    repo="github.com/jensenlab/CHESS.git",
    dirname="labwareplotting",
    devbranch="main",
    push_preview=true,
)
