# Reagents & Species

```@meta
DocTestSetup = :(using CHESS)
```

The material in a `Well` is described on two levels. A [`Reagent`](@ref) is the physical material
that is weighed or pipetted: table salt, a bottle of ethanol. A [`Species`](@ref) is an entity in
solution: Na⁺, Cl⁻, glucose. Table salt is one reagent, and once dissolved it is two species. A
[`Dissolution`](@ref) connects the two by listing the species a reagent breaks into.

Each species carries an elemental formula such as `C6H12O6`. Atomic masses from the periodic table
turn a formula into a molecular weight, and a reagent's formula follows from its species, so a
stock's amount of any element can be counted. This chapter covers the formulas, the two types, and
the dissolution that links them. [Composition & Solution Chemistry](composition.md) covers what
CHESS computes from them: molar amounts, element amounts, and pH.

## Elemental formulas

A formula is written as a string. Element symbols are one capital letter with an optional lowercase
letter, followed by an optional whole-number count, so `CO` is carbon monoxide and `Co` is cobalt.
Parentheses or square brackets group atoms, and a middle dot or a period joins the parts of a
hydrate, each with an optional whole-number coefficient. Elements may appear in any order, and a
repeated element is summed. Three functions work with formulas. `CHESSCore.parse_formula` reads a
string into a dictionary from element symbol to atom count, `CHESSCore.formula_mass` gives the molar
mass from the atomic masses of the PeriodicTable.jl package, and `CHESSCore.formula_string` writes
the counts back as a string in Hill order (carbon first, hydrogen second, then the other elements
alphabetically):

```jldoctest reagents
julia> counts = CHESSCore.parse_formula("FeSO4·7H2O");

julia> sort(collect(counts))
4-element Vector{Pair{Symbol, Int64}}:
 :Fe => 1
  :H => 14
  :O => 11
  :S => 1

julia> round(u"g/mol", CHESSCore.formula_mass(counts); digits=3)
278.006 g mol⁻¹

julia> CHESSCore.formula_string(counts)
"FeH14O11S"
```

Charge is not part of a formula string. A species takes its charge as a separate argument, and a
formula that contains a charge, an unknown element symbol, or an isotope is rejected:

```jldoctest reagents
julia> CHESSCore.parse_formula("Na+")
ERROR: ArgumentError: Invalid formula "Na+" at position 3: charge is not part of a formula; give it as a separate argument
```

