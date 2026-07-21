class_name TableView
extends RefCounted

## Renders the live table — opponent seats, the felt of meld panels, and your
## hand — into the containers the controller owns. Split out of main_ui so the
## ~300 lines of "turn game state into nodes" live in one place. This is a
## passive view: it reads the controller's state (game, selection, highlights,
## hover filter) and wires each card button back to the controller's handlers,
## but holds no state of its own. The controller drives it by calling
## refresh_seats / refresh_board / refresh_hand from its _refresh().

var _ui: MainUI

func setup(ui: MainUI) -> void:
	_ui = ui

## Seat opponents around the table: players[1] opposite you, players[2] on the
## left, players[3] on the right. Unused seats collapse.
func refresh_seats() -> void:
	var gm := _ui.gm
	# Rebuilding the seats frees the card backs any open hand reveal was tied to,
	# so drop the reveal; re-entering a seat brings it back.
	_ui._hide_opponent_hand()
	_ui.opponent_backs.clear()
	var seats: Array = [_ui.seat_top, _ui.seat_left, _ui.seat_right]
	var seated_players := mini(gm.players.size(), MainUI.MAX_PLAYERS)
	for i in seats.size():
		var seat: VBoxContainer = seats[i]
		_ui._clear_children(seat)
		var player_index := i + 1
		if player_index >= seated_players:
			seat.visible = false
			continue
		seat.visible = true
		var p := gm.players[player_index]
		var chip := _make_player_chip(p, player_index)
		chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		seat.add_child(chip)
		var backs := _make_card_backs(p, player_index, i == 0)
		backs.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		seat.add_child(backs)
		_ui.opponent_backs[p.player_id] = backs
	_ui.stock_label.text = "Stock: %d" % gm.deck.size()
	_ui.round_label.text = "Round %d" % gm.round_number
	_refresh_stock_top()

## Show the top card of the stock beside the count when its status is public: a
## glass top shows its face (everyone sees the next draw), and a slimed top shows
## a back with the splotch (everyone sees the next draw is stuck, but not what it
## is). A plain top stays hidden.
func _refresh_stock_top() -> void:
	_ui._clear_children(_ui.stock_top_slot)
	var top := _ui.gm.deck.peek()
	if top == null:
		return
	if top.is_glass():
		var face := CardRenderer.make_glass_face(top, UITheme.BACK_SIZE_TOP)
		face.tooltip_text = "Top of the stock is glass — everyone can see " \
			+ "the next card drawn."
		_ui.stock_top_slot.add_child(face)
	elif top.is_sticky():
		var back := CardRenderer.make_card_back(UITheme.BACK_SIZE_TOP, top)
		back.tooltip_text = "Top of the stock is slimed — the next card drawn is stuck."
		_ui.stock_top_slot.add_child(back)

func _make_player_chip(p: PlayerState, player_index: int) -> PanelContainer:
	var gm := _ui.gm
	var is_current: bool = p == gm.current_player() and not gm.is_game_over
	var chip := PanelContainer.new()
	var sb := CardRenderer.panel_style(UITheme.COL_CHIP_BG, 8)
	sb.border_color = UITheme.COL_CHIP_ACTIVE if is_current else Color(1, 1, 1, 0.15)
	sb.set_border_width_all(2)
	chip.add_theme_stylebox_override("panel", sb)
	# The name row sits over the ultimate meter (when the meter is enabled), so
	# each opponent's charge reads right under their name.
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	chip.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var lbl := Label.new()
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var marker := "▶ " if is_current else ""
	var opened := "" if p.has_opened else " · not open"
	lbl.text = "%s%s — %d cards%s" % [marker, p.display_name, p.hand.size(), opened]
	if is_current:
		lbl.add_theme_color_override("font_color", UITheme.COL_CHIP_ACTIVE)
	row.add_child(lbl)
	# "Info" button beside the name tag: the opponent's mechanic and AI brain.
	var info_btn := Button.new()
	info_btn.text = "Info"
	info_btn.tooltip_text = "Show this opponent's mechanic and AI"
	info_btn.focus_mode = Control.FOCUS_NONE
	info_btn.add_theme_font_size_override("font_size", 12)
	info_btn.pressed.connect(_ui._on_enemy_info_pressed.bind(player_index))
	row.add_child(info_btn)
	if gm.meter_max > 0:
		var meter := CardRenderer.make_meter_bar(gm.projected_meter(p), gm.meter_max)
		meter.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(meter)
	return chip

