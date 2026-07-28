




function can_place(l::Labware,d::DeckPosition)
    return kind(l).name in labware(d)
  end


function can_place(l::Labware,d::UnconstrainedPosition)
    return true 
end 

function can_place(l::Labware,d::EmptyPosition)
  return false 
end 


function can_place(labware::Labware,deck::Deck)

  for pos in deck
    if can_place(labware,pos)
      return true
    end
  end
  return false
end


"""
    can_operate(h::Head,l::Labware) -> Bool

Return whether `h` can actually aspirate or dispense with `l` -- i.e. whether `Mask(h,l)` is
non-trivial. Every instrument's `Mask` method returns the trivial default
`Mask(h,l,(x,y,z)->false,(x,y,z)->false,(0,0),(0,0))` for an unsupported labware kind, so checking
`asp_positions`/`disp_positions` against `(0,0)` is sufficient without invoking the mask functions
themselves.
"""
function can_operate(h::Head,l::Labware)
  m = Mask(h,l)
  return asp_positions(m) != (0,0) || disp_positions(m) != (0,0)
end

# The true schedulable set is the intersection of Deck-admissibility and Head-operability -- a
# labware kind can be admissible to a deck position (matching an instrument's own explicit
# admissibility set, see instruments/*.jl) while still having no real Mask for this instrument's Head.
function can_place(l::Labware,config::Configuration)
  return can_place(l,deck(config)) && can_operate(head(config),l)
end

function can_place(l::Labware,d::DeckPosition,config::Configuration)
  return can_place(l,d) && can_operate(head(config),l)
end


function can_aspirate(l::Labware,d::DeckPosition)

  return can_place(l,d) && can_aspirate(d)
end

function can_dispense(l::Labware,d::DeckPosition)
  return can_place(l,d) && can_dispense(d)
  
end


