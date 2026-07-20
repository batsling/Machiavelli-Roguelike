class_name BoardGrid
extends RefCounted

## Layout groundwork: the grid math for the planned bizarre table shapes.
##
## The vanilla table is a bag of horizontal lines, but the designs coming need
## more of it: vertical groups, a card sitting in a horizontal AND a vertical
## group at once (an intersection, both still extendable), and whole pictures
## of cards (the Cute Slime's planned heart) where any card can be played off
## in any direction that feasibly works — which in turn needs "directly
## horizontal or vertical to each other" to be a real, queryable relation.
##
## This module answers those spatial questions without owning any state: give
## it a Board and it lays every connected patch of melds onto a local grid.
##  - A line meld occupies consecutive cells along its orientation, in display
##    order.
##  - Melds sharing a card (an intersection) are aligned so the shared card
##    occupies a single cell.
##  - A shape meld brings its own cells (CardSet.shape_cells).
## The UI renders each cluster from these cells; future play rules read
## neighbors() to decide what counts as adjacent.

## Group the table into clusters — melds transitively connected by shared
## cards — and lay each onto its own grid. Returns one Dictionary per cluster,
## in board order of each cluster's first meld:
##   "melds":   Array[CardSet] — the cluster's melds, in board order
##   "cells":   {Vector2i: Card} — where every card sits, normalized to (0,0)
##   "meld_at": {Vector2i: CardSet} — the meld that placed each cell (the
##              host meld at a shared cell)
##   "size":    Vector2i — grid extent (max cell + (1,1))
static func clusters(board: Board) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var placed_in := {}  # CardSet -> true once emitted in some cluster
	for seed_meld in board.melds:
		if placed_in.has(seed_meld):
			continue
		var cluster := _lay_out_cluster(board, seed_meld)
		for m: CardSet in cluster["melds"]:
			placed_in[m] = true
		out.append(cluster)
	return out

## The cluster containing this card, or {} if it is not on the table.
static func cluster_of(board: Board, card: Card) -> Dictionary:
	for cluster in clusters(board):
		for m: CardSet in cluster["melds"]:
			if m.cards.has(card):
				return cluster
	return {}

## The cards sitting directly beside `card` on its cluster's grid — one cell
## up, down, left or right. This is the future "adjacent cards are a legal
## play off each other" relation.
static func neighbors(board: Board, card: Card) -> Array[Card]:
	var out: Array[Card] = []
	var cluster := cluster_of(board, card)
	if cluster.is_empty():
		return out
	var cells: Dictionary = cluster["cells"]
	var mine := Vector2i.ZERO
	var found := false
	for cell: Vector2i in cells:
		if cells[cell] == card:
			mine = cell
			found = true
			break
	if not found:
		return out
	for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var n: Card = cells.get(mine + step)
		if n != null:
			out.append(n)
	return out

## Lay one connected patch of melds onto a grid, breadth-first from `seed`:
## the seed goes down at the origin, and every meld sharing a card with an
## already-placed meld is aligned so the shared card lands on its placed cell.
static func _lay_out_cluster(board: Board, seed_meld: CardSet) -> Dictionary:
	var melds: Array[CardSet] = []
	var cells := {}    # Vector2i -> Card
	var meld_at := {}  # Vector2i -> CardSet (the meld that placed the cell)
	var cell_of := {}  # Card -> Vector2i, for aligning newcomers
	_place_meld(seed_meld, Vector2i.ZERO, melds, cells, meld_at, cell_of)
	# Keep absorbing melds that touch the placed patch until none are left.
	var grew := true
	while grew:
		grew = false
		for m in board.melds:
			if melds.has(m):
				continue
			var shared := _shared_placed_card(m, cell_of)
			if shared == null:
				continue
			var anchor := _anchor_for(m, shared, cell_of[shared])
			_place_meld(m, anchor, melds, cells, meld_at, cell_of)
			grew = true
	# Normalize so the top-left occupied cell is (0,0).
	var origin := Vector2i(2147483647, 2147483647)
	for cell: Vector2i in cells:
		origin.x = mini(origin.x, cell.x)
		origin.y = mini(origin.y, cell.y)
	var norm_cells := {}
	var norm_meld_at := {}
	var extent := Vector2i.ZERO
	for cell: Vector2i in cells:
		var moved: Vector2i = cell - origin
		norm_cells[moved] = cells[cell]
		norm_meld_at[moved] = meld_at[cell]
		extent.x = maxi(extent.x, moved.x + 1)
		extent.y = maxi(extent.y, moved.y + 1)
	# Emit the melds in board order, so Sort/Randomize keep steering the felt.
	var ordered: Array[CardSet] = []
	for m in board.melds:
		if melds.has(m):
			ordered.append(m)
	return {"melds": ordered, "cells": norm_cells, "meld_at": norm_meld_at, "size": extent}

## A card of `meld` that already has a cell, or null.
static func _shared_placed_card(meld: CardSet, cell_of: Dictionary) -> Card:
	for c in meld.cards:
		if cell_of.has(c):
			return c
	return null

## Where `meld` must anchor (its first cell) so that `shared` lands on
## `shared_cell`. A line meld anchors at display index 0; a shape meld anchors
## at its own local (0,0)-relative offset for that card.
static func _anchor_for(meld: CardSet, shared: Card, shared_cell: Vector2i) -> Vector2i:
	if meld.is_shape():
		return shared_cell - meld.cell_of(shared)
	var step := _step(meld)
	var idx := Rules.display_order(meld.cards).find(shared)
	return shared_cell - step * idx

static func _step(meld: CardSet) -> Vector2i:
	return Vector2i.DOWN if meld.orientation == CardSet.Orientation.VERTICAL \
		else Vector2i.RIGHT

## Write one meld's cards into the cluster maps. Cells already claimed by an
## earlier meld are left as they are (the shared card of an intersection is
## claimed by its host), so meld_at answers "whose panel is this" one way.
static func _place_meld(meld: CardSet, anchor: Vector2i, melds: Array[CardSet],
		cells: Dictionary, meld_at: Dictionary, cell_of: Dictionary) -> void:
	melds.append(meld)
	if meld.is_shape():
		for c: Card in meld.shape_cells:
			var cell: Vector2i = anchor + meld.shape_cells[c]
			_claim(cell, c, meld, cells, meld_at, cell_of)
		return
	var step := _step(meld)
	var ordered := Rules.display_order(meld.cards)
	for i in ordered.size():
		_claim(anchor + step * i, ordered[i], meld, cells, meld_at, cell_of)

static func _claim(cell: Vector2i, c: Card, meld: CardSet,
		cells: Dictionary, meld_at: Dictionary, cell_of: Dictionary) -> void:
	if not cells.has(cell):
		cells[cell] = c
		meld_at[cell] = meld
	if not cell_of.has(c):
		cell_of[c] = cell
