class_name CardSet
extends Resource

## A "meld" on the table — a group of cards placed together (per real-world
## Machiavelli rules: a set of one rank, or a run of one suit). Membership is
## tracked here so the roguelike effects (Sticky, Bomb, Trigger) have a
## concrete place to hook into later; the vanilla engine only uses is_valid().
##
## Beyond the vanilla line group, this carries the groundwork for the planned
## bizarre table layouts:
##  - `orientation`: a line group can lie horizontally or vertically on the
##    felt. Validity never depends on it, but direction is what lets a
##    vertical group cross a horizontal one at a shared card (see
##    Board.melds_of / GameManager.stage_cross_meld) with both still valid and
##    extendable.
##  - `shape_cells`: a "picture" group (e.g. the Cute Slime's planned ultimate
##    arranging her slimed cards into a heart) places its cards on a small
##    local grid instead of in a line. Any card of the picture is meant to be
##    played off of in any direction that feasibly works — those play rules
##    arrive with the mechanic; the grid helpers here (cell_of / card_at /
##    line_through) are what they will read. Cards directly beside each other
##    on the grid are the future "adjacent = playable" relation (BoardGrid).

## How a line group lies on the felt (ignored by shape groups, which carry
## their own cells).
enum Orientation { HORIZONTAL, VERTICAL }

## Sentinel board_pos: "not placed yet". The table view auto-places any group
## carrying it (into the next free spot), so a fresh group finds a home without
## the engine ever caring where groups sit.
const UNPLACED := Vector2(-1, -1)

@export var cards: Array[Card] = []
# id of a board tile effect applied to this set's space, if any
@export var board_tile_effect: String = ""
@export var orientation := Orientation.HORIZONTAL
## Where this group's panel sits on the freeform felt — the canvas-local
## top-left of its panel, or UNPLACED until the table view places it. Purely
## visual (like orientation): the player drags groups around, Sort/Randomize
## rewrite it, and it is snapshotted so an undo restores the layout, not just
## the membership. A crossing/picture cluster shares one position across its
## melds.
@export var board_pos := UNPLACED
## Card -> Vector2i local grid cell. Empty for ordinary line groups; non-empty
## makes this a shape (picture) group, valid when its cells form one
## edge-connected patch covering exactly its cards.
@export var shape_cells := {}
## Attached extension line (a Scrabble-style play off a picture): the picture
## card the line reads from — it stays in its own group — and the outward
## direction. cards[i] sits at the anchor's cell + attach_step * (i + 1), so
## the array order IS the spatial order. Valid when the anchor plus the line
## reads as a legal grid line (Rules.is_valid_grid_line), or is still a
## growable pair while one card long (Rules.could_pair); a vertical straight
## must also read with the lower rank on top (Rules.line_direction_ok). Line
## cards stay loose: any of them can be picked back up or moved on its own —
## only the picture itself is sealed — with the cards left behind sliding in
## toward the anchor.
var attach_anchor: Card = null
@export var attach_step := Vector2i.ZERO

## True once this group has been given a spot on the freeform felt.
func is_placed() -> bool:
	return board_pos != UNPLACED

func is_valid() -> bool:
	if is_shape():
		return _shape_is_valid()
	if is_attached():
		return _attached_line_valid()
	return Rules.is_valid_meld(cards)

func is_attached() -> bool:
	return attach_anchor != null

func _attached_line_valid() -> bool:
	if cards.is_empty():
		return false
	var line: Array[Card] = [attach_anchor]
	line.append_array(cards)
	# Vertical straights keep the lower rank on top (Rules.line_direction_ok).
	if not Rules.line_direction_ok(line, attach_step):
		return false
	if line.size() == 2:
		return Rules.could_pair(line[0], line[1])
	return Rules.is_valid_grid_line(line)

# --- Shape (picture) groups — groundwork -------------------------------------

func is_shape() -> bool:
	return not shape_cells.is_empty()

## Turn this group into a shape: `cells` maps every card to its local grid
## cell. Replaces the membership so cards and cells always agree.
func set_shape(cells: Dictionary) -> void:
	shape_cells = cells.duplicate()
	cards.clear()
	for c: Card in cells:
		cards.append(c)

## A shape group is valid by construction — the mechanic that builds it is the
## legality gate — but it must be well-formed: one cell per card, every card
## placed, no two cards sharing a cell, and the whole picture edge-connected.
func _shape_is_valid() -> bool:
	if cards.size() < Rules.MIN_MELD_SIZE or shape_cells.size() != cards.size():
		return false
	var used := {}
	for c in cards:
		if not shape_cells.has(c):
			return false
		var cell: Vector2i = shape_cells[c]
		if used.has(cell):
			return false
		used[cell] = c
	# Flood-fill from any cell; a picture in one piece reaches every cell.
	var seen := {}
	var frontier: Array[Vector2i] = [shape_cells[cards[0]]]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		if seen.has(cell) or not used.has(cell):
			continue
		seen[cell] = true
		for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			frontier.append(cell + step)
	return seen.size() == used.size()

## The cell this card occupies in the shape, or SHAPE_NO_CELL when it has none.
const SHAPE_NO_CELL := Vector2i(-2147483648, -2147483648)

func cell_of(card: Card) -> Vector2i:
	return shape_cells.get(card, SHAPE_NO_CELL)

func card_at(cell: Vector2i) -> Card:
	for c: Card in shape_cells:
		if shape_cells[c] == cell:
			return c
	return null

## The maximal contiguous straight line of shape cards through `card`, along
## one axis, in cell order. This is what the future "play off any picture card
## in any feasible direction" rule will validate extensions against.
func line_through(card: Card, horizontal: bool) -> Array[Card]:
	var out: Array[Card] = []
	if not shape_cells.has(card):
		return out
	var step := Vector2i.RIGHT if horizontal else Vector2i.DOWN
	var start: Vector2i = shape_cells[card]
	while card_at(start - step) != null:
		start -= step
	var cell := start
	while true:
		var c := card_at(cell)
		if c == null:
			break
		out.append(c)
		cell += step
	return out

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
	shape_cells.erase(card)

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
## returned in that left-to-right order. In a shape (picture) group adjacency
## is the grid instead: slimed cards touching up/down/left/right stick, so a
## picture built entirely of slimed cards (the slime's ultimate) moves as one
## lump — which nothing else on the table can legally absorb, sealing it.
func sticky_cluster(start_card: Card) -> Array[Card]:
	var cluster: Array[Card] = []
	if not cards.has(start_card):
		return cluster
	if not start_card.is_sticky():
		cluster.append(start_card)
		return cluster
	if is_shape():
		return _shape_sticky_cluster(start_card)
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

## Flood the shape's grid from start_card over slimed cards touching edge to
## edge — the picture-group reading of the sticky bond.
func _shape_sticky_cluster(start_card: Card) -> Array[Card]:
	var cluster: Array[Card] = []
	var frontier: Array[Card] = [start_card]
	var seen := {}
	while not frontier.is_empty():
		var c: Card = frontier.pop_back()
		if seen.has(c):
			continue
		seen[c] = true
		cluster.append(c)
		var cell: Vector2i = shape_cells[c]
		for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n := card_at(cell + step)
			if n != null and n.is_sticky() and not seen.has(n):
				frontier.append(n)
	return cluster
