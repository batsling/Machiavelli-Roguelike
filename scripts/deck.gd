class_name Deck
extends RefCounted

## The stock: two full 52-card decks (104 cards), plus 4 jokers when enabled.
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

func build_double_deck(include_jokers := false) -> void:
	cards.clear()
	for _copy in 2:
		for suit in SUITS:
			for rank in range(1, 14):
				var c := Card.new()
				c.suit = suit
				c.rank = rank
				cards.append(c)
	if include_jokers:
		for _i in JOKER_COUNT:
			var j := Card.new()
			j.suit = "joker"
			j.rank = 0
			j.is_joker = true
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
