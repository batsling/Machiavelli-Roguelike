extends Control

## Playable UI for vanilla Machiavelli, built entirely in code so the scene
## file stays trivial.
##
## Table layout: you sit at the bottom; opponents sit around the table showing
## the backs of their cards. The first enemy sits directly opposite you at the
## top, the second on the left, and a fourth player (when one exists) sits on
## the right — at most 4 seats in total. Backs overlap more as a hand grows so
## every seat always fits on screen.
##
## How to play: on your turn, drag cards — from your hand AND from any group
## on the table (rearranging the table is the heart of the game). Drop them
## onto a group (or any card in it) to add them there, or onto empty felt /
## the "+ New group" zone to start a fresh group. Cards you laid down this
## turn can be dragged back into your hand (or selected and sent back with
## the "Return to hand" button). Clicking still works too: click cards to
## select them (they lift and turn blue), then click a group's "+" button or
## "+ New group". Dragging a selected card drags the whole selection.
##
## Opening rule: until you have laid down at least one valid group built only
## from your own hand, you cannot add to other groups or take cards from them
## (table cards are greyed out — except cards you played this turn, which stay
## movable so you can always take them back). The same rule binds the AI.
##
## The table only has to be valid when you press "End turn". "Undo action"
## takes back the last staged move; "Undo turn" puts the whole turn back. If
## you can't (or won't) play, "Draw & end turn".
##
## Enemy turns play out visibly: each move the AI makes is applied one at a
## time, its cards fly from where they were (the enemy's hidden hand or their
## previous spot on the table) to where they land. Every card any enemy
## touched stays highlighted in gold through your whole turn, so you can see
## at a glance everything that changed while you weren't acting; the
## highlights clear when the enemies start their next round.
##
## Your hand works like Balatro's: it keeps whatever order you give it. Drag
## a card onto another hand card to move it there (left half = before, right
## half = after), drag to the hand's empty space to send it to the end, or
## use the "Sort: rank" / "Sort: suit" buttons.
##
## The Settings dialog holds: the enemy AI graph (vertical = weak→strong,
## horizontal = quick→conservative; applies from the next enemy turn), the
## number of enemies (1-3, next game), cards drawn per turn (1-3, applies
## immediately), and the joker toggle (next game). Jokers (★) count as any
## card; a joker in a valid group shows the card it currently stands for
## (e.g. ★7♥), and if you hold that exact card you can drop it on the joker
## to swap it out and take the wildcard into your hand. When a group leaves
## the joker a choice (say, two missing suits in a set of three), right-click
## the joker on your turn to pick which card it stands for.

const AI_THINK_DELAY := 0.6
const AI_MOVE_DELAY := 0.5
const AI_ANIM_TIME := 0.45
const RED_SUITS := ["hearts", "diamonds"]
const DRAG_TYPE := "machiavelli_cards"

## The UI seats at most this many players: you + up to 3 opponents.
const MAX_PLAYERS := 4
const ENEMY_NAMES := ["Rosso", "Nero", "Bianco"]

const CARD_SIZE := Vector2(78, 108)
const CARD_FONT_SIZE := 28
const ADD_BTN_SIZE := Vector2(44, 108)
const NEW_GROUP_SIZE := Vector2(150, 124)
const UI_FONT_SIZE := 17
const BACK_SIZE_TOP := Vector2(46, 64)  # portrait backs for the seat opposite you
const BACK_SIZE_SIDE := Vector2(64, 46)  # landscape backs for the left/right seats
const BACKS_MAX_LEN_TOP := 560.0
const BACKS_MAX_LEN_SIDE := 330.0
const SIDE_SEAT_WIDTH := 130.0

const COL_FELT := Color(0.09, 0.30, 0.19)
const COL_FELT_DARK := Color(0.07, 0.22, 0.14)
const COL_CARD_BG := Color(0.97, 0.96, 0.91)
const COL_CARD_BORDER := Color(0.60, 0.56, 0.46)
const COL_CARD_RED := Color(0.78, 0.13, 0.16)
const COL_CARD_BLACK := Color(0.10, 0.10, 0.13)
const COL_CARD_BACK := Color(0.17, 0.24, 0.50)
const COL_CARD_BACK_EDGE := Color(0.93, 0.93, 0.97)
const COL_SELECT := Color(0.20, 0.55, 0.95)
const COL_SELECT_BG := Color(0.84, 0.91, 1.0)
const COL_HILITE := Color(0.93, 0.72, 0.13)
const COL_HILITE_BG := Color(1.0, 0.94, 0.75)
const COL_MELD_OK := Color(0.35, 0.75, 0.45)
const COL_MELD_BAD := Color(0.92, 0.35, 0.30)
const COL_CHIP_BG := Color(0.13, 0.14, 0.17)
const COL_CHIP_ACTIVE := Color(0.93, 0.72, 0.13)
const COL_JOKER := Color(0.48, 0.20, 0.62)
const COL_JOKER_BG := Color(0.96, 0.92, 0.98)

var gm: GameManager
var selected: Array[Card] = []
var highlighted := {}  # Card -> true; every card the enemies touched last round
var ai_running := false
# Bumped on every new game so a suspended AI coroutine from the previous game
# notices on resume and bails out instead of acting on the fresh state.
var game_generation := 0
# Card -> Button for every face-up card currently on screen; rebuilt on each
# refresh so enemy-move animations can find source and destination positions.
var card_nodes := {}
# player_id -> the container of card backs for that opponent; rebuilt on each
# refresh, used as the animation origin for cards played from a hidden hand.
var opponent_backs := {}

