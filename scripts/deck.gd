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

func is_empty() -> bool:
	return cards.is_empty()

func size() -> int:
	return cards.size()
