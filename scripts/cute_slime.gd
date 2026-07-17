class_name CuteSlime
extends Enemy

## The first designed enemy. She plays at full strength but is oblivious (keeps
## overlooking the plays that read the table) and quick (dumps cards as soon as
## she can). Her mechanic is the slime.
##
## At combat start she coats a random half of the hearts, a random half of the
## diamonds, and every joker in slime, giving them the Sticky effect. Slimed
## cards only stick to each other (see CardSet.sticky_cluster): a run of slimed
## cards on the table is one lump the player can't pick a single card out of —
## dragging one drags them all. The Cute Slime herself is immune (ignores_sticky
## on her PlayerState), so she slides her slime around freely.
##
## Slime strategy: once she has spent her ordinary plays for the turn, she uses
## that free movement to ooze a slimed card next to an unguarded joker, sealing
## it inside a slime cluster so the player can no longer lift the joker on its
## own. She only makes a move that genuinely puts a slimed card beside a joker,
## and never one that would leave another joker exposed, so the guarding only
## grows — no shuffling in circles.

func _init() -> void:
	display_name = "The Cute Slime"
	strength = 1.0     # strongest difficulty (for now every enemy is)
	style = 0.0        # quick
	attention = 0.0    # oblivious

## Slime a random half of the hearts, a random half of the diamonds, and all of
## the jokers, wherever they sit right after the deal (the stock and every
## player's hand). The random halves ride on the deck's own RNG, so a seeded
## game slimes the same cards every replay. Her own seat is marked immune so she
## moves slimed cards freely.
func on_combat_start(gm: GameManager) -> void:
	var hearts: Array[Card] = []
	var diamonds: Array[Card] = []
	var pool: Array[Card] = gm.deck.cards.duplicate()
	for p in gm.players:
		pool.append_array(p.hand)
		if p.is_opponent:
			p.ignores_sticky = true
	for c in pool:
		if c.is_joker:
			_slime(c)
		elif c.suit == "hearts":
			hearts.append(c)
		elif c.suit == "diamonds":
			diamonds.append(c)
	_slime_half(gm.deck.rng, hearts)
	_slime_half(gm.deck.rng, diamonds)

## Shuffle a suit's cards with the given RNG and slime the first half of them.
func _slime_half(rng: RandomNumberGenerator, pile: Array[Card]) -> void:
	for i in range(pile.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := pile[i]
		pile[i] = pile[j]
		pile[j] = tmp
	for i in pile.size() / 2:
		_slime(pile[i])

func _slime(card: Card) -> void:
	if not card.has_effect(Card.Effect.STICKY):
		card.effects.append(Card.Effect.STICKY)

# --- Slime strategy ---------------------------------------------------------

## Find the best "guard a joker" move: relocate one slimed table card so it ends
## up beside a joker that has no slimed neighbour yet, raising the number of
## guarded jokers on the table. Returns {} when no move helps. Because it only
## ever moves on a strict increase in guarded jokers (a bounded count), it makes
## finitely many moves a turn and never loops.
func plan_strategy_move(gm: GameManager) -> Dictionary:
	if not gm.current_player_is_open():
		return {}
	var melds := gm.board.melds
	var base := _guarded_total(melds)
	var best: Dictionary = {}
	var best_score := base
	for i in melds.size():
		var m1: CardSet = melds[i]
		for c in m1.cards:
			# Only a slimed, non-joker card is worth relocating as a bodyguard;
			# the jokers are what we protect, not what we shuffle around.
			if c.is_joker or not c.is_sticky():
				continue
			var rest: Array[Card] = m1.cards.duplicate()
			rest.erase(c)
			if not (rest.is_empty() or Rules.is_valid_meld(rest)):
				continue
			for j in melds.size():
				if j == i:
					continue
				var m2: CardSet = melds[j]
				var grown: Array[Card] = m2.cards.duplicate()
				grown.append(c)
				if not Rules.is_valid_meld(grown):
					continue
				var score := _guarded_after(melds, i, j, rest, grown)
				if score > best_score:
					best_score = score
					best = {"cards": [c], "dest": m2, "borrowed": [c], "strategy": true,
						"text": "oozes %s over to seal a joker in slime" % c.label()}
	return best

## Guarded jokers across the whole table.
func _guarded_total(melds: Array[CardSet]) -> int:
	var total := 0
	for m in melds:
		total += _guarded_jokers(m.cards)
	return total

## Guarded jokers across the table after moving one card: meld i loses it
## (becomes `rest`) and meld j gains it (becomes `grown`).
func _guarded_after(melds: Array[CardSet], i: int, j: int,
		rest: Array[Card], grown: Array[Card]) -> int:
	var total := 0
	for k in melds.size():
		var cards := melds[k].cards
		if k == i:
			cards = rest
		elif k == j:
			cards = grown
		total += _guarded_jokers(cards)
	return total

## How many jokers in this group sit next to a slimed card in display order —
## i.e. are wrapped in a slime cluster the player can't pick them out of.
func _guarded_jokers(cards: Array[Card]) -> int:
	var order := Rules.display_order(cards)
	var guarded := 0
	for i in order.size():
		if not order[i].is_joker:
			continue
		var left := i > 0 and order[i - 1].is_sticky()
		var right := i < order.size() - 1 and order[i + 1].is_sticky()
		if left or right:
			guarded += 1
	return guarded
