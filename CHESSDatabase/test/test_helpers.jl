# Helpers shared by the tests that need a database of their own instead of the shared fixture
# database `build_test_database.jl` sets up.

"""
    with_scratch_db(f; path=tempname()*".db", create=true, keep=false)

Connect to a CHESS database at `path` (created first unless `create=false`), run `f(path)`, then reconnect
to whichever database was connected before (if any). The scratch file is deleted afterwards unless
`keep=true`. The location kinds and attributes registered by `build_test_database.jl` are global, so `f`
can use them.
"""
function with_scratch_db(f::Function;path::AbstractString=tempname()*".db",create::Bool=true,keep::Bool=false)
    previous = CHESSDatabase._current_db[]
    previous_path = isnothing(previous) ? nothing : previous.file
    create && create_db(path)
    connect_SQLite(path)
    try
        return f(path)
    finally
        isnothing(previous_path) ? (CHESSDatabase._current_db[] = nothing) : connect_SQLite(previous_path)
        keep || rm(path;force=true)
    end
end