## A row (top seat) or column (side seats) of an opponent's cards, seen from
## the back. Glass cards are see-through, so they show their face right in the
## row; a slimed card shows its green splotch on the back; everything else is a
## plain card back. The overlap tightens as the hand grows so the seat never
## exceeds a fixed footprint. When the opponent holds a visibly-statused card (a
## glass card or a slimed one), hovering the row pops an enlarged reveal of the
## same cards, so the player can read them at a bigger size than the crowded seat
## allows.
func _make_card_backs(p: PlayerState, player_index: int, horizontal: bool) -> BoxContainer:
	var hand := p.hand
	var box: BoxContainer
	var back_size: Vector2
	var max_len: float
	if horizontal:
		box = HBoxContainer.new()
		back_size = UITheme.BACK_SIZE_TOP
		max_len = UITheme.BACKS_MAX_LEN_TOP
	else:
		box = VBoxContainer.new()
		back_size = UITheme.BACK_SIZE_SIDE
		max_len = UITheme.BACKS_MAX_LEN_SIDE
	var card_len := back_size.x if horizontal else back_size.y
	if hand.size() > 1:
		var step := minf(card_len * 0.55, (max_len - card_len) / (hand.size() - 1))
		box.add_theme_constant_override("separation", int(step - card_len))
	var reveal := _ui._hand_has_visible_card(hand)
	for c in hand:
		if c.is_glass():
			var face := CardRenderer.make_glass_face(c, back_size)
			face.tooltip_text = "Glass — you can see this card through the back."
			# With the reveal wired to the row, let hover fall through to the row so
			# the enlarged screen stays up while the mouse crosses the cards.
			if reveal:
				face.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(face)
			# Registered so enemy-move animations start from the visible card.
			_ui.card_nodes[c] = face
		else:
			var back := CardRenderer.make_card_back(back_size, c)
			if reveal:
				back.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(back)
	if reveal:
		# The cards fall through (set IGNORE above), so the row itself catches the
		# hover across its whole footprint and drives the enlarged reveal.
		box.mouse_filter = Control.MOUSE_FILTER_STOP
		box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		box.tooltip_text = "Hover to see %s's hand enlarged." % p.display_name
		box.mouse_entered.connect(_ui._show_opponent_hand.bind(player_index))
		box.mouse_exited.connect(_ui._hide_opponent_hand)
	return box

## The felt is a freeform canvas: one draggable panel per cluster (see
## BoardGrid), each sitting wherever its group was placed. A lone line group
## keeps the plain panel — laid flat or upright by its orientation — while
## crossing groups (sharing a card) and shape (picture) groups render on a grid,
## empty cells and all. A group with no spot yet (freshly laid, or cleared by
## Sort/Randomize) is auto-placed into the next free patch of felt, so mixed
## vertical and horizontal groups nestle together instead of ruling off rows.
func refresh_board() -> void:
	var gm := _ui.gm
	_ui._clear_children(_ui.board_flow)
	# Rects already spoken for on the felt, so auto-placement never overlaps.
	var placed: Array[Rect2] = []
	var width := _canvas_width()
	if gm.board.melds.is_empty():
		var empty := Label.new()
		empty.text = "The table is empty — drag cards here to lay down the first group."
		empty.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
		empty.position = Vector2(UITheme.BOARD_PAD, UITheme.BOARD_PAD)
		empty.size = empty.get_combined_minimum_size()
		_ui.board_flow.add_child(empty)
	for cluster in BoardGrid.clusters(gm.board):
		var melds: Array[CardSet] = cluster["melds"]
		var panel: Control
		if melds.size() == 1 and not melds[0].is_shape():
			panel = _make_meld_panel(melds[0])
		else:
			panel = _make_cluster_panel(cluster)
		_ui.board_flow.add_child(panel)
		_place_panel(panel, melds, placed, width)
	# The "+ New group" click target only appears while cards are selected;
	# drags can always land on empty felt instead. It (and the hover hint) tuck
	# into a free patch of felt like any group, but keep no lasting spot.
	if not _ui.selected.is_empty() and _ui._is_human_turn():
		var zone := _make_new_group_zone()
		_ui.board_flow.add_child(zone)
		_place_panel(zone, [], placed, width)
	# The hover hint's "forms a new group" cue: shown only when nothing is
	# selected (so it never sits beside the interactive New group zone).
	elif _ui.hint_new_group and _ui._is_human_turn():
		var hint := _make_new_group_hint()
		_ui.board_flow.add_child(hint)
		_place_panel(hint, [], placed, width)
	_size_canvas(placed)

