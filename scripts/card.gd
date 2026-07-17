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
const JOKER_GLYPH := "★"

@export var suit: String = ""        # "hearts", "diamonds", "clubs", "spades" ("joker" for jokers)
@export var rank: int = 0            # 1-13 (ace = 1); 0 for jokers
@export var owner_id: int = -1       # which player/opponent this card currently belongs to
@export var effects: Array[Effect] = []
@export var is_joker: bool = false   # counts as any card; see Rules.assign_jokers

# What the joker currently stands for on the table (0 / "" while it sits free
# in a hand or its meld is invalid). Recomputed by Rules.assign_jokers().
var joker_rank: int = 0
var joker_suit: String = ""

# Which card the joker's holder wants it to stand for when the meld leaves a
# choice (e.g. two missing suits in a set, or a spare joker that could extend
# either end of a run). Honored by Rules.assign_jokers() whenever it still
# fits the meld; cleared when the joker returns to a hand.
var joker_pref_rank: int = 0
var joker_pref_suit: String = ""

# Once a turn that placed this joker is committed, the joker locks to the
# card it was placed as (GameManager.commit_turn): from then on the rules
# treat it as exactly that card — rearrange it anywhere, it is no longer a
# wildcard — until it returns to a hand via the joker swap. 0/"" = free.
var joker_lock_rank: int = 0
var joker_lock_suit: String = ""

# Tracks whether a Brittle card has already used its one move.
var has_moved: bool = false

func label() -> String:
	if is_joker:
		return JOKER_GLYPH if joker_rank == 0 else JOKER_GLYPH + rep_label()
	var rank_text: String = RANK_NAMES.get(rank, str(rank))
	var suit_text: String = SUIT_SYMBOLS.get(suit, suit)
	return "%s%s" % [rank_text, suit_text]

## The card this joker stands for, e.g. "7♥". Only meaningful when a valid
## meld has assigned the joker a value.
func rep_label() -> String:
	var rank_text: String = RANK_NAMES.get(joker_rank, str(joker_rank))
	var suit_text: String = SUIT_SYMBOLS.get(joker_suit, joker_suit)
	return "%s%s" % [rank_text, suit_text]

func has_effect(e: Effect) -> bool:
	return effects.has(e)

func can_move() -> bool:
	if has_effect(Effect.BRITTLE) and has_moved:
		return false
	return true

func mark_moved() -> void:
	has_moved = true
