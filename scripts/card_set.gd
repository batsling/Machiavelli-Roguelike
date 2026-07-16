extends Resource
class_name CardSet

## A "set" on the board — a run of cards placed together (per real-world Machiavelli
## rules: same rank, or a run of a suit). Track membership here so Sticky, Bomb, and
## Trigger effects have a concrete place to hook into.

@export var cards: Array[Card] = []
@export var board_tile_effect: String = ""  # id of a board tile effect applied to this set's space, if any

func add_card(card: Card, index: int = -1) -> void:
	if index < 0 or index > cards.size():
		cards.append(card)
	else:
		cards.insert(index, card)
	_resolve_triggers(card)

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
	print("Trigger fired: %s reacting to %s" % [trigger_card.resource_name, played_card.resource_name])

func sticky_cluster(start_card: Card) -> Array[Card]:
	# Returns the connected cluster of cards bound together by Sticky, starting
	# from start_card. Naive adjacency walk for the prototype — refine once
	# board topology (rows vs. runs) is settled.
	var cluster: Array[Card] = []
	var idx := cards.find(start_card)
	if idx == -1:
		return cluster
	cluster.append(start_card)
	if not start_card.has_effect(Card.Effect.STICKY):
		return cluster
	# Walk left
	var i := idx - 1
	while i >= 0 and cards[i].has_effect(Card.Effect.STICKY):
		cluster.push_front(cards[i])
		i -= 1
	# Walk right
	var j := idx + 1
	while j < cards.size() and cards[j].has_effect(Card.Effect.STICKY):
		cluster.append(cards[j])
		j += 1
	return cluster