## Put one group's panel on the felt: at the spot its group remembers, or — for
## an unplaced group — the next free patch, which is then stored on every meld
## of the group so a crossing/picture cluster keeps one shared spot. A
## remembered spot the panel has outgrown (a lay-off widened the group onto a
## neighbour, or past the felt's right edge) is given up and the group is
## re-placed, so every group always sits whole and visible. Transient panels
## (the New group zone/hint) pass no melds and store nothing.
func _place_panel(panel: Control, melds: Array[CardSet], placed: Array[Rect2],
		width: float) -> void:
	var size := panel.get_combined_minimum_size()
	panel.size = size
	var anchor: CardSet = melds[0] if not melds.is_empty() else null
	var pos: Vector2
	if anchor != null and anchor.is_placed() \
			and not _needs_replacing(Rect2(anchor.board_pos, size), placed, width):
		pos = anchor.board_pos
	else:
		pos = _free_spot(size, placed, width)
		for m in melds:
			m.board_pos = pos
	panel.position = pos
	placed.append(Rect2(pos, size))

## True when a group can no longer keep its remembered spot: its panel now
## overlaps one already on the felt, or it spills past the right edge (where
## clipping would hide cards). A panel wider than the felt itself is left
## where it is — no spot could fit it anyway.
func _needs_replacing(rect: Rect2, placed: Array[Rect2], width: float) -> bool:
	if _overlaps_any(rect, placed):
		return true
	return rect.size.x <= width and rect.position.x + rect.size.x > width

## The next open spot for a panel of `size`: the topmost-then-leftmost candidate
## corner (the felt's top-left, plus the right and bottom edges every placed
## panel opens up) that neither overlaps a placed panel nor overflows `width`.
## Placing every group this way packs them into tidy shelves that let a tall
## vertical group and a short horizontal one share a row with no wasted gap.
func _free_spot(size: Vector2, placed: Array[Rect2], width: float) -> Vector2:
	var pad := float(UITheme.BOARD_PAD)
	var cand_x: Array[float] = [pad]
	var cand_y: Array[float] = [pad]
	for r in placed:
		cand_x.append(r.position.x + r.size.x + pad)
		cand_y.append(r.position.y + r.size.y + pad)
	var best := Vector2.INF
	for y in cand_y:
		for x in cand_x:
			if x + size.x > width and x > pad:
				continue  # would spill past the right edge of the felt
			if _overlaps_any(Rect2(Vector2(x, y), size), placed):
				continue
			if y < best.y or (y == best.y and x < best.x):
				best = Vector2(x, y)
	if best == Vector2.INF:
		# Nothing fit within the width — drop it below everything on the felt.
		var bottom := pad
		for r in placed:
			bottom = maxf(bottom, r.position.y + r.size.y + pad)
		best = Vector2(pad, bottom)
	return best

func _overlaps_any(rect: Rect2, placed: Array[Rect2]) -> bool:
	for r in placed:
		if rect.intersects(r):
			return true
	return false

## The felt's usable width for packing — its laid-out width once known, or a
## sensible default on the very first build before layout has run.
func _canvas_width() -> float:
	var w := _ui.board_flow.size.x
	return w if w > 100.0 else 820.0