# Settings (the Settings dialog). The AI graph and draw count apply
# immediately; enemy count and jokers take effect on the next new game.
var ai_strength := 1.0    # 0 = weak, 1 = strong
var ai_style := 0.0       # 0 = quick, 1 = conservative
var enemy_count := 2      # 1-3
var draw_per_turn := 1    # 1-3
var include_jokers := false

var seat_top: VBoxContainer
var seat_left: VBoxContainer
var seat_right: VBoxContainer
var stock_label: Label
var status_label: Label
var log_box: RichTextLabel
var board_flow: HFlowContainer
var hand_panel: PanelContainer
var hand_box: HFlowContainer
var hand_title: Label
var selection_label: Label
var return_btn: Button
var undo_action_btn: Button
var reset_btn: Button
var end_turn_btn: Button
var draw_btn: Button
var settings_btn: Button
var new_game_btn: Button
var settings_dialog: AcceptDialog
var ai_graph: AIGraph
var ai_desc_label: Label
var anim_layer: Control

func _ready() -> void:
	gm = GameManager.new()
	add_child(gm)
	gm.turn_committed.connect(_on_turn_committed)
	gm.card_drawn.connect(_on_card_drawn)
	gm.player_passed.connect(_on_player_passed)
	gm.game_over.connect(_on_game_over)
	_build_layout()
	_new_game()

func _new_game() -> void:
	game_generation += 1
	selected.clear()
	highlighted.clear()
	ai_running = false
	_clear_children(anim_layer)
	var names: Array = ["You"]
	for i in enemy_count:
		names.append(ENEMY_NAMES[i])
	gm.setup(names, GameManager.DEFAULT_HAND_SIZE, -1, include_jokers)
	gm.draw_per_turn = draw_per_turn
	log_box.clear()
	_set_status("Your turn. Drag cards to the table (or click to select) — "
		+ "open by laying down a valid group from your hand.")
	_log("New game: %d enem%s, 13 cards each, double deck, %s." % [enemy_count,
		"y" if enemy_count == 1 else "ies",
		"4 jokers in" if include_jokers else "no jokers"])
	if include_jokers:
		_log("Jokers (★) count as any card. A joker in a valid group shows what "
			+ "it stands for — drop the real card on it to swap the joker into your hand.")
	_log("Opening rule: lay down a valid group from your own hand before "
		+ "you can touch other groups on the table.")
	_refresh()

# --- Layout -------------------------------------------------------------------

