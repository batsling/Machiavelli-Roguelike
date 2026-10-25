class_name MatchEvent
extends RefCounted

## A board event: a rule card revealed face up during a match, Marvel Snap
## location style. Events are mechanics only for now (no theme). Each match draws
## a few from the pool (GameManager.event_deck) and reveals one at the start of
## each round in GameManager.event_rounds, so at most that many are active.
##
## Every event affects every player, not just whoever's turn it is:
##  - ON_REVEAL events act once per player, on each player's turn in the round
##    the event is revealed (that turn is "this turn" in their text). A choice
##    ("choose 2 cards ...") becomes a pending choice the player resolves before
##    they play (GameManager.pending_choice / resolve_choice).
##  - ONGOING events stay in force for the rest of the match.
## GameManager applies the rules; this class only names and describes them.

enum Kind { ON_REVEAL, ONGOING }

enum Id {
	CYCLE,        # on reveal: choose 2 cards to discard, then draw 2
	GIFT,         # on reveal: choose 2 cards to give to the opponent
	SURGE,        # on reveal: +3 energy this turn
	OVERCHARGE,   # ongoing: +1 max energy
	EXTRA_DRAW,   # ongoing: draw 1 more whenever you draw
	ATTRITION,    # ongoing: discard 1 random card at the start of your turn
	COIN_RUSH,    # on reveal: this turn each card played gives +1 coin
	OPEN_DECKS,   # ongoing: the top card of every deck is face up
}

## Cards chosen by the CYCLE and GIFT events.
const CHOICE_COUNT := 2
## Bonus energy SURGE gives on the reveal turn.
const SURGE_ENERGY := 3

var id: Id = Id.CYCLE
var kind: Kind = Kind.ON_REVEAL
var title := ""
var text := ""
## The round this event was revealed in, or 0 while it is still face down.
var revealed_round := 0

func _init(id_value: Id = Id.CYCLE) -> void:
	id = id_value
	match id:
		Id.CYCLE:
			_describe(Kind.ON_REVEAL, "Cycle",
				"Choose %d cards to discard, then draw %d." % [CHOICE_COUNT, CHOICE_COUNT])
		Id.GIFT:
			_describe(Kind.ON_REVEAL, "Gift",
				"Choose %d cards to give to your opponent." % CHOICE_COUNT)
		Id.SURGE:
			_describe(Kind.ON_REVEAL, "Surge", "Gain +%d energy this turn." % SURGE_ENERGY)
		Id.OVERCHARGE:
			_describe(Kind.ONGOING, "Overcharge", "+1 max energy.")
		Id.EXTRA_DRAW:
			_describe(Kind.ONGOING, "Extra Draw", "Draw 1 more card whenever you draw.")
		Id.ATTRITION:
			_describe(Kind.ONGOING, "Attrition",
				"Discard 1 random card at the start of your turn.")
		Id.COIN_RUSH:
			_describe(Kind.ON_REVEAL, "Coin Rush", "This turn, each card played gives +1 coin.")
		Id.OPEN_DECKS:
			_describe(Kind.ONGOING, "Open Decks", "The top card of every deck is face up.")

func _describe(kind_value: Kind, title_value: String, text_value: String) -> void:
	kind = kind_value
	title = title_value
	text = text_value

func is_revealed() -> bool:
	return revealed_round > 0

func is_ongoing() -> bool:
	return kind == Kind.ONGOING

## "On reveal" / "Ongoing", for the event panel and the log.
func kind_label() -> String:
	return "Ongoing" if is_ongoing() else "On reveal"

## A fresh copy of every event in the pool.
static func pool() -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	for id_value in Id.values():
		out.append(MatchEvent.new(id_value))
	return out

## `count` distinct events drawn at random from the pool, fresh for one match.
## Pass an rng for a reproducible draw.
static func draw(count: int, rng: RandomNumberGenerator = null) -> Array[MatchEvent]:
	var all := pool()
	for i in range(all.size() - 1, 0, -1):
		var j := rng.randi_range(0, i) if rng != null else randi_range(0, i)
		var tmp := all[i]
		all[i] = all[j]
		all[j] = tmp
	var out: Array[MatchEvent] = []
	for i in mini(count, all.size()):
		out.append(all[i])
	return out