Isotopes are not supported. Every formula describes the natural isotopic mixture, and the notation
`[13C]` and the symbols `D` and `T` are reserved for a later extension, so they raise an error
instead of being read as something else. A formula also cannot describe a fractional amount, such
as the half water of a hemihydrate. A [`Dissolution`](@ref) can (see
[Fractional amounts](#Fractional-amounts)).

## Species

A species has a `name`, an integer `charge` (zero for a neutral species), and a description of its
atoms. The description is one of three kinds:

- an elemental formula, from which the molecular weight is derived;
- a stored molecular weight, for a species whose formula has not been registered yet; or
- the marker `opaque`, for a species whose atoms are intentionally not described (see
  [Opaque reagents](#Opaque-reagents)).

CHESS registers common ions such as Na⁺, Cl⁻, and Ca²⁺. [`@species`](@ref) registers a new species
from a label, a name, a charge, and a formula:

```jldoctest reagents
julia> @species Li⁺ "Li+" 1 "Li"
Li⁺

julia> round(u"g/mol", molecular_weight(Li⁺); digits=3)
6.94 g mol⁻¹
```

[`@spc_str`](@ref) recalls a registered species by name. The ASCII form `spc"Na+"` finds `Na⁺`.

A species can record the PubChem ID of its compound, as an optional last argument of
[`@species`](@ref). The ID is descriptive metadata, available from [`pubchemid`](@ref). It is not part of
the species' identity, so a species is equal to one with the same name, charge, and formula whatever IDs
they carry:

```jldoctest reagents
julia> @species Rb⁺ "Rb+" 1 "Rb" 105153
Rb⁺

julia> pubchemid(Rb⁺)
105153

julia> Rb⁺ == Species("Rb+", 1, "Rb")
true
```

A species is identified by its name. Two species are equal when their name, charge, and formula are
equal, whatever order the elements were written in. Registering the same name and charge with a
different formula therefore gives a different species and never a silent merge. Isomers are separate
species with separate names, because a formula is a property of a species and not its identity:

```jldoctest reagents
julia> Species("D-glucose", 0, "C6H12O6") == Species("D-glucose", 0, "H12C6O6")
true

julia> Species("D-glucose", 0, "C6H12O6") == Species("D-fructose", 0, "C6H12O6")
false
```

A species does not store its structure, so stereoisomers such as D-glucose and L-glucose differ only
by name. [`molecular_weight`](@ref) of a species with a formula comes from atomic masses, and the
species has no stored weight that could disagree with it.

## Reagent types

`Reagent` is an abstract type with three concrete subtypes, `Solid`, `Liquid`, and `Gas`, which
share three fields: `name`, `molecular_weight`, and `density`. A solid is dosed by mass or amount and a
liquid by volume. A liquid can also be dosed by mass or amount: either is converted to a volume with the
liquid's density, and an unknown density is an error. A reagent has no PubChem ID of its own, because PubChem identifies compounds. The
ID belongs to the species a reagent is made of, and [`pubchemid`](@ref) of a reagent made of one species
returns that species' ID. CHESS already includes a starter set of reagents, which [`@rgt_str`](@ref)
recalls by name:

```jldoctest reagents
julia> rgt"water"
water

julia> molecular_weight(rgt"water")
18.015 g mol⁻¹

julia> density(rgt"water")
1.0 g mL⁻¹

julia> pubchemid(rgt"water")
962
```

## Defining a reagent

[`@reagent`](@ref) registers a new reagent from a label, a name, a type, a description of its
chemistry, a density, and the PubChem ID of the species it is made of. The chemistry argument says
what the reagent is made of. An
elemental formula string registers the reagent as a single neutral species with that formula, and
the molecular weight is derived from the formula:

```jldoctest reagents
julia> @reagent mysugar "my sugar" Solid "C6H12O6" 1.2u"g/mL" missing
my sugar

julia> molecular_weight(mysugar)
180.156 g mol⁻¹

julia> sort(collect(CHESSCore.formula(only(keys(dissolution(mysugar).products)))))
3-element Vector{Pair{Symbol, Int64}}:
 :C => 6
 :H => 12
 :O => 6
```

A [`Dissolution`](@ref) in the chemistry argument registers a reagent that breaks into several
species (see [Dissolution](#Dissolution)). A molar mass, such as `180.16u"g/mol"`, may be given in
place of a formula for a reagent whose formula has not been registered. The reagent then keeps that
stored molecular weight and has no formula. Any of the properties can be left unknown, so a reagent
can be registered and used with incomplete data:

```jldoctest reagents
julia> @reagent myreagent "my made-up reagent" Solid missing missing missing
my made-up reagent

julia> molecular_weight(myreagent)
missing
```

An invalid formula string is rejected when the reagent is defined.

## Products

A reagent is a material identified by its composition. A [`ReagentProduct`](@ref) records one way the lab
obtains it: the supplier, the catalog number, the vendor's product name, the manufacturer number, the grade
as the vendor states it, and notes. A reagent has no product, one, or several. Two vendors' urea are two
products of one reagent, and the in-house water supply is a product with no catalog number. A product holds
only what stays true across purchases. Price, quantity, received date, lot, and shelf location describe a
purchase or a bottle and are not recorded. A stated purity is information only: the reagent is the pure
composition, and nothing reads the grade.

[`@reagent_product`](@ref) registers a product of a reagent, and [`reagent_products`](@ref) returns the
products registered for it:

```jldoctest reagents
julia> @reagent carbamide "carbamide" Solid "CH4N2O" 1.34u"g/mL" missing
carbamide

julia> @reagent_product carbamide "Sigma-Aldrich" catalog_number="U5128" product_name="Urea ACS reagent" grade="ACS reagent"

julia> @reagent_product carbamide "in-house"

julia> reagent_products(carbamide)
2-element Vector{ReagentProduct}:
 Sigma-Aldrich U5128
 in-house

julia> reagent_products(carbamide)[1].grade
"ACS reagent"
```

A product that is already registered for the reagent is not added twice. Products are kept with the module
that registers them, as dissolutions are, so a lab module's products are available once it is registered.

## Opaque reagents

Some materials have no formula: an undefined mixture such as yeast extract, a polymer of varying
length, or a product sold as a mixture of related compounds. The word `opaque` in the chemistry
argument marks a reagent whose atoms are intentionally not described. Declaring it opaque is
different from leaving the formula out, because [`atoms`](@ref) warns about a reagent with no
registered formula and says nothing about an opaque one. An opaque reagent has no molecular weight
unless one is given by calling `opaque` with a molar mass. That form suits a mixture sold as a salt,
or a solution whose stated purity makes its effective molecular weight differ from the compound's:

```jldoctest reagents
julia> @reagent mymixture "my undefined mixture" Solid opaque 1.0u"g/mL" missing
my undefined mixture

julia> molecular_weight(mymixture)
missing

julia> @reagent mysolution "my 88% solution" Solid opaque(102.4u"g/mol") 1.2u"g/mL" missing
my 88% solution

julia> molecular_weight(mysolution)
102.4 g mol⁻¹
```

An opaque reagent with a molar mass has its moles tracked, so concentrations work, but its atoms are
not counted by [`atoms`](@ref).

## Dissolution

Every `Reagent` has a [`dissolution`](@ref), a [`Dissolution`](@ref) that lists the species it
breaks down into when dissolved, with a coefficient for each. The default dissolution is the
reagent's own identity as a single species, which means no dissociation:

```jldoctest reagents
julia> dissolution(rgt"water")
Dissolution(Dict{Species, Float64}(water => 1.0))
```

`+` and `*` on species build a `Dissolution`. Adding species lists them, and multiplying by a number
sets a coefficient, as for the two chlorides that balance Ca²⁺:

```jldoctest reagents
julia> salt = spc"Ca2+" + 2*spc"Cl-";

julia> salt.products[spc"Cl-"], salt.products[spc"Ca2+"]
(2.0, 1.0)
```

A dissolution in the chemistry argument of [`@reagent`](@ref) registers the reagent and its
dissolution in one step. The molecular weight is derived from the species and their coefficients, so
the two cannot disagree. A hydrate lists its water of hydration as a species:

```jldoctest reagents
julia> @reagent LiCl "lithium chloride" Solid (Li⁺ + spc"Cl-") missing missing
lithium chloride

julia> round(u"g/mol", molecular_weight(LiCl); digits=2)
42.39 g mol⁻¹
```

### Fractional amounts

Coefficients are amounts per mole of reagent and do not have to be whole numbers. A hemihydrate is one
mole of the compound with half a mole of water:

```jldoctest reagents
julia> @species Glucoside "my glucoside" 0 "C7H14O6"
Glucoside

julia> @reagent hemihydrate "my hemihydrate" Solid (Glucoside + 0.5*spc"H2O") missing missing
my hemihydrate

julia> round(u"g/mol", molecular_weight(hemihydrate); digits=2)
203.19 g mol⁻¹
```

A product sold as a solution is described the same way, with its solvent as a species. [`by_mass`](@ref)
takes the mass fractions that the label gives and converts them to moles per mole of the first species,
which is the species that a molar amount of the reagent counts. An 88% w/w solution of an acid has the
molar mass of the whole product per mole of acid:

```jldoctest reagents
julia> @species MyAcid "my acid" 0 "C3H6O3"
MyAcid

julia> @reagent solution "my 88% acid" Liquid by_mass(MyAcid => 0.88, spc"H2O" => 0.12) 1.2u"g/mL" missing
my 88% acid

julia> round(u"g/mol", molecular_weight(solution); digits=1)
102.4 g mol⁻¹

julia> round(dissolution(solution).products[spc"H2O"]; digits=3)
0.682
```

Only the composition is modeled. A solid sold at a purity grade, such as 99%, is registered as the
pure species.

[`set_dissolution!`](@ref) registers the dissolution of a reagent that is already defined. The
dissolutions are held in [`dissolutions`](@ref), keyed by the reagent itself and not by its type,
because every reagent is a value of one of three types and the type cannot tell two solids apart.
A reagent is neutral, so the charges of its products, weighted by their coefficients, must sum to
zero:

```jldoctest reagents
julia> @reagent DemoSalt "demo salt" Solid missing missing missing;

julia> @species DemoCation "DemoCation" 1 "K";

julia> @species DemoAnion "DemoAnion" -1 "Br";

julia> set_dissolution!(DemoSalt, DemoCation + DemoAnion);

julia> sort(string.(keys(dissolution(DemoSalt).products)))
2-element Vector{String}:
 "DemoAnion"
 "DemoCation"

julia> DemoSalt in keys(dissolutions)
true

julia> set_dissolution!(DemoSalt, Dissolution(Dict(DemoCation => 1)))
ERROR: ArgumentError: The dissolution of "demo salt" has a net charge of 1; a reagent is neutral, so the charges of its products must sum to zero
```

Dissolution coefficients must be non-negative. A base's hydroxide is represented by the canonical
[`OH⁻`](@ref) species, not a negative [`H⁺`](@ref) count. This lets `pH` (see
[Composition & Solution Chemistry](composition.md)) net acid and base contributions by explicit
subtraction instead of signed stoichiometry.

A weak acid or base only partially dissociates, so a fixed `Dissolution` cannot describe it.
It is registered as an [`AcidBaseSystem`](@ref) instead. See [Acid/Base Chemistry](acid-base.md).
