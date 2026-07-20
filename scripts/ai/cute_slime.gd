class_name CuteSlime
extends Enemy

## The first designed enemy. She plays at full strength but is oblivious (keeps
## overlooking the plays that read the table) and quick (dumps cards as soon as
## she can). Her mechanic is the slime.
##
## At combat start she coats every heart, every diamond and every joker in her
## own deck in slime, giving them the Sticky effect. Because the combined stock
## holds one copy of each card per player, only her copy is slimed — of the two
## copies of any heart or diamond in the game, exactly one carries slime, and
## only two of the four jokers (hers) are sticky. Slimed cards only stick to each
## other (see CardSet.sticky_cluster): a run of slimed cards on the table is one
## lump the player can't pick a single card out of — dragging one drags them all.
## The Cute Slime herself is immune (ignores_sticky on her PlayerState), so she
## slides her slime around freely.
##
## Slime strategy: once she has spent her ordinary plays for the turn, she uses
## her free movement to legally combine slimed cards — moving one slimed card
## next to the most valuable slimed card the player could still lift, sealing it
## in slime. Every combine keeps both groups valid and leaves no unmatched card
## behind, and she repeats it as long as it helps (still all within her one
## turn), always taking the move that guards her most versatile cards first —
## jokers, then the flexible 4-8s. She only ever moves on a real improvement, so
## she consolidates her slime, never shuffles in circles. The guard runs even on
## a turn with no ordinary play: she reworks the felt and then draws, keeping the
## rearrangement (GameManager.draw_and_end_turn), so she never wastes the guard.

## Groundwork for her planned ultimate: once her meter fills she will gather
## the slimed cards she can and arrange them into a picture on the felt — a
## heart, a ladybug, a flower — as a shape group (CardSet.set_shape) that any
## card of can be played off in any direction that feasibly works. The heart
## template is laid out here as grid cells, row by row:
##   . X . X .
##   X X X X X
##   X X X X X
##   . X X X .
##   . . X . .
## The ladybug and flower templates land with the ultimate itself.
const ULT_HEART: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(3, 0),
	Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1),
	Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2),
	Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3),
	Vector2i(2, 4),
]

## Build one of her picture groups from a template and the cards to fill it
## (in template order). Needs exactly as many cards as the template has cells;
## returns null when the count doesn't fit.
static func build_shape_meld(template: Array[Vector2i], cards: Array[Card]) -> CardSet:
	if cards.size() != template.size():
		return null
	var cells := {}
	for i in template.size():
		cells[cards[i]] = template[i]
	var meld := CardSet.new()
	meld.set_shape(cells)
	return meld

func _init() -> void:
	display_name = "The Cute Slime"
	strength = 1.0     # strongest difficulty (for now every enemy is)
	style = 0.0        # quick
	attention = 0.0    # oblivious

func mechanic_intro() -> String:
	return "[b]%s[/b] slimes every heart, diamond and joker in her own deck " \
		% display_name \
		+ "(green splotch) — one copy of each, so only her half is sticky. " \
		+ "Slimed cards stick to each other, so a run of them is one lump — " \
		+ "dragging one drags them all. She oozes freely and combines her slime " \
		+ "to guard her most valuable cards (jokers, then the versatile 4-8s) " \
		+ "out of your reach."

## Slime every heart, diamond and joker that came from her own deck, wherever
## they sit right after the deal (the stock and every player's hand). Only her
## copies carry slime — the player's matching cards stay clean — so of the two
## copies of any heart or diamond exactly one is sticky, and only her two jokers.
## Deterministic (no RNG), so a seeded game slimes the same cards every replay.
## Her own seat is marked immune so she moves slimed cards freely.
func on_combat_start(gm: GameManager) -> void:
	var own := own_deck_id(gm)
	for p in gm.players:
		if p.is_opponent:
			p.ignores_sticky = true
	for c in all_dealt_cards(gm):
		if c.deck_owner != own:
			continue
		if c.is_joker or c.suit == "hearts" or c.suit == "diamonds":
			_slime(c)

func _slime(card: Card) -> void:
	if not card.has_effect(Card.Effect.STICKY):
		card.effects.append(Card.Effect.STICKY)

# --- Slime strategy ---------------------------------------------------------

## Her best guarding move right now: relocate one slimed card so it locks the
## most valuable slimed card the player could still lift, weighting each card by
## how badly she wants it kept away — jokers most, then the versatile 4-8s, then
## anything. The move keeps both groups valid and leaves no unmatched card, and
## she only makes it when it strictly improves her grip; otherwise {}. The turn
## loop calls this repeatedly, so she guards as much as legally helps in a turn.
func plan_strategy_move(gm: GameManager) -> Dictionary:
	if not gm.current_player_is_open():
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
	return best

func _guard_text(c: Card, seals_joker: bool) -> String:
	if seals_joker:
		return "oozes %s over to seal a joker in slime" % c.label()
	return "oozes %s over to guard a card in slime" % c.label()

## The total importance of the locked slimed cards in one group: a slimed card
## is locked when a slimed card sits next to it in display order, so the player
## can't peel it off on its own. Jokers and the versatile 4-8s are worth more
## than other cards (see _importance).
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
## then the versatile middle ranks 4-8 (the most flexible cards in play), then
## any other card. Aces and faces are edge ranks, so they rate no higher than
## the rest.
func _importance(c: Card) -> int:
	if c.is_joker:
		return 100
	if c.rank >= 4 and c.rank <= 8:
		return 8
	return 1

func _has_joker(cards: Array[Card]) -> bool:
	for c in cards:
		if c.is_joker:
			return true
	return false
