
using Documenter, PlateArrays

makedocs(sitename="PlateArrays.jl",
remotes=nothing,
pages = [
    "Home" => "index.md",
    "Quick Start Guide" => "quickstart.md",
    "API Reference" => "api-reference.md"
]
)

deploydocs(
    repo="github.com/jensenlab/CHESS.git",
    dirname="platearrays",
    devbranch="main",
    push_preview=true,
)
