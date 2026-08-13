# Scans the local, private data/ directory (gitignored -- see CHESSParsers/.gitignore) and reports,
# for every file, whether parse_instrument_file succeeds and a one-line summary, or the error message
# on failure. The fast "does this new export work" check when a new candidate file lands in data/ --
# see the package README's "Contributing a fixture" section for the full workflow.
#
# Usage: julia --project=CHESSParsers CHESSParsers/dev/triage_fixtures.jl

using CHESSParsers, DataFrames

datadir = joinpath(@__DIR__, "..", "data")

if !isdir(datadir) || isempty(readdir(datadir))
    println("data/ is empty or missing -- nothing to triage. Drop candidate files into ", datadir)
else
    is_candidate(f) = isfile(joinpath(datadir, f)) && !startswith(f, ".") && !startswith(f, "~\$") &&
                       !endswith(lowercase(f), ".md")
    files = sort(filter(is_candidate, readdir(datadir)))
    for f in files
        path = joinpath(datadir, f)
        print(rpad(f, 50))
        try
            lrs = parse_instrument_file(path)
            plates = length(unique(lr.metadata["plate"] for lr in lrs))
            rows = sum(nrow(lr.data) for lr in lrs)
            println("OK    plates=$plates  channels=$(length(lrs))  rows=$rows")
        catch e
            println("FAIL  ", sprint(showerror, e))
        end
    end
end
