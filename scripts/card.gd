class_name Card
extends Resource

## Core data for a single Machiavelli card.
## Effects are modeled as flags/data rather than subclasses so a card can carry
## more than one effect at once (e.g. Sticky + Spiked) without a class explosion.
## The vanilla engine ignores effects entirely; they are kept for the roguelike layer.

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

const SUIT_SYMBOLS := {"hearts": "♥", "diamonds": "♦", "clubs": "♣", "spades": "♠"}
const RANK_NAMES := {1: "A", 11: "J", 12: "Q", 13: "K"}

@export var suit: String = ""        # "hearts", "diamonds", "clubs", "spades"
@export var rank: int = 0            # 1-13 (ace = 1)
@export var owner_id: int = -1       # which player/opponent this card currently belongs to
@export var effects: Array[Effect] = []

# Tracks whether a Brittle card has already used its one move.
var has_moved: bool = false

func label() -> String:
	var rank_text: String = RANK_NAMES.get(rank, str(rank))
	var suit_text: String = SUIT_SYMBOLS.get(suit, suit)
	return "%s%s" % [rank_text, suit_text]

func has_effect(e: Effect) -> bool:
	return effects.has(e)

func can_move() -> bool:
	if has_effect(Effect.BRITTLE) and has_moved:
		return false
	return true

func mark_moved() -> void:
	has_moved = true
