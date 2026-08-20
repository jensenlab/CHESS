"""
    DuplicateRegistrationError

Raised when something is registered under a name that's already taken (see [`register_qc_method!`](@ref)).
"""
struct DuplicateRegistrationError <: Exception
    msg::AbstractString
end

Base.showerror(io::IO, e::DuplicateRegistrationError) = print(io, "DuplicateRegistrationError: ", e.msg)
