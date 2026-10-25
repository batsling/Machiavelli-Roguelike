class_name InstanceEffect
extends RefCounted

## ONE COMMAND from an instance's Effect cell in the `Instances` sheet of
## tools/Machiavelli Roguelike.xlsx. An Effect cell holds commands separated by
## `;`, run left to right, e.g. `discard choose 2; draw 2`. InstanceEffect.parse
## turns a cell into commands (or reports what is wrong with it); GameManager
## runs them (see GameManager's Instances section). The full command list, with
## examples, is in data/instances/README.md — keep the two in step.
##
## When a command happens comes from the instance's Type, not the command:
##  - Reveal: on each player's own turn in the round the instance is revealed
##    ("this turn" means that turn).
##  - Ongoing: at the start of each player's turn for the rest of the match.
## Rule commands (energy, draw_bonus, coins_per_card, open_decks, a `cost` rule)
## are in force during those same turns instead of happening once. Table
## commands (destroy) happen once when a Reveal instance turns up, and at the
## start of every round for an Ongoing one.
##
## Commands:
##   draw N                      draw N cards from your own deck
##   draw_joker N                take N jokers from your deck (or discard pile) into your hand
##   discard PICK [FILTER] N     hand cards to your discard pile
##   give PICK [FILTER] N        hand cards to the next player's hand
##   jumble PICK [FILTER] N      hand cards turn into a random rank and suit
##   cost PICK [FILTER] N ±D     hand cards cost D more/less energy for good (never below 0)
##   cost FILTER... V            rule: cards matching FILTER cost V energy
##   energy +N                   rule: +N energy
##   max_energy +N               +N max energy for the rest of the match
##   draw_bonus N                rule: draw N more cards whenever you draw
##   coins_per_card N            rule: +N coins per card played from hand
##   open_decks                  rule: the top card of every deck is face up
##   destroy combo random        a random group on the table (never the instance's own
##                               combo) goes to the discard pile
## PICK is `random` or `choose` followed by a count, or `all`. FILTER narrows the
## cards: rank=7 (or A, J, Q, K), suit=hearts, joker, natural. `random` picks
## within one instance never pick the same card twice ("2 other random cards").

enum Verb {
	DRAW, DRAW_JOKER, DISCARD, GIVE, JUMBLE, COST_CHANGE, COST_RULE,
	ENERGY, MAX_ENERGY, DRAW_BONUS, COINS_PER_CARD, OPEN_DECKS, DESTROY_COMBO,
}

enum Pick { NONE, RANDOM, CHOOSE, ALL }

## What a command acts on: the player whose turn it is, a standing rule, or the table.
enum Scope { PLAYER, RULE, TABLE }

const VERB_NAMES := {
	"draw": Verb.DRAW, "draw_joker": Verb.DRAW_JOKER, "discard": Verb.DISCARD,
	"give": Verb.GIVE, "jumble": Verb.JUMBLE, "cost": Verb.COST_CHANGE,
	"energy": Verb.ENERGY, "max_energy": Verb.MAX_ENERGY, "draw_bonus": Verb.DRAW_BONUS,
	"coins_per_card": Verb.COINS_PER_CARD, "open_decks": Verb.OPEN_DECKS,
	"destroy": Verb.DESTROY_COMBO,
}
## The verbs that take hand cards with a PICK.
const PICK_VERBS := [Verb.DISCARD, Verb.GIVE, Verb.JUMBLE, Verb.COST_CHANGE]
const RANK_WORDS := {"a": 1, "ace": 1, "j": 11, "jack": 11, "q": 12, "queen": 12,
	"k": 13, "king": 13}

var verb: Verb = Verb.DRAW
var pick: Pick = Pick.NONE
## The count for draw/draw_joker/a pick, or the amount for energy and the like.
var count := 0
## A cost change (±D) or a cost rule's value (V).
var amount := 0
## rank (0 = any), suit ("" = any), jokers: 0 = any, 1 = only jokers, -1 = no jokers.
var filter_rank := 0
var filter_suit := ""
var filter_joker := 0
## The command as written, for messages.
var source := ""

func scope() -> Scope:
	match verb:
		Verb.COST_RULE, Verb.ENERGY, Verb.DRAW_BONUS, Verb.COINS_PER_CARD, Verb.OPEN_DECKS:
			return Scope.RULE
		Verb.DESTROY_COMBO:
			return Scope.TABLE
	return Scope.PLAYER