## Grow the canvas tall enough to hold every placed panel, so the scroll area
## can reach a group parked near the bottom of the felt.
func _size_canvas(placed: Array[Rect2]) -> void:
	var bottom := 0.0
	for r in placed:
		bottom = maxf(bottom, r.position.y + r.size.y)
	_ui.board_flow.custom_minimum_size = Vector2(0, bottom + UITheme.BOARD_PAD)

## A slim grip strip along the top of a group's panel: press it and drag to
## slide the whole group (a crossing/picture cluster moves as one) anywhere on
## the felt. main_ui follows the motion and stores the resting spot.
func _make_move_handle(panel: Control, melds: Array[CardSet]) -> Control:
	var handle := Panel.new()
	handle.custom_minimum_size = Vector2(0, UITheme.GROUP_HANDLE_HEIGHT)
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	handle.tooltip_text = "Drag to move this group around the felt"
	handle.add_theme_stylebox_override("panel",
		CardRenderer.panel_style(UITheme.COL_GROUP_HANDLE, 6))
	var dots := Label.new()
	dots.text = "⠿"
	dots.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dots.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dots.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	dots.add_theme_font_size_override("font_size", 11)
	dots.set_anchors_preset(Control.PRESET_FULL_RECT)
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	handle.add_child(dots)
	handle.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			_ui.begin_group_drag(panel, melds))
	return handle

func _make_meld_panel(meld: CardSet) -> PanelContainer:
	var gm := _ui.gm
	Rules.assign_jokers(meld.cards)
	var panel := PanelContainer.new()
	var valid := meld.is_valid()
	var locked := _ui._is_human_turn() and not gm.current_player_is_open() \
		and not gm.is_own_staged_meld(meld)
	# Valid groups sit quietly on the felt; only broken ones shout.
	var play_hint: bool = _ui.hint_meld_targets.has(meld)
	var sb := CardRenderer.panel_style(
		UITheme.COL_HINT_BG if play_hint else Color(1, 1, 1, 0.045), 10)
	if play_hint:
		# The hovered hand card lays off here as-is — spotlight the group.
		sb.border_color = UITheme.COL_HINT_EDGE
		sb.set_border_width_all(3)
	else:
		sb.border_color = UITheme.COL_MELD_BORDER if valid else UITheme.COL_MELD_BAD
		sb.set_border_width_all(1 if valid else 2)
	panel.add_theme_stylebox_override("panel", sb)
	if play_hint:
		panel.tooltip_text = "You can lay the hovered card here without moving anything."
	elif not valid:
		panel.tooltip_text = "Not a valid group yet — fix it before ending your turn."
	elif locked:
		panel.tooltip_text = "Locked until you open — lay down a valid group " \
			+ "from your own hand first."
	panel.set_drag_forwarding(Callable(),
		_ui._can_drop_on_meld.bind(meld), _ui._drop_on_meld.bind(meld))
	# The group lies along its orientation: a row when flat, a column upright.
	var box: BoxContainer
	if meld.orientation == CardSet.Orientation.VERTICAL:
		box = VBoxContainer.new()
	else:
		box = HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	for c in Rules.display_order(meld.cards):
		box.add_child(_make_card_button(c, meld))
	if _ui._is_human_turn():
		box.add_child(_make_rotate_button(meld))
	panel.add_child(_with_handle(panel, box, [meld] as Array[CardSet]))
	return panel

## Stack a group's move handle over its content in one column, so every panel on
## the felt carries a grip to drag it by. Keeps the card box as the direct
## parent of its cards (a vertical group's column, a cluster's grid) so the
## layout the rest of the code and tests read is unchanged.
func _with_handle(panel: Control, content: Control, melds: Array[CardSet]) -> VBoxContainer:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 3)
	outer.add_child(_make_move_handle(panel, melds))
	outer.add_child(content)
	return outer