func _build_layout() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var ui_theme := Theme.new()
	ui_theme.default_font_size = UI_FONT_SIZE
	theme = ui_theme

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	root.offset_left = 14
	root.offset_top = 14
	root.offset_right = -14
	root.offset_bottom = -14
	add_child(root)

	# Top row: the first enemy's seat, centered directly opposite you, with the
	# stock count tucked into the corner.
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 8)
	root.add_child(top_bar)
	var top_pad_left := Control.new()
	top_pad_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(top_pad_left)
	seat_top = _make_seat()
	top_bar.add_child(seat_top)
	var top_pad_right := Control.new()
	top_pad_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(top_pad_right)
	stock_label = Label.new()
	stock_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top_bar.add_child(stock_label)

	# Middle row: left seat, the felt, right seat (hidden until a 4th player).
	var mid_row := HBoxContainer.new()
	mid_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid_row.add_theme_constant_override("separation", 8)
	root.add_child(mid_row)
	seat_left = _make_seat()
	seat_left.custom_minimum_size = Vector2(SIDE_SEAT_WIDTH, 0)
	mid_row.add_child(seat_left)

	# Table: green felt panel holding a flow of meld panels. The felt itself
	# (panel, scroll area and flow) accepts drops to start a new group.
	var table_panel := PanelContainer.new()
	table_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table_panel.add_theme_stylebox_override("panel", _panel_style(COL_FELT, 10))
	mid_row.add_child(table_panel)
	var table_scroll := ScrollContainer.new()
	table_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	table_panel.add_child(table_scroll)
	board_flow = HFlowContainer.new()
	board_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_flow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_flow.mouse_filter = Control.MOUSE_FILTER_PASS
	board_flow.add_theme_constant_override("h_separation", 10)
	board_flow.add_theme_constant_override("v_separation", 10)
	table_scroll.add_child(board_flow)
	for zone: Control in [table_panel, table_scroll, board_flow]:
		zone.set_drag_forwarding(Callable(), _can_drop_new_group, _drop_new_group)

	seat_right = _make_seat()
	seat_right.custom_minimum_size = Vector2(SIDE_SEAT_WIDTH, 0)
	mid_row.add_child(seat_right)

	# Hand: darker felt panel at the bottom. The whole panel accepts drops so
	# cards played this turn can be dragged back into the hand.
	hand_panel = PanelContainer.new()
	root.add_child(hand_panel)
	var hand_col := VBoxContainer.new()
	hand_col.add_theme_constant_override("separation", 4)
	hand_panel.add_child(hand_col)
	var hand_top := HBoxContainer.new()
	hand_top.add_theme_constant_override("separation", 8)
	hand_col.add_child(hand_top)
	hand_title = Label.new()
	hand_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_title.add_theme_font_size_override("font_size", 15)
	hand_title.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	hand_top.add_child(hand_title)
	var sort_rank_btn := Button.new()
	sort_rank_btn.text = "Sort: rank"
	sort_rank_btn.tooltip_text = "Sort your hand by rank (jokers last)"
	sort_rank_btn.focus_mode = Control.FOCUS_NONE
	sort_rank_btn.pressed.connect(_on_sort_rank_pressed)
	hand_top.add_child(sort_rank_btn)
	var sort_suit_btn := Button.new()
	sort_suit_btn.text = "Sort: suit"
	sort_suit_btn.tooltip_text = "Sort your hand by suit, then rank (jokers last)"
	sort_suit_btn.focus_mode = Control.FOCUS_NONE
	sort_suit_btn.pressed.connect(_on_sort_suit_pressed)
	hand_top.add_child(sort_suit_btn)
	hand_box = HFlowContainer.new()
	hand_box.add_theme_constant_override("h_separation", 4)
	hand_box.add_theme_constant_override("v_separation", 4)
	hand_col.add_child(hand_box)
	for zone: Control in [hand_panel, hand_col, hand_top, hand_title, hand_box]:
		zone.set_drag_forwarding(Callable(), _can_drop_on_hand, _drop_on_hand)

	# Action row.
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	root.add_child(actions)

	selection_label = Label.new()
	selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(selection_label)

	return_btn = Button.new()
	return_btn.text = "Return to hand"
	return_btn.tooltip_text = "Put the selected cards you played this turn back in your hand"
	return_btn.pressed.connect(_on_return_pressed)
	actions.add_child(return_btn)

	undo_action_btn = Button.new()
	undo_action_btn.text = "Undo action"
	undo_action_btn.tooltip_text = "Take back only the last move you staged this turn"
	undo_action_btn.pressed.connect(_on_undo_action_pressed)
	actions.add_child(undo_action_btn)

	reset_btn = Button.new()
	reset_btn.text = "Undo turn"
	reset_btn.tooltip_text = "Take back everything staged this turn"
	reset_btn.pressed.connect(_on_reset_pressed)
	actions.add_child(reset_btn)

	end_turn_btn = Button.new()
	end_turn_btn.text = "End turn"
	end_turn_btn.pressed.connect(_on_end_turn_pressed)
	actions.add_child(end_turn_btn)

	draw_btn = Button.new()
	draw_btn.text = "Draw & end turn"
	draw_btn.pressed.connect(_on_draw_pressed)
	actions.add_child(draw_btn)

	settings_btn = Button.new()
	settings_btn.text = "Settings"
	settings_btn.tooltip_text = "Enemy AI, enemy count, draw count and jokers"
	settings_btn.pressed.connect(_on_settings_pressed)
	actions.add_child(settings_btn)

	new_game_btn = Button.new()
	new_game_btn.text = "New game"
	new_game_btn.pressed.connect(_new_game)
	actions.add_child(new_game_btn)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status_label)

	log_box = RichTextLabel.new()
	log_box.custom_minimum_size = Vector2(0, 110)
	log_box.scroll_following = true
	log_box.fit_content = false
	root.add_child(log_box)

	# Overlay for the flying-card animations; never intercepts the mouse.
	anim_layer = Control.new()
	anim_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	anim_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anim_layer)

	_build_settings_dialog()

func _build_settings_dialog() -> void:
	settings_dialog = AcceptDialog.new()
	settings_dialog.title = "Settings"
	settings_dialog.ok_button_text = "Done"
	add_child(settings_dialog)

	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(380, 0)
	col.add_theme_constant_override("separation", 10)
	settings_dialog.add_child(col)

	var ai_label := Label.new()
	ai_label.text = "Enemy AI — click the graph: up = stronger, right = more conservative."
	ai_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(ai_label)

	ai_graph = AIGraph.new()
	ai_graph.set_values(ai_style, ai_strength)
	ai_graph.value_changed.connect(_on_ai_graph_changed)
	col.add_child(ai_graph)

	ai_desc_label = Label.new()
	ai_desc_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	ai_desc_label.text = _ai_description()
	col.add_child(ai_desc_label)

	col.add_child(HSeparator.new())

	col.add_child(_make_spin_row("Enemies (next game):", 1, 3, enemy_count,
		_on_enemy_count_changed))
	col.add_child(_make_spin_row("Cards drawn per turn:", 1, 3, draw_per_turn,
		_on_draw_count_changed))

	var joker_check := CheckBox.new()
	joker_check.text = "Include 4 jokers — wildcards (next game)"
	joker_check.button_pressed = include_jokers
	joker_check.toggled.connect(_on_jokers_toggled)
	col.add_child(joker_check)

