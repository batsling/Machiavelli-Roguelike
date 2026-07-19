class_name Board
extends RefCounted

## The shared table: an unordered collection of melds. Supports snapshot and
## restore so a turn's rearrangement can be rolled back wholesale if the player
## draws instead, or tries to end the turn with an invalid table.

var melds: Array[CardSet] = []

func all_valid() -> bool:
	for m in melds:
		if not m.is_valid():
			return false
	return true

func all_cards() -> Array[Card]:
	var out: Array[Card] = []
	for m in melds:
		out.append_array(m.cards)
	return out

## The meld currently holding this card, or null if it is not on the table.
func meld_of(card: Card) -> CardSet:
	for m in melds:
		if m.cards.has(card):
			return m
	return null

func remove_card(card: Card) -> bool:
	for m in melds:
		if m.cards.has(card):
			m.cards.erase(card)
			return true
	return false

func prune_empty() -> void:
	for i in range(melds.size() - 1, -1, -1):
		if melds[i].is_empty():
			melds.remove_at(i)

## Snapshot is an Array of Array[Card] (one entry per meld, card refs shared).
func snapshot() -> Array:
	var snap: Array = []
	for m in melds:
		snap.append(m.cards.duplicate())
	return snap

func restore(snap: Array) -> void:
	melds.clear()
	for card_list in snap:
		var m := CardSet.new()
		for c in card_list:
			m.cards.append(c)
		melds.append(m)