## A small control on each lone group that turns it between lying flat and
## standing upright — purely how it sits on the felt, the group is unchanged.
## Groundwork for the layouts where direction matters (crossings, pictures).
func _make_rotate_button(meld: CardSet) -> Button:
	var b := Button.new()
	b.text = "⟳"
	b.tooltip_text = "Turn this group %s on the felt (visual only)." \
		% ("flat" if meld.orientation == CardSet.Orientation.VERTICAL else "upright")
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.custom_minimum_size = Vector2(24, 24)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(_ui._on_rotate_meld_pressed.bind(meld))
	return b

## A cluster panel: crossing groups and shape (picture) groups laid out on a
## grid of card cells, gaps left where the picture has none. Cards keep their
## usual behaviour (select, drag, drop onto them to add to their group); at a
## shared cell the card answers for its host group.
func _make_cluster_panel(cluster: Dictionary) -> PanelContainer:
	var melds: Array[CardSet] = cluster["melds"]
	for m in melds:
		Rules.assign_jokers(m.cards)
	var panel := PanelContainer.new()
	var all_valid := true
	for m in melds:
		if not m.is_valid():
			all_valid = false
	var sb := CardRenderer.panel_style(Color(1, 1, 1, 0.045), 10)
	sb.border_color = UITheme.COL_MELD_BORDER if all_valid else UITheme.COL_MELD_BAD
	sb.set_border_width_all(1 if all_valid else 2)
	panel.add_theme_stylebox_override("panel", sb)
	if not all_valid:
		panel.tooltip_text = "Not a valid group yet — fix it before ending your turn."
	elif melds.size() > 1:
		panel.tooltip_text = "Crossing groups — they share the card where they meet, " \
			+ "and each can still take cards."
	var cells: Dictionary = cluster["cells"]
	var meld_at: Dictionary = cluster["meld_at"]
	# Ghost cells — the spots a line can be played off the picture — sit on a
	# one-cell ring around the cluster, so the grid grows when any exist.
	var ghosts := _extension_ghosts(cluster)
	var lo := Vector2i.ZERO
	var hi: Vector2i = cluster["size"]
	if not ghosts.is_empty():
		lo -= Vector2i.ONE
		hi += Vector2i.ONE
	var grid := GridContainer.new()
	grid.columns = maxi(hi.x - lo.x, 1)
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	panel.add_child(_with_handle(panel, grid, melds))
	for y in range(lo.y, hi.y):
		for x in range(lo.x, hi.x):
			var cell := Vector2i(x, y)
			if cells.has(cell):
				grid.add_child(_make_card_button(cells[cell], meld_at[cell]))
			elif ghosts.has(cell):
				grid.add_child(_make_ghost_cell(ghosts[cell]))
			else:
				var gap := Control.new()
				gap.custom_minimum_size = UITheme.BOARD_CARD_SIZE
				gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
				grid.add_child(gap)
	return panel

## Drop/click targets for Scrabble-style plays around a picture: the legal
## first cell of a new line off each picture card (outward only, never
## hugging the picture, one line per card per axis) and the next outward cell
## of every existing extension line. Empty when it isn't the player's turn or
## the cluster holds no picture. Best-effort mirror of the engine's cell
## rules — the engine revalidates every play.
func _extension_ghosts(cluster: Dictionary) -> Dictionary:
	var out := {}
	if not _ui._is_human_turn():
		return out
	var has_picture := false
	for m: CardSet in cluster["melds"]:
		if m.is_shape():
			has_picture = true
	if not has_picture:
		return out
	var cells: Dictionary = cluster["cells"]
	var meld_at: Dictionary = cluster["meld_at"]
	var cell_of := {}
	for cell: Vector2i in cells:
		cell_of[cells[cell]] = cell
	var dirs := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for m: CardSet in cluster["melds"]:
		if m.is_attached():
			# Extend an existing line at its outward end.
			var end: Vector2i = cell_of[m.attach_anchor] \
				+ m.attach_step * (m.cards.size() + 1)
			if not cells.has(end) and not _hugs_picture(end, m.attach_step, cells, meld_at):
				out[end] = {"meld": m}
			continue
		if not m.is_shape():
			continue
		for p: Card in m.cards:
			for dir: Vector2i in dirs:
				if _axis_taken(p, dir):
					continue
				var first: Vector2i = cell_of[p] + dir
				if cells.has(first) or out.has(first) \
						or _hugs_picture(first, dir, cells, meld_at):
					continue
				out[first] = {"anchor": p, "step": dir}
	return out

