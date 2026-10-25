class_name MatchLocation
extends RefCounted

## A location: a rule card revealed face up during a match, in the style of
## Marvel Snap's locations. Locations are mechanics only for now (no theme).
## Each match draws a few from the pool (GameManager.location_deck) and reveals one at the start of
## each round in GameManager.location_rounds, so at most that many are active.
##
## Every location affects every player, not just whoever's turn it is:
##  - ON_REVEAL locations act once per player, on each player's turn in the round
##    the location is revealed (that turn is "this turn" in their text). A choice
##    ("choose 2 cards ...") becomes a pending choice the player resolves before
##    they play (GameManager.pending_choice / resolve_choice).
##  - ONGOING locations stay in force for the rest of the match.
## Every location also comes with a combo: a random valid three-card group built
## from fresh cards that belong to neither player's deck (Card.deck_owner -1).
## It joins the table the moment the location is revealed, for anyone to build on.
## GameManager applies the rules; this class names and describes them and
## builds the combos.
##
## The NAMES, kinds and rule text come from the `Locations` sheet of
## tools/Machiavelli Roguelike.xlsx (via data/locations/, see Locations); the
## rules themselves are code, matched to a sheet row by ID_NAMES. The pool is
## the rows that have a rule: delete a row and that location leaves the game;
## add a row with no rule yet and it waits, with a warning, until one is written.

enum Kind { ON_REVEAL, ONGOING }

enum Id {
	CYCLE,        # on reveal: choose 2 cards to discard, then draw 2
	GIFT,         # on reveal: choose 2 cards to give to the opponent
	SURGE,        # on reveal: +3 energy this turn
	OVERCHARGE,   # on reveal: +2 max energy for the rest of the match
	EXTRA_DRAW,   # ongoing: draw 1 more whenever you draw
	ATTRITION,    # ongoing: discard 1 random card at the start of your turn
	COIN_RUSH,    # on reveal: this turn each card played gives +1 coin
	OPEN_DECKS,   # ongoing: the top card of every deck is face up
}

## Each rule's location id: the sheet's Name, slugified.
const ID_NAMES := {
	Id.CYCLE: &"cycle",
	Id.GIFT: &"gift",
	Id.SURGE: &"surge",
	Id.OVERCHARGE: &"overcharge",
	Id.EXTRA_DRAW: &"extra_draw",
	Id.ATTRITION: &"attrition",
	Id.COIN_RUSH: &"coin_rush",
	Id.OPEN_DECKS: &"open_decks",
}
## The kind each rule is written as. GameManager reads ongoing rules every turn
## and on-reveal rules only in their reveal round, so the code decides; a sheet
## Type that disagrees is reported and overridden.
const RULE_KINDS := {
	Id.CYCLE: Kind.ON_REVEAL,
	Id.GIFT: Kind.ON_REVEAL,
	Id.SURGE: Kind.ON_REVEAL,
	Id.OVERCHARGE: Kind.ON_REVEAL,
	Id.EXTRA_DRAW: Kind.ONGOING,
	Id.ATTRITION: Kind.ONGOING,
	Id.COIN_RUSH: Kind.ON_REVEAL,
	Id.OPEN_DECKS: Kind.ONGOING,
}

## Cards chosen by the CYCLE and GIFT locations.
const CHOICE_COUNT := 2
## Bonus energy SURGE gives on the reveal turn.
const SURGE_ENERGY := 3
## Max energy OVERCHARGE adds, for good, on each player's reveal turn.
const OVERCHARGE_ENERGY := 2
## The deck_owner of combo cards: they come from outside every player's deck.
const NO_OWNER := -1

var id: Id = Id.CYCLE
var kind: Kind = Kind.ON_REVEAL
var title := ""
var text := ""
## The round this location was revealed in, or 0 while it is still face down.
var revealed_round := 0
## The combo this location puts on the table when revealed (built then, so it
## stays secret while the location is face down); empty until revealed.
var combo: Array[Card] = []

func _init(id_value: Id = Id.CYCLE) -> void:
	id = id_value
	kind = RULE_KINDS[id]
	var loc := Locations.get_by_id(ID_NAMES[id])
	if loc == null:
		push_warning("[MatchLocation] no '%s' row in the Locations sheet" % ID_NAMES[id])
		title = String(ID_NAMES[id]).capitalize()
		return
	title = loc.title
	text = loc.text
	if loc.kind != _kind_name(kind):
		push_error("[MatchLocation] the sheet makes %s '%s', but its rule is written as '%s'"
			% [title, loc.kind, _kind_name(kind)])

static func _kind_name(kind_value: Kind) -> String:
	return "ongoing" if kind_value == Kind.ONGOING else "on_reveal"

## The rule behind a location id, or -1 if no code implements it yet.
static func id_for(location_id: StringName) -> int:
	for id_value: int in ID_NAMES:
		if ID_NAMES[id_value] == location_id:
			return id_value
	return -1

func is_revealed() -> bool:
	return revealed_round > 0

func is_ongoing() -> bool:
	return kind == Kind.ONGOING

## "On reveal" / "Ongoing", for the location panel and the log.
func kind_label() -> String:
	return "Ongoing" if is_ongoing() else "On reveal"

## "7♥ 8♥ 9♥" — the combo's cards, for the location panel and the log.
func combo_label() -> String:
	var parts := PackedStringArray()
	for c in combo:
		parts.append(c.label())
	return " ".join(parts)

## A random valid three-card group of fresh natural cards from outside every
## deck: an even coin flip between a set (one rank, three different suits) and a
## run (one suit, three consecutive ranks, ace low). Drawn from `rng`.
static func random_combo(rng: RandomNumberGenerator) -> Array[Card]:
	var out: Array[Card] = []
	if rng.randi_range(0, 1) == 0:
		var rank := rng.randi_range(1, 13)
		var suits := Deck.SUITS.duplicate()
		for i in range(suits.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp: String = suits[i]
			suits[i] = suits[j]
			suits[j] = tmp
		for i in 3:
			out.append(_combo_card(rank, suits[i]))
	else:
		var suit: String = Deck.SUITS[rng.randi_range(0, Deck.SUITS.size() - 1)]
		var start := rng.randi_range(1, 11)
		for i in 3:
			out.append(_combo_card(start + i, suit))
	return out

static func _combo_card(rank: int, suit: String) -> Card:
	var c := Card.new()
	c.rank = rank
	c.suit = suit
	c.deck_owner = NO_OWNER
	return c

## A fresh copy of every location in the pool: each sheet row with a rule behind
## it, in sheet order.
static func pool() -> Array[MatchLocation]:
	var out: Array[MatchLocation] = []
	for loc in Locations.all():
		var id_value := id_for(loc.id)
		if id_value < 0:
			push_warning("[MatchLocation] location '%s' has no rule in code yet; left out of the pool"
				% loc.title)
			continue
		out.append(MatchLocation.new(id_value))
	return out

## `count` distinct locations drawn at random from the pool, fresh for one match.
## Pass an rng for a reproducible draw.
static func draw(count: int, rng: RandomNumberGenerator = null) -> Array[MatchLocation]:
	var all := pool()
	for i in range(all.size() - 1, 0, -1):
		var j := rng.randi_range(0, i) if rng != null else randi_range(0, i)
		var tmp := all[i]
		all[i] = all[j]
		all[j] = tmp
	var out: Array[MatchLocation] = []
	for i in mini(count, all.size()):
		out.append(all[i])
	return out