func _make_spin_row(text: String, minimum: int, maximum: int, value: int,
		on_changed: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1
	spin.value = value
	spin.value_changed.connect(on_changed)
	row.add_child(spin)
	return row

func _on_settings_pressed() -> void:
	settings_dialog.popup_centered()

func _on_enemy_count_changed(value: float) -> void:
	enemy_count = int(value)

func _on_draw_count_changed(value: float) -> void:
	draw_per_turn = int(value)
	gm.draw_per_turn = draw_per_turn

func _on_jokers_toggled(on: bool) -> void:
	include_jokers = on

func _on_ai_graph_changed(style: float, strength: float) -> void:
	ai_style = style
	ai_strength = strength
	ai_desc_label.text = _ai_description()

func _ai_description() -> String:
	var skill := "strong"
	if ai_strength < 0.4:
		skill = "weak"
	elif ai_strength < 0.75:
		skill = "capable"
	var pace := "quick"
	if ai_style >= 0.75:
		pace = "conservative"
	elif ai_style >= 0.4:
		pace = "balanced"
	return "Enemies play %s and %s. Applies from their next turn." % [skill, pace]

func _make_seat() -> VBoxContainer:
	var seat := VBoxContainer.new()
	seat.alignment = BoxContainer.ALIGNMENT_CENTER
	seat.add_theme_constant_override("separation", 6)
	return seat

# --- Refresh ------------------------------------------------------------------

func _refresh() -> void:
	card_nodes.clear()
	_prune_selection()
	_refresh_seats()
	_refresh_board()
	_refresh_hand()
	_refresh_buttons()

## Seat opponents around the table: players[1] opposite you, players[2] on the
## left, players[3] on the right. Unused seats collapse.
func _refresh_seats() -> void:
	opponent_backs.clear()
	var seats: Array = [seat_top, seat_left, seat_right]
	var seated_players := mini(gm.players.size(), MAX_PLAYERS)
	for i in seats.size():
		var seat: VBoxContainer = seats[i]
		_clear_children(seat)
		var player_index := i + 1
		if player_index >= seated_players:
			seat.visible = false
			continue
		seat.visible = true
		var p := gm.players[player_index]
		var chip := _make_player_chip(p)
		chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		seat.add_child(chip)
		var backs := _make_card_backs(p.hand.size(), i == 0)
		backs.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		seat.add_child(backs)
		opponent_backs[p.player_id] = backs
	stock_label.text = "Stock: %d" % gm.deck.size()

func _make_player_chip(p: PlayerState) -> PanelContainer:
	var is_current: bool = p == gm.current_player() and not gm.is_game_over
	var chip := PanelContainer.new()
	var sb := _panel_style(COL_CHIP_BG, 8)
	sb.border_color = COL_CHIP_ACTIVE if is_current else Color(1, 1, 1, 0.15)
	sb.set_border_width_all(2)
	chip.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	var marker := "▶ " if is_current else ""
	var opened := "" if p.has_opened else " · not open"
	lbl.text = "%s%s — %d cards%s" % [marker, p.display_name, p.hand.size(), opened]
	if is_current:
		lbl.add_theme_color_override("font_color", COL_CHIP_ACTIVE)
	chip.add_child(lbl)
	return chip

## A row (top seat) or column (side seats) of face-down cards. The overlap
## tightens as the hand grows so the seat never exceeds a fixed footprint.
func _make_card_backs(count: int, horizontal: bool) -> BoxContainer:
	var box: BoxContainer
	var back_size: Vector2
	var max_len: float
	if horizontal:
		box = HBoxContainer.new()
		back_size = BACK_SIZE_TOP
		max_len = BACKS_MAX_LEN_TOP
	else:
		box = VBoxContainer.new()
		back_size = BACK_SIZE_SIDE
		max_len = BACKS_MAX_LEN_SIDE
	var card_len := back_size.x if horizontal else back_size.y
	if count > 1:
		var step := minf(card_len * 0.55, (max_len - card_len) / (count - 1))
		box.add_theme_constant_override("separation", int(step - card_len))
	for _i in count:
		box.add_child(_make_card_back(back_size))
	return box

func _make_card_back(back_size: Vector2) -> Panel:
	var back := Panel.new()
	back.custom_minimum_size = back_size
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_CARD_BACK
	sb.border_color = COL_CARD_BACK_EDGE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	back.add_theme_stylebox_override("panel", sb)
	return back

func _refresh_board() -> void:
	_clear_children(board_flow)
	if gm.board.melds.is_empty():
		var empty := Label.new()
		empty.text = "The table is empty — drag cards here to lay down the first group."
		empty.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
		board_flow.add_child(empty)
	for meld in gm.board.melds:
		board_flow.add_child(_make_meld_panel(meld))
	board_flow.add_child(_make_new_group_zone())

func _make_meld_panel(meld: CardSet) -> PanelContainer:
	Rules.assign_jokers(meld.cards)
	var panel := PanelContainer.new()
	var valid := meld.is_valid()
	var locked := _is_human_turn() and not gm.current_player_is_open() \
		and not gm.is_own_staged_meld(meld)
	var sb := _panel_style(Color(1, 1, 1, 0.06), 10)
	sb.border_color = COL_MELD_OK if valid else COL_MELD_BAD
	sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)
	if not valid:
		panel.tooltip_text = "Not a valid group yet — fix it before ending your turn."
	elif locked:
		panel.tooltip_text = "Locked until you open — lay down a valid group " \
			+ "from your own hand first."
	panel.set_drag_forwarding(Callable(),
		_can_drop_on_meld.bind(meld), _drop_on_meld.bind(meld))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	panel.add_child(row)
	for c in Rules.display_order(meld.cards):
		row.add_child(_make_card_button(c, meld))
	var add_btn := Button.new()
	add_btn.text = "+"
	add_btn.tooltip_text = "Move selected cards into this group"
	add_btn.custom_minimum_size = ADD_BTN_SIZE
	add_btn.disabled = selected.is_empty() or not _is_human_turn() or locked
	add_btn.pressed.connect(_on_add_to_meld_pressed.bind(meld))
	add_btn.set_drag_forwarding(Callable(),
		_can_drop_on_meld.bind(meld), _drop_on_meld.bind(meld))
	row.add_child(add_btn)
	return panel