## True when this empty cell touches a picture card other than the one the
## line reads from (the cell behind it, against `step`) — the engine's
## outward-only rule, so ghosts only appear where a play could stick.
func _hugs_picture(cell: Vector2i, step: Vector2i, cells: Dictionary,
		meld_at: Dictionary) -> bool:
	for side in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var n_cell: Vector2i = cell + side
		if n_cell == cell - step or not cells.has(n_cell):
			continue
		var n_meld: CardSet = meld_at.get(n_cell)
		if n_meld != null and n_meld.is_shape():
			return true
	return false

## True when this picture card already carries an extension line on the axis
## of `dir` (one line per card per axis).
func _axis_taken(anchor: Card, dir: Vector2i) -> bool:
	for m in _ui.gm.board.melds:
		if m.is_attached() and m.attach_anchor == anchor \
				and m.attach_step.abs() == dir.abs():
			return true
	return false

## A faint "+" cell beside a picture: drop cards (or click with a selection)
## to lay them as a line reading outward from the picture card behind it.
func _make_ghost_cell(info: Dictionary) -> Button:
	var b := Button.new()
	b.text = "+"
	b.custom_minimum_size = UITheme.BOARD_CARD_SIZE
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "Play cards here: together with the picture card they " \
		+ "extend, they must read as a set or run (a single card may sit as " \
		+ "a pair that could still grow). Vertical straights keep the lower " \
		+ "rank on top."
	var sb := CardRenderer.panel_style(Color(1, 1, 1, 0.02), 7)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(1)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("hover", CardRenderer.hover_variant(sb))
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	if info.has("meld"):
		var meld: CardSet = info["meld"]
		b.pressed.connect(_ui._on_extend_line_pressed.bind(meld))
		b.set_drag_forwarding(Callable(),
			_ui._can_drop_on_meld.bind(meld), _ui._drop_on_meld.bind(meld))
	else:
		b.pressed.connect(_ui._on_line_start_pressed.bind(info["anchor"], info["step"]))
		b.set_drag_forwarding(Callable(),
			_ui._can_drop_line_start.bind(info["anchor"], info["step"]),
			_ui._drop_line_start.bind(info["anchor"], info["step"]))
	return b

func _make_new_group_zone() -> Button:
	var zone := Button.new()
	zone.text = "+ New group"
	zone.tooltip_text = "Drop or move selected cards here to start a brand-new group"
	zone.custom_minimum_size = UITheme.NEW_GROUP_SIZE
	zone.focus_mode = Control.FOCUS_NONE
	var sb := CardRenderer.panel_style(Color(1, 1, 1, 0.04), 10)
	sb.border_color = Color(1, 1, 1, 0.35)
	sb.set_border_width_all(2)
	zone.add_theme_stylebox_override("normal", sb)
	zone.add_theme_stylebox_override("hover", CardRenderer.hover_variant(sb))
	zone.add_theme_stylebox_override("pressed", sb)
	zone.pressed.connect(_ui._on_new_meld_pressed)
	zone.set_drag_forwarding(Callable(), _ui._can_drop_new_group, _ui._drop_new_group)
	return zone

## A passive ghost of the "+ New group" zone, spotlighted in the hint colour, to
## tell the player the card they are hovering forms a fresh group with other
## cards already in their hand. Purely a cue — the real play is a drag or select.
func _make_new_group_hint() -> PanelContainer:
	var zone := PanelContainer.new()
	zone.custom_minimum_size = UITheme.NEW_GROUP_SIZE
	zone.tooltip_text = "The hovered card starts a new group with cards in your hand."
	var sb := CardRenderer.panel_style(UITheme.COL_HINT_BG, 10)
	sb.border_color = UITheme.COL_HINT_EDGE
	sb.set_border_width_all(3)
	zone.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = "✓ New group"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", UITheme.COL_HINT_EDGE)
	zone.add_child(lbl)
	return zone

