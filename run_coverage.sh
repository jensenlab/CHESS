#!/bin/bash
set -e
for pkg in CHESSCore CHESSDatabase CHESSLabConstants; do
    echo "=== $pkg ==="
    (cd "$pkg" && julia --project=. -e 'using Pkg; Pkg.test(coverage=true)')
done

julia -e '
using Coverage
for pkg in ("CHESSCore", "CHESSDatabase", "CHESSLabConstants")
    cd(pkg) do
        cov = process_folder("src")
        covered, total = get_summary(cov)
        pct = total == 0 ? 0.0 : round(100*covered/total, digits=1)
        println(pkg, ": ", covered, "/", total, " lines covered (", pct, "%)")
        LCOV.writefile("lcov.info", cov)
        clean_folder("src") # removes the .cov files, keeps src/ clean after reporting
        clean_folder("test") # Julia also instruments the test scripts themselves
    end
end
'
