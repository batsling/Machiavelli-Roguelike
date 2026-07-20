class_name Board
extends RefCounted

## The shared table: an unordered collection of melds. Supports snapshot and
## restore so a turn's rearrangement can be rolled back wholesale if the player
## draws instead, or tries to end the turn with an invalid table.
##
## Layout groundwork: a card may sit in MORE than one meld at once — an
## intersection, where a vertical group crosses a horizontal one at a shared
## card (see GameManager.stage_cross_meld). Everything here treats that as
## first-class: melds_of lists every group holding a card, remove_card pulls a
## card out of all of them (leaving the table means leaving every group it was
## part of), and snapshots keep each meld's orientation and shape cells so an
## undo restores the layout, not just the membership.

var melds: Array[CardSet] = []

func all_valid() -> bool:
	for m in melds:
		if not m.is_valid():
			return false
	return true

## Every card on the table, each listed once — a card shared by two crossing
## melds still counts as one card.
func all_cards() -> Array[Card]:
	var seen := {}
	var out: Array[Card] = []
	for m in melds:
		for c in m.cards:
			if not seen.has(c):
				seen[c] = true
				out.append(c)
	return out

## The meld currently holding this card, or null if it is not on the table.
## At an intersection this is the group the card joined first (its "host");
## melds_of lists them all.
func meld_of(card: Card) -> CardSet:
	for m in melds:
		if m.cards.has(card):
			return m
	return null

## Every meld holding this card — more than one exactly at an intersection.
func melds_of(card: Card) -> Array[CardSet]:
	var out: Array[CardSet] = []
	for m in melds:
		if m.cards.has(card):
			out.append(m)
	return out

## Every card currently shared by two or more melds, as
## {"card": Card, "melds": Array[CardSet]} entries.
func intersections() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in all_cards():
		var holders := melds_of(c)
		if holders.size() > 1:
			out.append({"card": c, "melds": holders})
	return out

## Take a card off the table: it leaves EVERY meld holding it (both groups of
## an intersection lose their crossing card together).
func remove_card(card: Card) -> bool:
	var removed := false
	for m in melds:
		if m.cards.has(card):
			m.remove_card(card)
			removed = true
	return removed

func prune_empty() -> void:
	for i in range(melds.size() - 1, -1, -1):
		if melds[i].is_empty():
			melds.remove_at(i)

## Snapshot is an Array with one Dictionary per meld (card refs shared, so a
## card sitting in two melds is restored into both) carrying the cards plus
## the layout groundwork: orientation and shape cells.
func snapshot() -> Array:
	var snap: Array = []
	for m in melds:
		snap.append({
			"cards": m.cards.duplicate(),
			"orientation": m.orientation,
			"shape": m.shape_cells.duplicate(),
		})
	return snap

func restore(snap: Array) -> void:
	melds.clear()
	for entry: Dictionary in snap:
		var m := CardSet.new()
		for c: Card in entry["cards"]:
			m.cards.append(c)
		m.orientation = entry["orientation"]
		m.shape_cells = (entry["shape"] as Dictionary).duplicate()
		melds.append(m)