func _make_new_group_zone() -> Button:
	var zone := Button.new()
	zone.text = "+ New group"
	zone.tooltip_text = "Drop or move selected cards here to start a brand-new group"
	zone.custom_minimum_size = NEW_GROUP_SIZE
	zone.disabled = selected.is_empty() or not _is_human_turn()
	zone.focus_mode = Control.FOCUS_NONE
	var sb := _panel_style(Color(1, 1, 1, 0.04), 10)
	sb.border_color = Color(1, 1, 1, 0.35)
	sb.set_border_width_all(2)
	zone.add_theme_stylebox_override("normal", sb)
	zone.add_theme_stylebox_override("hover", _hover_variant(sb))
	zone.add_theme_stylebox_override("pressed", sb)
	var sb_off := _panel_style(Color(1, 1, 1, 0.02), 10)
	sb_off.border_color = Color(1, 1, 1, 0.12)
	sb_off.set_border_width_all(2)
	zone.add_theme_stylebox_override("disabled", sb_off)
	zone.pressed.connect(_on_new_meld_pressed)
	zone.set_drag_forwarding(Callable(), _can_drop_new_group, _drop_new_group)
	return zone

func _refresh_hand() -> void:
	var sb := _panel_style(COL_FELT_DARK, 10)
	if _is_human_turn():
		sb.border_color = COL_CHIP_ACTIVE
		sb.set_border_width_all(2)
	hand_panel.add_theme_stylebox_override("panel", sb)
	_clear_children(hand_box)
	var hand := gm.players[0].hand
	if gm.players[0].has_opened:
		hand_title.text = "Your hand (%d)" % hand.size()
	else:
		hand_title.text = "Your hand (%d) — not open yet: lay down a valid group " % hand.size() \
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
	for c in hand:
		hand_box.add_child(_make_card_button(c))

func _refresh_buttons() -> void:
	var human_turn := _is_human_turn()
	return_btn.disabled = not human_turn or not gm.can_return_to_hand(selected)
	undo_action_btn.disabled = not human_turn or not gm.can_undo_action()
	reset_btn.disabled = not human_turn or not gm.can_undo_action()
	end_turn_btn.disabled = not human_turn
	draw_btn.disabled = not human_turn
	if selected.is_empty():
		selection_label.text = ""
	else:
		var parts := PackedStringArray()
		for c in Rules.display_order(selected):
			parts.append(c.label())
		selection_label.text = "Selected: %s" % " ".join(parts)

# --- Card rendering -------------------------------------------------------------

