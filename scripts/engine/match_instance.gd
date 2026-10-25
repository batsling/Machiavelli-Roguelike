class_name MatchInstance
extends RefCounted

## An instance: a rule card revealed face up during a match, in the style of
## Marvel Snap's locations. Each match draws a few from the pool
## (GameManager.instance_deck) and reveals one at the start of each round in
## GameManager.instance_rounds, so at most that many are active.
##
## Every instance affects every player, not just whoever's turn it is:
##  - REVEAL instances act on each player's turn in the round the instance is
##    revealed (that turn is "this turn" in their text). A choice ("choose 2
##    cards ...") becomes a pending choice the player resolves before they play
##    (GameManager.pending_choice / resolve_choice).
##  - ONGOING instances act at the start of every player's turn, and their rules
##    stay in force, for the rest of the match.
## Every instance also comes with a combo: a random valid three-card group built
## from fresh cards that belong to neither player's deck (Card.deck_owner -1).
## It joins the table the moment the instance is revealed, for anyone to build
## on — and every card played from hand into a group holding a combo card earns
## COMBO_COINS coins.
##
## Everything about an instance comes from its row in the `Instances` sheet of
## tools/Machiavelli Roguelike.xlsx (via data/instances/, see Instances): its
## name, Type, rule text and Effect — the commands it runs (see InstanceEffect).
## The pool is every row whose Effect parses; a row with an empty or broken
## Effect stays out with a warning naming the problem.

enum Kind { REVEAL, ONGOING }

## Coins each card played from hand into a group holding an instance combo card
## earns its player (GameManager.pending_combo_coins).
const COMBO_COINS := 1
## The deck_owner of combo cards: they come from outside every player's deck.
const NO_OWNER := -1

## The sheet's Name, slugified ("Coin Rush" -> &"coin_rush").
var id: StringName = &""
var kind: Kind = Kind.REVEAL
var title := ""
var text := ""
## The parsed Effect cell, run in order.
var effects: Array[InstanceEffect] = []
## What is wrong with the Effect cell; non-empty keeps the instance out of play.
var errors := PackedStringArray()
## The round this instance was revealed in, or 0 while it is still face down.
var revealed_round := 0
## The combo this instance puts on the table when revealed (built then, so it
## stays secret while the instance is face down); empty until revealed.
var combo: Array[Card] = []

## A fresh instance from its sheet row.
static func from_data(data: InstanceData) -> MatchInstance:
	var e := MatchInstance.new()
	e.id = data.id
	e.title = data.title
	e.text = data.text
	e.kind = Kind.ONGOING if data.kind == "ongoing" else Kind.REVEAL
	var parsed := InstanceEffect.parse(data.effect)
	e.effects.assign(parsed["effects"])
	e.errors = parsed["errors"]
	return e

## A fresh copy of the instance with this id (the sheet's Name, slugified), or
## null when the sheet has no such row.
static func named(instance_id: StringName) -> MatchInstance:
	var data := Instances.get_by_id(instance_id)
	return from_data(data) if data != null else null

## An instance built straight from an Effect string, for tests and tools.
static func custom(effect: String, ongoing := false, name := "Custom") -> MatchInstance:
	var data := InstanceData.new()
	data.id = StringName(name.to_snake_case())
	data.title = name
	data.kind = "ongoing" if ongoing else "reveal"
	data.effect = effect
	return from_data(data)

func is_revealed() -> bool:
	return revealed_round > 0

func is_ongoing() -> bool:
	return kind == Kind.ONGOING

## "Reveal" / "Ongoing", for the instance panel and the log.
func kind_label() -> String:
	return "Ongoing" if is_ongoing() else "Reveal"

## The commands of this verb.
func effects_of(verb: InstanceEffect.Verb) -> Array[InstanceEffect]:
	var out: Array[InstanceEffect] = []
	for eff in effects:
		if eff.verb == verb:
			out.append(eff)
	return out

## "7♥ 8♥ 9♥" — the combo's cards, for the instance panel and the log.
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
	c.from_instance = true
	return c

## A fresh copy of every playable instance in the pool, in sheet order. A row
## whose Effect is empty or doesn't parse is left out, with a warning saying why.
static func pool() -> Array[MatchInstance]:
	var out: Array[MatchInstance] = []
	for data in Instances.all():
		var e := from_data(data)
		if data.effect.strip_edges() == "":
			push_warning("[MatchInstance] '%s' has no Effect in the sheet yet; left out of the pool"
				% e.title)
			continue
		if not e.errors.is_empty():
			push_error("[MatchInstance] '%s' Effect can't be read: %s"
				% [e.title, "; ".join(e.errors)])
			continue
		out.append(e)
	return out

## `count` distinct instances drawn at random from the pool, fresh for one match.
## Pass an rng for a reproducible draw.
static func draw(count: int, rng: RandomNumberGenerator = null) -> Array[MatchInstance]:
	var all := pool()
	for i in range(all.size() - 1, 0, -1):
		var j := rng.randi_range(0, i) if rng != null else randi_range(0, i)
		var tmp := all[i]
		all[i] = all[j]
		all[j] = tmp
	var out: Array[MatchInstance] = []
	for i in mini(count, all.size()):
		out.append(all[i])
	return out
