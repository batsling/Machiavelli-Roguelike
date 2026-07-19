class_name CardSet
extends Resource

## A "meld" on the table — a group of cards placed together (per real-world
## Machiavelli rules: a set of one rank, or a run of one suit). Membership is
## tracked here so the roguelike effects (Sticky, Bomb, Trigger) have a
## concrete place to hook into later; the vanilla engine only uses is_valid().

@export var cards: Array[Card] = []
# id of a board tile effect applied to this set's space, if any
@export var board_tile_effect: String = ""

func is_valid() -> bool:
	return Rules.is_valid_meld(cards)

func size() -> int:
	return cards.size()

func is_empty() -> bool:
	return cards.is_empty()

func add_card(card: Card, index: int = -1) -> void:
	if index < 0 or index > cards.size():
		cards.append(card)
	else:
		cards.insert(index, card)
	_resolve_triggers(card)

func remove_card(card: Card) -> void:
	cards.erase(card)

func _resolve_triggers(played_card: Card) -> void:
	# OPEN QUESTION: resolution order when a set has more than one TRIGGER card.
	# Current stub: resolve in board-position order (left to right).
	for c in cards:
		if c == played_card:
			continue
		if c.has_effect(Card.Effect.TRIGGER):
			_fire_trigger(c, played_card)

func _fire_trigger(trigger_card: Card, played_card: Card) -> void:
	# TODO: hook into damage/heal system once that exists.
	print("Trigger fired: %s reacting to %s" % [trigger_card.label(), played_card.label()])

## The cluster of cards that must move together with start_card because of the
## Sticky (slime) effect. Slimed cards only stick to each other: two neighbours
## are bound only when BOTH are slimed. The cluster is the maximal run of
## consecutive slimed cards containing start_card, so a plain card (or a slimed
## card with no slimed neighbour) is always its own singleton. Adjacency is read
## from the meld's display order — what the player actually sees on the felt —
## so the cards it drags are the cards sitting next to it, and the cluster is
## returned in that left-to-right order.
func sticky_cluster(start_card: Card) -> Array[Card]:
	var cluster: Array[Card] = []
	if not cards.has(start_card):
		return cluster
	if not start_card.is_sticky():
		cluster.append(start_card)
		return cluster
	var order := Rules.display_order(cards)
	var idx := order.find(start_card)
	var lo := idx
	var hi := idx
	while lo > 0 and order[lo - 1].is_sticky():
		lo -= 1
	while hi < order.size() - 1 and order[hi + 1].is_sticky():
		hi += 1
	for i in range(lo, hi + 1):
		cluster.append(order[i])
	return cluster