func refresh_hand() -> void:
	var gm := _ui.gm
	var sb := CardRenderer.panel_style(UITheme.COL_FELT_DARK, 10)
	if _ui._is_human_turn():
		sb.border_color = UITheme.COL_CHIP_ACTIVE
		sb.set_border_width_all(2)
	_ui.hand_panel.add_theme_stylebox_override("panel", sb)
	_refresh_hand_meter()
	_ui._clear_children(_ui.hand_box)
	var hand := gm.players[0].hand
	if gm.players[0].has_opened:
		_ui.hand_title.text = "Your hand (%d)" % hand.size()
	else:
		_ui.hand_title.text = "Your hand (%d) — not open yet: lay down a valid group " % hand.size() \
			+ "from these cards before touching the table"
	# The hand keeps whatever order the player gave it (drag to rearrange,
	# sort buttons to sort). A joker back in the hand is a free wildcard, so
	# shed any representation (and choice) left over from its time on the table.
	for c in hand:
		if c.is_joker:
			c.joker_rank = 0
			c.joker_suit = ""
			c.joker_pref_rank = 0
			c.joker_pref_suit = ""
			c.joker_lock_rank = 0
			c.joker_lock_suit = ""
	for c in hand:
		_ui.hand_box.add_child(_make_card_button(c))

## Your own ultimate meter, shown in the hand header: a small "Ultimate" tag
## beside the charge bar. Rebuilt each refresh so the bar tracks your charge;
## drawn only when the meter is enabled (meter_max > 0).
func _refresh_hand_meter() -> void:
	_ui._clear_children(_ui.hand_meter_slot)
	var gm := _ui.gm
	if gm.meter_max <= 0:
		return
	var tag := Label.new()
	tag.text = "Ultimate"
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.add_theme_font_size_override("font_size", 12)
	tag.add_theme_color_override("font_color", UITheme.COL_CHIP_ACTIVE)
	_ui.hand_meter_slot.add_child(tag)
	var bar := CardRenderer.make_meter_bar(gm.projected_meter(gm.players[0]), gm.meter_max)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ui.hand_meter_slot.add_child(bar)

