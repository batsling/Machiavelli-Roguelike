class_name Deck
extends RefCounted

## One player's deck. Every entity at the table — the player and each enemy —
## brings and draws from its own deck; nothing is merged into a shared stock.
## A standard deck is 52 cards (plus 2 jokers when jokers are enabled), each
## tagged with its owner (Card.deck_owner). Uses its own RNG so a whole game is
## reproducible from a single seed.

const SUITS: Array[String] = ["hearts", "diamonds", "clubs", "spades"]
## Jokers in one standard deck when jokers are enabled.
const JOKERS_PER_DECK := 2

var cards: Array[Card] = []
## The face-up discard pile: cards sent out of play from this deck. Out of play
## until the deck runs dry, at which point it is shuffled to become the new
## draw pile (see draw()). A general facility for discard effects.
var discards: Array[Card] = []
var rng := RandomNumberGenerator.new()

func _init(seed_value: int = -1) -> void:
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()

## Build a standard deck for `owner` (a player_id): one card of every rank in
## every suit, plus JOKERS_PER_DECK jokers when include_jokers is on.
func build_standard(owner: int, include_jokers := false) -> void:
	cards.clear()
	for suit in SUITS:
		for rank in range(1, 14):
			var c := Card.new()
			c.suit = suit
			c.rank = rank
			c.deck_owner = owner
			cards.append(c)
	if include_jokers:
		for _i in JOKERS_PER_DECK:
			var j := Card.new()
			j.suit = "joker"
			j.rank = 0
			j.is_joker = true
			j.deck_owner = owner
			cards.append(j)

func shuffle() -> void:
	# Fisher-Yates using our own RNG (Array.shuffle() would use the global one).
	for i in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cards[i]
		cards[i] = cards[j]
		cards[j] = tmp

## Draw the top card. When the deck is empty the discard pile is reshuffled
## into a fresh draw pile first; returns null only when both are empty.
func draw() -> Card:
	if cards.is_empty():
		if discards.is_empty():
			return null
		reshuffle_discards()
	return cards.pop_back()

## Send a card to the face-up discard pile — out of play until the deck is
## exhausted and the pile is reshuffled back in.
func discard(card: Card) -> void:
	discards.append(card)

## Fold the discard pile back into the deck and shuffle it. Called
## automatically by draw() when the deck empties; safe to call directly.
func reshuffle_discards() -> void:
	cards.append_array(discards)
	discards.clear()
	shuffle()

## Remove and return a specific natural card from the deck, or null when no
## copy is left in it. Used to build the optional starting combos.
func take_card(rank: int, suit: String) -> Card:
	for i in cards.size():
		var c := cards[i]
		if not c.is_joker and c.rank == rank and c.suit == suit:
			cards.remove_at(i)
			return c
	return null

## The card the next draw() will return (the top of the deck), or null when the
## deck is empty. Its face is public only when the card is glass; a slimed top
## reveals only its slimed status (a splotch on the back), and anything else is
## still face down. Callers must respect which of these applies.
func peek() -> Card:
	if cards.is_empty():
		return null
	return cards[-1]

## True only when there is truly nothing left to draw — both the deck and the
## discard pile are empty (draw() recycles the discards).
func is_empty() -> bool:
	return cards.is_empty() and discards.is_empty()

## The number of cards left in the draw pile (not counting the discard pile).
func size() -> int:
	return cards.size()
