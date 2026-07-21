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
## The face-up discard pile: cards played out of the game (currently only the
## Sadistic Billionaire's Riichi auto-discards). Out of play until the stock
## runs dry, at which point it is shuffled to become the new stock (see draw()).
## A general facility other mechanics can reuse.
var discards: Array[Card] = []
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

## Draw the top card. When the stock is empty the discard pile is reshuffled
## into a fresh stock first (so a game with active discards keeps cycling);
## returns null only when both the stock and the discards are empty.
func draw() -> Card:
	if cards.is_empty():
		if discards.is_empty():
			return null
		reshuffle_discards()
	return cards.pop_back()

## Send a card to the face-up discard pile — out of play until the stock is
## exhausted and the pile is reshuffled back in.
func discard(card: Card) -> void:
	discards.append(card)

## Fold the discard pile back into the stock and shuffle it. Called
## automatically by draw() when the stock empties; safe to call directly.
func reshuffle_discards() -> void:
	cards.append_array(discards)
	discards.clear()
	shuffle()

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
## the stock is empty. Its face is public only when the card is glass; a slimed
## top reveals only its slimed status (a splotch on the back), and anything else
## is still face down. Callers must respect which of these applies.
func peek() -> Card:
	if cards.is_empty():
		return null
	return cards[-1]

## True only when there is truly nothing left to draw — both the stock and the
## discard pile are empty (draw() recycles the discards, so a non-empty pile is
## still drawable). In a game with no discards this equals cards.is_empty(), so
## existing behavior is unchanged.
func is_empty() -> bool:
	return cards.is_empty() and discards.is_empty()

## The number of cards left in the stock proper (not counting the face-up
## discard pile, which is shown separately and only recycled once the stock dries).
func size() -> int:
	return cards.size()
