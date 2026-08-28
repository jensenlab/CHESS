"""
    letter_code(n::Integer) -> String

Bijective base-26 row label for row index `n` (1-indexed): `1->"A"`, ..., `26->"Z"`, `27->"AA"`,
`28->"AB"`, ..., `52->"AZ"`, `53->"BA"`, .... Matches the classic spreadsheet-column scheme, and
generalizes cleanly to arbitrary row counts (unlike a repeated-letter or fixed-length scheme).
"""
function letter_code(n::Integer)
    n < 1 && throw(DomainError(n,"must be positive"))
    s = ""
    while n > 0
        n -= 1
        s = string(Char('A'+n%26))*s
        n = n ÷ 26
    end
    return s
end

"""
    wellnames(active::AbstractMatrix) -> Matrix{String}

Well names ("A1", "H12", ...) for every cell of a grid shaped like `active`, using [`letter_code`](@ref)
for rows.
"""
wellnames(active::AbstractMatrix) = [string(letter_code(i),j) for i in 1:size(active,1), j in 1:size(active,2)]
