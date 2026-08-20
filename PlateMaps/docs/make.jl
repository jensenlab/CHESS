
using Documenter, PlateMaps

makedocs(sitename="PlateMaps.jl",
remotes=nothing,
pages = [
    "Home" => "index.md",
    "Quick Start Guide" => "quickstart.md",
    "API Reference" => "api-reference.md"
]
)

deploydocs(
    repo="github.com/jensenlab/CHESS.git",
    dirname="platemaps",
    devbranch="main",
    push_preview=true,
)
