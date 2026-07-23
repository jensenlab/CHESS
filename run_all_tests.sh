#!/bin/bash
set -e
(cd CHESSCore && julia --project=. -e 'using Pkg; Pkg.test()')
(cd CHESSDatabase && julia --project=. -e 'using Pkg; Pkg.test()')
(cd CHESSLabConstants && julia --project=. -e 'using Pkg; Pkg.test()')
julia --project=. -e 'using Pkg; Pkg.test()'