## Card buttons are both click-to-select toggles and drag sources. Cards on the
## table (meld != null) are also drop targets for their own group, and are
## greyed out until the player has opened; hand cards are drop targets for
## returning played cards.
func _make_card_button(c: Card, meld: CardSet = null) -> Button:
	var on_board := meld != null
	var b := Button.new()
	b.toggle_mode = true
	b.text = c.label()
	b.button_pressed = _ui.selected.has(c)
	b.custom_minimum_size = UITheme.BOARD_CARD_SIZE if on_board else UITheme.CARD_SIZE
	b.disabled = not _ui._card_is_interactive(meld)
	if on_board and b.disabled and _ui._is_human_turn():
		b.tooltip_text = "Locked until you open — lay down a valid group " \
			+ "from your own hand first."
	b.add_theme_font_size_override("font_size",
		UITheme.BOARD_CARD_FONT_SIZE if on_board else UITheme.CARD_FONT_SIZE)
	b.focus_mode = Control.FOCUS_NONE

	var font_col := UITheme.COL_CARD_RED if UITheme.RED_SUITS.has(c.suit) else UITheme.COL_CARD_BLACK
	if c.is_joker:
		font_col = UITheme.COL_JOKER
		if not b.disabled:
			if c.joker_rank > 0:
				b.tooltip_text = ("Joker placed as %s — it stays that card until " \
					+ "it leaves the table. Hold the real %s? Drop it on this " \
					+ "joker to swap it into your hand.") % [c.rep_label(), c.rep_label()]
				if on_board and _ui._joker_is_rechoosable(c, meld):
					b.tooltip_text += "\nRight-click to change what it stands for " \
						+ "(only until your turn ends)."
			else:
				b.tooltip_text = "Joker — counts as any card."
	for state in ["font_color", "font_pressed_color", "font_hover_color",
			"font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, font_col)
	b.add_theme_color_override("font_disabled_color", Color(font_col, 0.75))

	var bg := UITheme.COL_JOKER_BG if c.is_joker else UITheme.COL_CARD_BG
	var border := UITheme.COL_JOKER if c.is_joker else UITheme.COL_CARD_BORDER
	var border_w := 1
	if _ui.highlighted.has(c):
		bg = UITheme.COL_HILITE_BG
		border = UITheme.COL_HILITE
		border_w = 3
	if _ui.selected.has(c):
		bg = UITheme.COL_SELECT_BG
		border = UITheme.COL_SELECT
		border_w = 3
	# Suit highlighter (every card in play — hand and table): while a suit is
	# hovered, cards of that suit get a bright outline and everything else is
	# faded out below. Jokers match every suit since they can stand in for any of
	# them. Selection/enemy-touch borders keep priority so those states still read.
	var filter_active := _ui.hover_filter_suit != ""
	var filter_match := filter_active and (c.is_joker or c.suit == _ui.hover_filter_suit)
	if filter_match and not _ui.selected.has(c) and not _ui.highlighted.has(c):
		border = UITheme.COL_FILTER_EDGE
		border_w = 3
	# Glass cards render transparent — the felt shows through whatever state
	# the card is in. The selection/highlight border stays so they still read.
	if c.is_glass():
		bg = Color(bg, UITheme.GLASS_BG_ALPHA)
		if not _ui.selected.has(c) and not _ui.highlighted.has(c):
			border = UITheme.COL_GLASS_EDGE
			border_w = 2
		if not on_board:
			b.tooltip_text = "Glass — see-through from the back: opponents " \
				+ "can see this card in your hand." \
				+ ("" if b.tooltip_text == "" else "\n" + b.tooltip_text)
	var style := CardRenderer.card_style(bg, border, border_w)
	for state in ["normal", "pressed", "disabled"]:
		b.add_theme_stylebox_override(state, style)
	b.add_theme_stylebox_override("hover", CardRenderer.card_style(bg, UITheme.COL_SELECT, maxi(border_w, 2)))
	b.add_theme_stylebox_override("hover_pressed", CardRenderer.card_style(bg, border, border_w))

	if c.is_sticky():
		CardRenderer.add_slime_blob(b)
	# A hand card you can play right now (with no rearranging) is capped with a
	# green strip; hovering it lights its destination group the same green.
	if not on_board and _ui._card_is_playable_now(c):
		CardRenderer.add_play_marker(b)
		var note := "Playable now — drop it straight onto its group (or lay it as " \
			+ "a new one) with no rearranging."
		b.tooltip_text = note if b.tooltip_text == "" else b.tooltip_text + "\n" + note
	if filter_active and not filter_match:
		b.modulate = Color(1, 1, 1, UITheme.FILTER_DIM_ALPHA)

	b.toggled.connect(_ui._on_card_toggled.bind(c))
	b.gui_input.connect(_ui._on_card_gui_input.bind(c, meld))
	if on_board:
		b.set_drag_forwarding(_ui._get_card_drag_data.bind(c, b),
			_ui._can_drop_on_meld.bind(meld), _ui._drop_on_meld.bind(meld))
	else:
		# Hand cards are also reorder targets: dropping other hand cards on
		# them moves those cards next to this one.
		b.set_drag_forwarding(_ui._get_card_drag_data.bind(c, b),
			_ui._can_drop_on_hand_card.bind(c), _ui._drop_on_hand_card.bind(c))
		# Hovering a hand card lights up any spot on the board it could play into
		# right now with no rearranging — a lay-off onto an existing group, or a
		# brand-new group it forms with other cards already in your hand.
		b.mouse_entered.connect(_ui._on_hand_card_hover_enter.bind(c))
		b.mouse_exited.connect(_ui._on_hand_card_hover_exit.bind(c))
	_ui.card_nodes[c] = b
	return b