## True when `c` passes this command's filter.
func matches(c: Card) -> bool:
	if filter_joker == 1 and not c.is_joker:
		return false
	if filter_joker == -1 and c.is_joker:
		return false
	if filter_rank > 0 and (c.is_joker or c.rank != filter_rank):
		return false
	if filter_suit != "" and (c.is_joker or c.suit != filter_suit):
		return false
	return true

## Parse an Effect cell into commands. Returns {"effects": Array[InstanceEffect],
## "errors": PackedStringArray}; any error means the instance can't be played.
static func parse(cell: String) -> Dictionary:
	var effects: Array[InstanceEffect] = []
	var errors := PackedStringArray()
	for part in cell.split(";"):
		var text := part.strip_edges()
		if text == "":
			continue
		var e := InstanceEffect.new()
		var err := e._parse_command(text)
		if err != "":
			errors.append("'%s': %s" % [text, err])
		else:
			effects.append(e)
	if effects.is_empty() and errors.is_empty():
		errors.append("no commands")
	return {"effects": effects, "errors": errors}

func _parse_command(text: String) -> String:
	source = text
	var words: Array[String] = []
	for w in text.to_lower().split(" ", false):
		words.append(w)
	var name: String = words.pop_front()
	if not VERB_NAMES.has(name):
		return "unknown command '%s' (commands: %s)" % [name, ", ".join(VERB_NAMES.keys())]
	verb = VERB_NAMES[name]
	match verb:
		Verb.DRAW, Verb.DRAW_JOKER, Verb.DRAW_BONUS, Verb.COINS_PER_CARD:
			return _take_number_only(words, false)
		Verb.ENERGY, Verb.MAX_ENERGY:
			return _take_number_only(words, true)
		Verb.OPEN_DECKS:
			return "" if words.is_empty() else "open_decks takes nothing after it"
		Verb.DESTROY_COMBO:
			var ok := words.size() == 2 and words[0] == "combo" and words[1] == "random"
			return "" if ok else "write it as: destroy combo random"
	# discard / give / jumble / cost
	if words.is_empty() or not words[0] in ["random", "choose", "all"]:
		if verb != Verb.COST_CHANGE:
			return "needs random N, choose N or all (e.g. %s random 2)" % name
		return _parse_cost_rule(words)
	pick = {"random": Pick.RANDOM, "choose": Pick.CHOOSE, "all": Pick.ALL}[words.pop_front()]
	if pick != Pick.ALL:
		if words.is_empty() or not words[0].is_valid_int() or int(words[0]) < 1:
			return "needs how many cards after random/choose (e.g. %s random 2)" % name
		count = int(words.pop_front())
	if verb == Verb.COST_CHANGE:
		if words.is_empty() or not (words[-1].begins_with("+") or words[-1].begins_with("-")) \
				or not words[-1].is_valid_int():
			return "needs a signed change at the end (e.g. cost random 2 -1)"
		amount = int(words.pop_back())
	return _parse_filters(words)

func _take_number_only(words: Array[String], signed: bool) -> String:
	if words.size() != 1 or not words[0].is_valid_int():
		return "needs one number (e.g. %s %s2)" % [source.split(" ")[0], "+" if signed else ""]
	count = int(words[0])
	if not signed and count < 1:
		return "needs a number of 1 or more"
	return ""

## `cost FILTER... V`: a standing rule, so it needs a filter and a plain value.
func _parse_cost_rule(words: Array[String]) -> String:
	verb = Verb.COST_RULE
	if words.size() < 2 or not words[-1].is_valid_int() \
			or words[-1].begins_with("+") or words[-1].begins_with("-"):
		return "write a cost rule as: cost FILTER VALUE (e.g. cost rank=7 0), " \
			+ "or change cards with: cost random 2 -1"
	amount = int(words.pop_back())
	return _parse_filters(words)

func _parse_filters(words: Array[String]) -> String:
	for w in words:
		if w == "joker":
			filter_joker = 1
		elif w == "natural":
			filter_joker = -1
		elif w.begins_with("rank="):
			var v := w.trim_prefix("rank=")
			filter_rank = RANK_WORDS.get(v, int(v) if v.is_valid_int() else 0)
			if filter_rank < 1 or filter_rank > 13:
				return "rank must be 1-13 or A/J/Q/K, got '%s'" % v
		elif w.begins_with("suit="):
			filter_suit = w.trim_prefix("suit=")
			if not filter_suit in Deck.SUITS:
				return "suit must be one of %s, got '%s'" % [", ".join(Deck.SUITS), filter_suit]
		else:
			return "unknown word '%s' (filters: rank=7, suit=hearts, joker, natural)" % w
	return ""
