# Helpers shared by the tests that need a database of their own instead of the shared fixture
# database `build_test_database.jl` sets up.

"""
    with_scratch_db(f; path=tempname()*".db")

Create a new CHESS database at `path`, connect to it, run `f(path)`, then reconnect to whichever database
was connected before (if any) and delete the scratch file. The location kinds and attributes
registered by `build_test_database.jl` are global, so `f` can use them.
"""
function with_scratch_db(f::Function;path::AbstractString=tempname()*".db")
    previous = CHESSDatabase._current_db[]
    previous_path = isnothing(previous) ? nothing : previous.file
    create_db(path)
    connect_SQLite(path)
    try
        return f(path)
    finally
        isnothing(previous_path) ? (CHESSDatabase._current_db[] = nothing) : connect_SQLite(previous_path)
        rm(path;force=true)
    end
end
