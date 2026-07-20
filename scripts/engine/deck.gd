class_name Deck
extends RefCounted

## The stock: the players' decks combined into one. Every player brings a single
## 52-card deck (plus 2 jokers each when jokers are enabled); the two are merged
## here into the familiar double deck (104 cards, +4 jokers), so play is
## unchanged — but each card remembers which player's deck it came from
## (Card.deck_owner), which a designed enemy reads to corrupt only its own cards.
## Uses its own RNG so a whole game is reproducible from a single seed.

const SUITS: Array[String] = ["hearts", "diamonds", "clubs", "spades"]
const JOKER_COUNT := 4

var cards: Array[Card] = []
var rng := RandomNumberGenerator.new()

func _init(seed_value: int = -1) -> void:
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()

## Build the combined stock: one single 52-card deck per player (players 0 and 1),
## merged into the double deck. Each card is tagged with its origin deck via
## deck_owner (copy 0 → player 0, copy 1 → player 1), and the 4 jokers split two
## per deck. Card creation order is unchanged, so seeded shuffles are unaffected.
func build_double_deck(include_jokers := false) -> void:
	cards.clear()
	for copy in 2:
		for suit in SUITS:
			for rank in range(1, 14):
				var c := Card.new()
				c.suit = suit
				c.rank = rank
				c.deck_owner = copy
				cards.append(c)
	if include_jokers:
		for i in JOKER_COUNT:
			var j := Card.new()
			j.suit = "joker"
			j.rank = 0
			j.is_joker = true
			j.deck_owner = 0 if i < JOKER_COUNT / 2 else 1
			cards.append(j)

func shuffle() -> void:
	# Fisher-Yates using our own RNG (Array.shuffle() would use the global one).
	for i in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cards[i]
		cards[i] = cards[j]
		cards[j] = tmp

func draw() -> Card:
	if cards.is_empty():
		return null
	return cards.pop_back()

## Remove and return a specific natural card from the stock, or null when no
## copy is left in it. The stock is shuffled, so which copy leaves carries no
## information. Used to build the optional starting combos.
func take_card(rank: int, suit: String) -> Card:
	for i in cards.size():
		var c := cards[i]
		if not c.is_joker and c.rank == rank and c.suit == suit:
			cards.remove_at(i)
			return c
	return null

## The card the next draw() will return (the top of the stock), or null when
## the stock is empty. Callers must only act on it when the card is glass —
## a glass top is public information, anything else is still face down.
func peek() -> Card:
	if cards.is_empty():
		return null
	return cards[-1]

func is_empty() -> bool:
	return cards.is_empty()

func size() -> int:
	return cards.size()
