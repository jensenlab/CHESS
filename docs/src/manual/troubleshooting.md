# Troubleshooting

A lookup of the error types CHESSCore raises most often, what triggers each one, and where the
concept behind it is covered in detail.

## `LockedLocationError`

Thrown by [`move_into!`](@ref) when the location being moved is [`is_locked`](@ref). Locked
locations cannot be moved from their current parent, though their own children can still be moved.
See [Movement & Occupancy](movement.md) for the full set of move-refusal reasons.

## `AlreadyLocatedInError`

Thrown by [`move_into!`](@ref) when the location being moved is already inside the target parent.
See [Movement & Occupancy](movement.md).

## `OccupancyError`

Thrown by [`move_into!`](@ref) when the move would exceed the parent's remaining capacity, per its
[`occupancy`](@ref)/[`occupancy_cost`](@ref) accounting. See [Movement & Occupancy](movement.md)
for how occupancy cost is computed.

## `FixedMembershipError`

Thrown when trying to add or remove a slot from a `Labware`'s fixed internal structure, or move a
`Well` independently of its `Labware` -- both are permanently fixed at construction. See
[Locations](core-concepts.md) for the generic-vs-fixed distinction between `GenericLocation` and
`Labware`/`Well`, and [Movement & Occupancy](movement.md) for how it applies to `move_into!`.

## `MixingError`

Thrown by `Stock` subtraction (`-`) when the result would leave a reagent at a negative quantity.
See [Stocks](stocks.md) for `Stock` arithmetic.
