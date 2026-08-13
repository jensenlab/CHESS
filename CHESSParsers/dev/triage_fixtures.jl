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
            results = parse_instrument_file(path)
            rows = sum(nrow(r.data) for r in results)
            if !isempty(results) && haskey(first(results).metadata, "plate")
                # LabwareRead (Gen5 family): one "plate" per result
                plates = length(unique(r.metadata["plate"] for r in results))
                println("OK    plates=$plates  channels=$(length(results))  rows=$rows")
            elseif !isempty(results) && haskey(first(results).metadata, "plates")
                # EnvironmentLog (BioSpa): a shared plate-mapping table in metadata, not one per result
                plates = nrow(first(results).metadata["plates"])
                println("OK    plates=$plates  readings=$(length(results))  rows=$rows")
            else
                println("OK    results=$(length(results))  rows=$rows")
            end
        catch e
            println("FAIL  ", sprint(showerror, e))
        end
    end
end
