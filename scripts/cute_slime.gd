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
## that free movement to ooze slimed cards together into clusters the player
## can't pick apart, weighting each locked card by how badly she wants it kept
## away — jokers first, then aces, then faces, then anything. She makes several
## such moves a turn (up to MAX_GUARDS_PER_TURN), always the highest-value one,
## and only ever on a strict increase in that lock score, so the slime only ever
## thickens — no shuffling in circles.

## How many guarding moves she'll make in a single turn. She consolidates
## aggressively, but a cap keeps a turn watchable instead of oozing the whole
## table around at once.
const MAX_GUARDS_PER_TURN := 4

var _guards_left := MAX_GUARDS_PER_TURN

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

## Fresh guarding budget at the start of each of her turns.
func on_turn_begin(_gm: GameManager) -> void:
	_guards_left = MAX_GUARDS_PER_TURN

## Her best consolidating move: relocate one slimed card so that more of her
## slime — weighted by how badly she wants each locked card kept from the player
## — ends up stuck together in clusters the player can't pick a single card out
## of. She prizes jokers most, then aces, then faces, then anything, and takes
## the move that gains the most. Returns {} when no move improves her grip (or
## the turn's guarding budget is spent). She only ever moves on a strict
## increase in that bounded, importance-weighted lock score, so she makes
## finitely many moves a turn and never shuffles in circles.
func plan_strategy_move(gm: GameManager) -> Dictionary:
	if _guards_left <= 0 or not gm.current_player_is_open():
		return {}
	var melds := gm.board.melds
	# The lock score each group contributes right now, so a candidate only has
	# to re-score the two groups it changes.
	var scores: Array[int] = []
	for m in melds:
		scores.append(_meld_lock_score(m.cards))
	var best: Dictionary = {}
	var best_gain := 0
	for i in melds.size():
		var m1: CardSet = melds[i]
		for c in m1.cards:
			# Jokers are what she guards, not what she shuffles; she oozes the
			# other slimed cards (hearts, diamonds) around them as bodyguards.
			if c.is_joker or not c.is_sticky():
				continue
			var rest: Array[Card] = m1.cards.duplicate()
			rest.erase(c)
			if not (rest.is_empty() or Rules.is_valid_meld(rest)):
				continue
			var rest_score := _meld_lock_score(rest)
			for j in melds.size():
				if j == i:
					continue
				var m2: CardSet = melds[j]
				var grown: Array[Card] = m2.cards.duplicate()
				grown.append(c)
				if not Rules.is_valid_meld(grown):
					continue
				var gain := rest_score + _meld_lock_score(grown) - scores[i] - scores[j]
				if gain > best_gain:
					best_gain = gain
					var moved: Array[Card] = [c]
					best = {"cards": moved, "dest": m2, "borrowed": moved, "strategy": true,
						"text": _guard_text(c, _has_joker(grown))}
	if not best.is_empty():
		_guards_left -= 1
	return best

func _guard_text(c: Card, seals_joker: bool) -> String:
	if seals_joker:
		return "oozes %s over to seal a joker in slime" % c.label()
	return "oozes %s over to thicken her slime" % c.label()

## The total importance of the locked slimed cards in one group: a slimed card
## is locked when a slimed card sits next to it in display order (so the player
## can't peel it off on its own). Bigger clusters lock more cards, so they score
## higher, and jokers/aces/faces are worth more than plain cards.
func _meld_lock_score(cards: Array[Card]) -> int:
	var order := Rules.display_order(cards)
	var score := 0
	for i in order.size():
		if not order[i].is_sticky():
			continue
		var stuck := (i > 0 and order[i - 1].is_sticky()) \
			or (i < order.size() - 1 and order[i + 1].is_sticky())
		if stuck:
			score += _importance(order[i])
	return score

## How badly she wants a card kept away from the player: jokers most of all,
## then aces, then faces, then any other card.
func _importance(c: Card) -> int:
	if c.is_joker:
		return 100
	if c.rank == 1:
		return 8
	if c.rank >= 11:
		return 4
	return 1

func _has_joker(cards: Array[Card]) -> bool:
	for c in cards:
		if c.is_joker:
			return true
	return false
