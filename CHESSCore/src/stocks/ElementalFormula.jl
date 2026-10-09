"""
    _element_symbols

The set of element symbols accepted in formula strings: the 118 named elements of PeriodicTable.jl.
(PeriodicTable.jl also carries a placeholder entry for element 119, which is excluded.)
"""
const _element_symbols = Set{Symbol}(Symbol(e.symbol) for e in PeriodicTable.elements if e.number <= 118)

_formula_error(str,pos,msg) = throw(ArgumentError("Invalid formula \"$str\" at position $pos: $msg"))

"""
    parse_formula(str::AbstractString) -> Dict{Symbol,Int}

Parse an elemental formula string into a dictionary from element symbol to atom count.

Supported syntax:
- element symbols (one capital letter, optionally one lowercase letter) with an optional integer
  count: `C6H12O6`, `NaCl`. `CO` is carbon monoxide and `Co` is cobalt.
- groups in parentheses or square brackets with an optional multiplier: `Fe(OH)3`, `K4[Fe(CN)6]`.
- hydrate parts joined by a middle dot `·` or an ASCII period, each with an optional leading integer
  coefficient: `FeSO4·7H2O`, `FeSO4.7H2O`, `2NaOH·H2O`.

Elements can appear in any order. A repeated element is summed. Charge is not part of the formula
string. Whitespace, fractional coefficients, isotopes (`[13C]`, `D`, `T`) and unknown symbols raise
an `ArgumentError`.
"""
function parse_formula(str::AbstractString)
    s = String(str)
    isempty(s) && throw(ArgumentError("Invalid formula: the string is empty"))
    chars = collect(s)
    n = length(chars)
    pos = 1

    peek() = pos <= n ? chars[pos] : nothing

    function read_int()
        start = pos
        while pos <= n && isdigit(chars[pos]) && isascii(chars[pos])
            pos += 1
        end
        pos == start && return nothing
        val = parse(Int,String(chars[start:pos-1]))
        val == 0 && _formula_error(s,start,"a count of zero is not allowed")
        return val
    end

    # Parses a sequence of atoms/groups until a closing bracket, a hydrate separator, or the end of
    # the string; returns the accumulated counts.
    function read_sequence(closer::Union{Char,Nothing})
        counts = Dict{Symbol,Int}()
        start = pos
        while true
            c = peek()
            if c === nothing || c in ('·','.') || (closer !== nothing && c == closer)
                break
            elseif c in (')',']')
                _formula_error(s,pos,"unmatched closing \"$c\"")
            elseif c in ('(','[')
                if c == '[' && pos < n && isdigit(chars[pos+1])
                    _formula_error(s,pos,"isotopes are not supported (\"[$(chars[pos+1])...\")")
                end
                open_pos = pos
                pos += 1
                inner = read_sequence(c == '(' ? ')' : ']')
                peek() == (c == '(' ? ')' : ']') || _formula_error(s,open_pos,"unclosed \"$c\"")
                pos += 1
                mult = something(read_int(),1)
                for (k,v) in inner
                    counts[k] = get(counts,k,0) + v*mult
                end
            elseif isuppercase(c) && isascii(c)
                sym_start = pos
                pos += 1
                if pos <= n && islowercase(chars[pos]) && isascii(chars[pos])
                    pos += 1
                end
                sym = Symbol(String(chars[sym_start:pos-1]))
                if !(sym in _element_symbols)
                    hint = sym in (:D,:T) ? " (isotopes are not supported)" : ""
                    _formula_error(s,sym_start,"unknown element symbol \"$sym\"$hint")
                end
                counts[sym] = get(counts,sym,0) + something(read_int(),1)
            elseif c in ('+','-','^','⁺','⁻')
                _formula_error(s,pos,"charge is not part of a formula; give it as a separate argument")
            elseif isspace(c)
                _formula_error(s,pos,"whitespace is not allowed")
            else
                _formula_error(s,pos,"unexpected character \"$c\"")
            end
        end
        pos == start && _formula_error(s,pos,"expected an element or group")
        return counts
    end

    total = Dict{Symbol,Int}()
    while true
        coeff = something(read_int(),1)
        part = read_sequence(nothing)
        for (k,v) in part
            total[k] = get(total,k,0) + v*coeff
        end
        peek() === nothing && break
        pos += 1 # consume the hydrate separator
    end
    return total
end

"""
    formula_mass(counts::AbstractDict{Symbol,<:Integer}) -> Unitful.MolarMass
    formula_mass(str::AbstractString)

Return the molar mass (in g/mol) of a formula given as element counts or as a formula string (see
[`parse_formula`](@ref)), summed from the atomic masses in PeriodicTable.jl. The atomic mass in
daltons is taken as the molar mass in g/mol.
"""
function formula_mass(counts::AbstractDict{Symbol,<:Integer})
    isempty(counts) && throw(ArgumentError("Cannot compute the mass of an empty formula"))
    total = 0.0
    for (sym,k) in counts
        sym in _element_symbols || throw(ArgumentError("unknown element symbol \"$sym\""))
        total += k*ustrip(u"u",PeriodicTable.elements[sym].atomic_mass)
    end
    return total*u"g/mol"
end
formula_mass(str::AbstractString) = formula_mass(parse_formula(str))

"""
    formula_string(counts::AbstractDict{Symbol,<:Integer}) -> String

Write element counts as a canonical formula string in Hill order: carbon first and hydrogen second
when carbon is present, then the remaining elements alphabetically (all elements alphabetically when
there is no carbon). A count of one is omitted. [`parse_formula`](@ref) reads the result back to the
same counts, so equal formulas always give the same string.
"""
function formula_string(counts::AbstractDict{Symbol,<:Integer})
    isempty(counts) && throw(ArgumentError("Cannot write an empty formula"))
    syms = sort!(collect(keys(counts)),by=String)
    if :C in syms
        syms = vcat(:C, (:H in syms ? [:H] : Symbol[]), filter(s->s!==:C && s!==:H,syms))
    end
    return join((counts[s]==1 ? String(s) : "$(s)$(counts[s])") for s in syms)
end
