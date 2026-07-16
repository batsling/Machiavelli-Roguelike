extends Resource
class_name Card

## Core data for a single Machiavelli card.
## Effects are modeled as flags/data rather than subclasses so a card can carry
## more than one effect at once (e.g. Sticky + Spiked) without a class explosion.

enum Effect {
	NONE,
	CLEAR,       # See-through: reveals hidden info
	STICKY,      # Binds this card to its connected neighbors; bound cluster moves as a unit
	SPIKED,      # Deals damage when moved
	BRITTLE,     # Can only be moved once, ever
	BOMB,        # Destroys adjacent connected cards when triggered
	CLONE,       # Copies itself + left/right neighbors onto the board
	TRIGGER,     # Reacts when a card is played into its set (damage/heal)
	MIRRORED,    # 4-sided card; belongs to two sets at once
}

@export var suit: String = ""        # e.g. "hearts", "spades" — follows source Machiavelli suits
@export var rank: int = 0            # 1-13
@export var owner_id: int = -1       # which player/opponent this card currently belongs to
@export var effects: Array[Effect] = []

# Tracks whether a Brittle card has already used its one move.
var has_moved: bool = false

func has_effect(e: Effect) -> bool:
	return effects.has(e)

func can_move() -> bool:
	if has_effect(Effect.BRITTLE) and has_moved:
		return false
	return true

func mark_moved() -> void:
	has_moved = true
