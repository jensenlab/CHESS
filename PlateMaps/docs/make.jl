
using Documenter, PlateMaps

makedocs(sitename="PlateMaps.jl",
repo=Documenter.Remotes.GitHub("jensenlab", "CHESS"),
pages = [
    "Home" => "index.md",
    "Quick Start" => "quickstart.md",
    "API Reference" => "api-reference.md"
]
)

# The CHESS, Pourfecto, PlateMaps, and LabwarePlotting workflows all push to the same gh-pages
# branch, so a push can lose a race with another workflow. deploydocs fetches the current gh-pages
# on every call, so calling it again picks up the other push.
for attempt in 1:5
    try
        deploydocs(
            repo="github.com/jensenlab/CHESS.git",
            dirname="platemaps",
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