## Card buttons are both click-to-select toggles and drag sources. Cards on the
## table (meld != null) are also drop targets for their own group, and are
## greyed out until the player has opened; hand cards are drop targets for
## returning played cards.
func _make_card_button(c: Card, meld: CardSet = null) -> Button:
	var on_board := meld != null
	var b := Button.new()
	b.toggle_mode = true
	b.text = c.label()
	b.button_pressed = selected.has(c)
	b.custom_minimum_size = CARD_SIZE
	b.disabled = not _card_is_interactive(meld)
	if on_board and b.disabled and _is_human_turn():
		b.tooltip_text = "Locked until you open — lay down a valid group " \
			+ "from your own hand first."
	b.add_theme_font_size_override("font_size", CARD_FONT_SIZE)
	b.focus_mode = Control.FOCUS_NONE

	var font_col := COL_CARD_RED if RED_SUITS.has(c.suit) else COL_CARD_BLACK
	if c.is_joker:
		font_col = COL_JOKER
		if not b.disabled:
			if c.joker_rank > 0:
				b.tooltip_text = "Joker standing in for %s. Hold the real %s? " \
					% [c.rep_label(), c.rep_label()] \
					+ "Drop it on this joker to swap it into your hand."
				if on_board and not Rules.joker_alternatives(meld.cards).is_empty():
					b.tooltip_text += "\nRight-click to choose what the joker stands for."
					b.gui_input.connect(_on_joker_gui_input.bind(c, meld))
			else:
				b.tooltip_text = "Joker — counts as any card."
	for state in ["font_color", "font_pressed_color", "font_hover_color",
			"font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, font_col)
	b.add_theme_color_override("font_disabled_color", Color(font_col, 0.75))

	var bg := COL_JOKER_BG if c.is_joker else COL_CARD_BG
	var border := COL_JOKER if c.is_joker else COL_CARD_BORDER
	var border_w := 1
	if highlighted.has(c):
		bg = COL_HILITE_BG
		border = COL_HILITE
		border_w = 3
	if selected.has(c):
		bg = COL_SELECT_BG
		border = COL_SELECT
		border_w = 3
	var style := _card_style(bg, border, border_w)
	for state in ["normal", "pressed", "disabled"]:
		b.add_theme_stylebox_override(state, style)
	b.add_theme_stylebox_override("hover", _card_style(bg, COL_SELECT, maxi(border_w, 2)))
	b.add_theme_stylebox_override("hover_pressed", _card_style(bg, border, border_w))

	b.toggled.connect(_on_card_toggled.bind(c))
	if on_board:
		b.set_drag_forwarding(_get_card_drag_data.bind(c, b),
			_can_drop_on_meld.bind(meld), _drop_on_meld.bind(meld))
	else:
		# Hand cards are also reorder targets: dropping other hand cards on
		# them moves those cards next to this one.
		b.set_drag_forwarding(_get_card_drag_data.bind(c, b),
			_can_drop_on_hand_card.bind(c), _drop_on_hand_card.bind(c))
	card_nodes[c] = b
	return b

func _card_style(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(7)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	return sb

func _panel_style(bg: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb

func _hover_variant(sb: StyleBoxFlat) -> StyleBoxFlat:
	var out: StyleBoxFlat = sb.duplicate()
	out.bg_color = Color(out.bg_color.r, out.bg_color.g, out.bg_color.b,
		minf(out.bg_color.a + 0.06, 1.0))
	out.border_color = Color(1, 1, 1, 0.6)
	return out

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _prune_selection() -> void:
	var in_hand := {}
	for c in gm.players[0].hand:
		in_hand[c] = true
	var meld_of := {}
	for m in gm.board.melds:
		for c in m.cards:
			meld_of[c] = m
	# Before opening, table cards can't be moved (groups staged from your own
	# hand excepted), so drop them from the selection too (e.g. after undoing
	# the move that had opened the turn).
	var board_locked := _is_human_turn() and not gm.current_player_is_open()
	for i in range(selected.size() - 1, -1, -1):
		var c := selected[i]
		if in_hand.has(c):
			continue
		if not meld_of.has(c):
			selected.remove_at(i)
		elif board_locked and not gm.is_own_staged_meld(meld_of[c]):
			selected.remove_at(i)

func _is_human_turn() -> bool:
	return not gm.is_game_over and not ai_running and gm.current_player() == gm.players[0]

## Cards in your hand are always usable on your turn. Table cards unlock once
## you have opened — except cards in a group staged from your own hand this
## turn, which stay movable so they can always be taken back.
func _card_is_interactive(meld: CardSet) -> bool:
	if not _is_human_turn():
		return false
	if meld == null:
		return true
	return gm.current_player_is_open() or gm.is_own_staged_meld(meld)

# --- Drag and drop ---------------------------------------------------------------

## Dragging a selected card drags the whole selection; dragging an unselected
## card drags just that card. Returns null (no drag) for disabled cards.
func _get_card_drag_data(_at_position: Vector2, c: Card, source: Button) -> Variant:
	if source.disabled:
		return null
	var cards: Array[Card] = []
	if selected.has(c):
		cards.assign(selected)
	else:
		cards.append(c)
	source.set_drag_preview(_make_drag_preview(cards))
	return {"type": DRAG_TYPE, "cards": cards}

func _make_drag_preview(cards: Array[Card]) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for c in Rules.display_order(cards):
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", _card_style(COL_SELECT_BG, COL_SELECT, 2))
		var lbl := Label.new()
		lbl.text = c.label()
		lbl.add_theme_font_size_override("font_size", CARD_FONT_SIZE)
		lbl.add_theme_color_override("font_color",
			COL_CARD_RED if RED_SUITS.has(c.suit) else COL_CARD_BLACK)
		chip.add_child(lbl)
		row.add_child(chip)
	row.modulate = Color(1, 1, 1, 0.9)
	return row

func _drag_cards(data: Variant) -> Array[Card]:
	var out: Array[Card] = []
	if data is Dictionary and data.get("type") == DRAG_TYPE:
		out.assign(data["cards"])
	return out

func _can_drop_on_meld(_at_position: Vector2, data: Variant, meld: CardSet) -> bool:
	if not _is_human_turn() or _drag_cards(data).is_empty():
		return false
	return gm.current_player_is_open() or gm.is_own_staged_meld(meld)

func _drop_on_meld(_at_position: Vector2, data: Variant, meld: CardSet) -> void:
	_play_on_meld(_drag_cards(data), meld)

func _can_drop_new_group(_at_position: Vector2, data: Variant) -> bool:
	return _is_human_turn() and not _drag_cards(data).is_empty()

func _drop_new_group(_at_position: Vector2, data: Variant) -> void:
	_stage_move(_drag_cards(data), null)

## The hand takes two kinds of drops: cards already in the hand (a reorder)
## and cards played to the table this turn (a return).
func _can_drop_on_hand(_at_position: Vector2, data: Variant) -> bool:
	if not _is_human_turn():
		return false
	var cards := _drag_cards(data)
	return _all_in_hand(cards) or gm.can_return_to_hand(cards)

func _drop_on_hand(_at_position: Vector2, data: Variant) -> void:
	var cards := _drag_cards(data)
	if _all_in_hand(cards):
		_reorder_hand(cards, gm.players[0].hand.size())
	else:
		_return_to_hand(cards)

func _can_drop_on_hand_card(at_position: Vector2, data: Variant, _target: Card) -> bool:
	return _can_drop_on_hand(at_position, data)

## Dropping hand cards on another hand card slots them next to it: left half
## of the card = before it, right half = after.
func _drop_on_hand_card(at_position: Vector2, data: Variant, target: Card) -> void:
	var cards := _drag_cards(data)
	if not _all_in_hand(cards):
		_return_to_hand(cards)
		return
	var idx := gm.players[0].hand.find(target)
	if idx == -1:
		return
	if at_position.x > CARD_SIZE.x / 2.0:
		idx += 1
	_reorder_hand(cards, idx)

func _all_in_hand(cards: Array[Card]) -> bool:
	if cards.is_empty():
		return false
	var hand := gm.players[0].hand
	for c in cards:
		if not hand.has(c):
			return false
	return true

## Move `cards` (all already in the hand) so they sit just before hand index
## `idx`, keeping their dragged order. Pure presentation — no engine move is
## staged and nothing becomes undoable.
func _reorder_hand(cards: Array[Card], idx: int) -> void:
	var hand := gm.players[0].hand
	var shift := 0
	for c in cards:
		var i := hand.find(c)
		if i != -1 and i < idx:
			shift += 1
	for c in cards:
		hand.erase(c)
	var insert_at := clampi(idx - shift, 0, hand.size())
	for i in cards.size():
		hand.insert(insert_at + i, cards[i])
	_refresh()

# --- Input handlers -----------------------------------------------------------

## Play cards onto an existing meld — but if a single natural card is played
## onto a meld whose joker stands for exactly that card, it becomes the joker
## swap: the real card takes the joker's place and the wildcard joins the hand.
func _play_on_meld(cards: Array[Card], meld: CardSet) -> void:
	if cards.size() == 1 and not cards[0].is_joker:
		var joker := _matching_joker(cards[0], meld)
		if joker != null:
			var err := gm.swap_joker(cards[0], joker, meld)
			selected.clear()
			if err == "":
				_log("You swapped %s for the joker." % cards[0].label())
				_set_status("Swapped — the joker is back in your hand as a wildcard.")
			else:
				_set_status(err)
			_refresh()
			return
	_stage_move(cards, meld)

func _matching_joker(c: Card, meld: CardSet) -> Card:
	for t in meld.cards:
		if t.is_joker and t.joker_rank == c.rank and t.joker_suit == c.suit:
			return t
	return null

## Right-clicking a joker on the table (when its group leaves it a choice)
## opens a menu of the cards it could stand for.
func _on_joker_gui_input(event: InputEvent, joker: Card, meld: CardSet) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		_show_joker_menu(joker, meld)

func _show_joker_menu(joker: Card, meld: CardSet) -> void:
	if not _card_is_interactive(meld):
		return
	Rules.assign_jokers(meld.cards)
	var alts := Rules.joker_alternatives(meld.cards)
	if alts.is_empty():
		return
	var menu := PopupMenu.new()
	add_child(menu)
	for i in alts.size():
		var alt: Dictionary = alts[i]
		menu.add_radio_check_item("Stands for %s" % _rep_text(alt["rank"], alt["suit"]), i)
		menu.set_item_checked(i,
			alt["rank"] == joker.joker_rank and alt["suit"] == joker.joker_suit)
	menu.id_pressed.connect(func(id: int) -> void:
		var alt: Dictionary = alts[id]
		joker.joker_pref_rank = alt["rank"]
		joker.joker_pref_suit = alt["suit"]
		_refresh())
	menu.popup_hide.connect(menu.queue_free)
	menu.position = Vector2i(get_global_mouse_position())
	menu.popup()

func _rep_text(rank: int, suit: String) -> String:
	return "%s%s" % [Card.RANK_NAMES.get(rank, str(rank)),
		Card.SUIT_SYMBOLS.get(suit, suit)]

## Stage a move through the engine (meld == null starts a new group) and show
## the engine's error, if any, in the status line.
func _stage_move(cards: Array[Card], meld: CardSet) -> void:
	if cards.is_empty():
		return
	var err := ""
	if meld == null:
		err = gm.move_cards_to_new_meld(cards)
	else:
		err = gm.add_cards_to_meld(cards, meld)
	selected.clear()
	_set_status(err)
	_refresh()

## Send cards the player laid down this turn back into their hand.
func _return_to_hand(cards: Array[Card]) -> void:
	if cards.is_empty():
		return
	var err := gm.return_cards_to_hand(cards)
	selected.clear()
	_set_status(err)
	_refresh()

func _on_card_toggled(pressed: bool, c: Card) -> void:
	if pressed:
		if not selected.has(c):
			selected.append(c)
	else:
		selected.erase(c)
	_refresh()

func _on_new_meld_pressed() -> void:
	_stage_move(selected.duplicate(), null)

func _on_add_to_meld_pressed(meld: CardSet) -> void:
	_play_on_meld(selected.duplicate(), meld)

func _on_sort_rank_pressed() -> void:
	gm.players[0].hand.sort_custom(func(a: Card, b: Card) -> bool:
		if a.is_joker != b.is_joker:
			return b.is_joker
		if a.rank != b.rank:
			return a.rank < b.rank
		return a.suit < b.suit)
	_refresh()

func _on_sort_suit_pressed() -> void:
	gm.players[0].hand.sort_custom(func(a: Card, b: Card) -> bool:
		if a.is_joker != b.is_joker:
			return b.is_joker
		if a.suit != b.suit:
			return a.suit < b.suit
		return a.rank < b.rank)
	_refresh()

func _on_return_pressed() -> void:
	_return_to_hand(selected.duplicate())

func _on_undo_action_pressed() -> void:
	selected.clear()
	if gm.undo_action():
		_set_status("Last action undone.")
	_refresh()

func _on_reset_pressed() -> void:
	selected.clear()
	gm.reset_turn()
	_set_status("Turn reset.")
	_refresh()

func _on_end_turn_pressed() -> void:
	var err := gm.commit_turn()
	if err != "":
		_set_status(err)
		_refresh()
		return
	_set_status("")
	_refresh()
	_run_ai_turns()

func _on_draw_pressed() -> void:
	selected.clear()
	gm.draw_and_end_turn()
	_refresh()
	_run_ai_turns()

# --- Engine signal handlers ----------------------------------------------------

func _on_turn_committed(p: PlayerState, cards_played: int) -> void:
	_log("%s played %d card(s)." % [p.display_name, cards_played])

func _on_card_drawn(p: PlayerState, card: Card) -> void:
	if p == gm.players[0]:
		_log("You drew %s." % card.label())
	else:
		_log("%s drew a card." % p.display_name)

func _on_player_passed(p: PlayerState) -> void:
	_log("%s passed (stock is empty)." % p.display_name)

func _on_game_over(winners: Array) -> void:
	var names := PackedStringArray()
	for p in winners:
		names.append(p.display_name)
	var who := ", ".join(names)
	_log("[b]Game over — winner: %s[/b]" % who)
	_set_status("Game over — %s wins. Press New game to play again." % who)

# --- AI driving ----------------------------------------------------------------

## Play out every queued enemy turn, one visible move at a time. Each move is
## staged through the same engine calls the human uses and its cards fly on
## screen from where they were to where they land. Highlights accumulate over
## the whole round of enemy turns and stay through the player's turn, only
## clearing when the enemies next start acting (or a new game begins).
func _run_ai_turns() -> void:
	if ai_running or gm.is_game_over:
		return
	ai_running = true
	var gen := game_generation
	var profile := AIProfile.new(ai_strength, ai_style)
	highlighted.clear()
	_refresh()
	while not gm.is_game_over and gm.current_player().is_opponent:
		var enemy := gm.current_player()
		_set_status("%s is thinking…" % enemy.display_name)
		_refresh()
		await get_tree().create_timer(AI_THINK_DELAY).timeout
		if gen != game_generation:
			return
		var played_any := false
		while true:
			var move: Dictionary = GreedyAI.plan_move(gm, profile)
			if move.is_empty():
				break
			var moved: Array[Card] = move["cards"]
			var sources := _capture_card_positions(enemy, moved)
			GreedyAI.apply_move(gm, move, profile)
			played_any = true
			for c in moved:
				highlighted[c] = true
			_log("%s %s." % [enemy.display_name, move["text"]])
			_refresh()
			await _animate_cards(moved, sources)
			if gen != game_generation:
				return
			await get_tree().create_timer(AI_MOVE_DELAY).timeout
			if gen != game_generation:
				return
		if played_any:
			var err := gm.commit_turn()
			if err != "":
				push_warning("AI staged an illegal turn (%s); drawing instead." % err)
				gm.draw_and_end_turn()
		else:
			gm.draw_and_end_turn()
		_refresh()
	ai_running = false
	if not gm.is_game_over:
		_set_status("Your turn. Drag cards onto a group or empty felt — "
			+ "or click to select, then use the + buttons.")
	_refresh()

# --- Enemy move animation --------------------------------------------------------

## Where each card is on screen right now: face-up cards report their button's
## position, cards still hidden in an enemy hand report the middle of that
## enemy's card backs. Must be called before the move is applied/refreshed.
func _capture_card_positions(enemy: PlayerState, cards: Array[Card]) -> Dictionary:
	var out := {}
	for c in cards:
		var node: Control = card_nodes.get(c)
		if node != null and is_instance_valid(node):
			out[c] = node.global_position
		else:
			out[c] = _enemy_hand_origin(enemy)
	return out

func _enemy_hand_origin(enemy: PlayerState) -> Vector2:
	var backs: Control = opponent_backs.get(enemy.player_id)
	if backs != null and is_instance_valid(backs):
		return backs.get_global_rect().get_center() - CARD_SIZE / 2.0
	return get_global_rect().get_center() - CARD_SIZE / 2.0

## Fly card faces from `sources` (Card -> screen position) to wherever the
## cards sit after the last refresh. Each destination button is hidden while
## its card is in flight, then revealed when the flight lands.
func _animate_cards(cards: Array[Card], sources: Dictionary) -> void:
	# The freshly rebuilt containers need a frame or two to lay out before
	# destination positions are meaningful.
	await get_tree().process_frame
	await get_tree().process_frame
	var last_tween: Tween = null
	for c in cards:
		var dest: Control = card_nodes.get(c)
		if dest == null or not is_instance_valid(dest) or not sources.has(c):
			continue
		var proxy := _make_card_face(c)
		anim_layer.add_child(proxy)
		proxy.global_position = sources[c]
		dest.modulate.a = 0.0
		var tw := proxy.create_tween()
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(proxy, "global_position", dest.global_position, AI_ANIM_TIME)
		tw.tween_callback(func() -> void:
			if is_instance_valid(dest):
				dest.modulate.a = 1.0
			proxy.queue_free())
		last_tween = tw
	if last_tween != null:
		await last_tween.finished

## A non-interactive card face used as an animation proxy; styled like the
## gold highlight the card will carry once it lands.
func _make_card_face(c: Card) -> Control:
	var face := PanelContainer.new()
	face.custom_minimum_size = CARD_SIZE
	face.size = CARD_SIZE
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_theme_stylebox_override("panel", _card_style(COL_HILITE_BG, COL_HILITE, 3))
	var lbl := Label.new()
	lbl.text = c.label()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", CARD_FONT_SIZE)
	lbl.add_theme_color_override("font_color",
		COL_CARD_RED if RED_SUITS.has(c.suit) else COL_CARD_BLACK)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(lbl)
	return face

# --- Misc ----------------------------------------------------------------------

func _set_status(msg: String) -> void:
	status_label.text = msg

func _log(msg: String) -> void:
	log_box.append_text(msg + "\n")
