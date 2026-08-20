#!/bin/bash
set -e
(cd CHESSCore && julia --project=. -e 'using Pkg; Pkg.test()')
(cd CHESSDatabase && julia --project=. -e 'using Pkg; Pkg.test()')
(cd CHESSLabConstants && julia --project=. -e 'using Pkg; Pkg.test()')
(cd CHESSParsers && julia --project=. -e 'using Pkg; Pkg.test()')
(cd RunMaps && julia --project=. -e 'using Pkg; Pkg.test()')
(cd PlateMaps && julia --project=. -e 'using Pkg; Pkg.test()')
(cd CHESSExperiments && julia --project=. -e 'using Pkg; Pkg.test()')
(cd CHESSQC && julia --project=. -e 'using Pkg; Pkg.test()')
julia --project=. -e 'using Pkg; Pkg.test()'
