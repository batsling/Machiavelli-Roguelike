extends Control

## Playable UI for vanilla Machiavelli, built entirely in code so the scene
## file stays trivial.
##
## How to play: on your turn, click cards to select them — from your hand AND
## from any group on the table (rearranging the table is the heart of the
## game). Selected cards lift and turn blue. Then click a group's "+" button
## to move them there, or the "+ New group" zone to start a fresh group. The
## table only has to be valid when you press "End turn"; "Undo turn" puts
## everything back. If you can't (or won't) play, "Draw & end turn".
##
## Enemy turns play out visibly: each move the AI makes is applied one at a
## time with a pause, and every card it touched stays highlighted in gold
## until the next enemy acts — so you can see exactly what was laid down or
## taken from the table.

const AI_THINK_DELAY := 0.6
const AI_MOVE_DELAY := 0.9
const RED_SUITS := ["hearts", "diamonds"]

const COL_FELT := Color(0.09, 0.30, 0.19)
const COL_FELT_DARK := Color(0.07, 0.22, 0.14)
const COL_CARD_BG := Color(0.97, 0.96, 0.91)
const COL_CARD_BORDER := Color(0.60, 0.56, 0.46)
const COL_CARD_RED := Color(0.78, 0.13, 0.16)
const COL_CARD_BLACK := Color(0.10, 0.10, 0.13)
const COL_SELECT := Color(0.20, 0.55, 0.95)
const COL_SELECT_BG := Color(0.84, 0.91, 1.0)
const COL_HILITE := Color(0.93, 0.72, 0.13)
const COL_HILITE_BG := Color(1.0, 0.94, 0.75)
const COL_MELD_OK := Color(0.35, 0.75, 0.45)
const COL_MELD_BAD := Color(0.92, 0.35, 0.30)
const COL_CHIP_BG := Color(0.13, 0.14, 0.17)
const COL_CHIP_ACTIVE := Color(0.93, 0.72, 0.13)

var gm: GameManager
var selected: Array[Card] = []
var highlighted := {}  # Card -> true; cards the last enemy touched
var ai_running := false
# Bumped on every new game so a suspended AI coroutine from the previous game
# notices on resume and bails out instead of acting on the fresh state.
var game_generation := 0

var players_box: HBoxContainer
var stock_label: Label
var status_label: Label
var log_box: RichTextLabel
var board_flow: HFlowContainer
var hand_box: HFlowContainer
var hand_title: Label
var selection_label: Label
var reset_btn: Button
var end_turn_btn: Button
var draw_btn: Button
var new_game_btn: Button

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
	gm.setup(["You", "Rosso", "Nero"])
	log_box.clear()
	_set_status("Your turn. Click cards to select, then place them — or draw.")
	_log("New game: 13 cards each, double deck, no jokers.")
	_refresh()

# --- Layout -------------------------------------------------------------------

func _build_layout() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	root.offset_left = 12
	root.offset_top = 12
	root.offset_right = -12
	root.offset_bottom = -12
	add_child(root)

	# Top bar: player chips + stock count.
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 8)
	root.add_child(top_bar)
	players_box = HBoxContainer.new()
	players_box.add_theme_constant_override("separation", 8)
	players_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(players_box)
	stock_label = Label.new()
	top_bar.add_child(stock_label)

	# Table: green felt panel holding a flow of meld panels.
	var table_panel := PanelContainer.new()
	table_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table_panel.add_theme_stylebox_override("panel", _panel_style(COL_FELT, 10))
	root.add_child(table_panel)
	var table_scroll := ScrollContainer.new()
	table_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	table_panel.add_child(table_scroll)
	board_flow = HFlowContainer.new()
	board_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_flow.add_theme_constant_override("h_separation", 10)
	board_flow.add_theme_constant_override("v_separation", 10)
	table_scroll.add_child(board_flow)

	# Hand: darker felt panel at the bottom.
	var hand_panel := PanelContainer.new()
	hand_panel.add_theme_stylebox_override("panel", _panel_style(COL_FELT_DARK, 10))
	root.add_child(hand_panel)
	var hand_col := VBoxContainer.new()
	hand_col.add_theme_constant_override("separation", 4)
	hand_panel.add_child(hand_col)
	hand_title = Label.new()
	hand_title.add_theme_font_size_override("font_size", 13)
	hand_title.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	hand_col.add_child(hand_title)
	hand_box = HFlowContainer.new()
	hand_box.add_theme_constant_override("h_separation", 4)
	hand_box.add_theme_constant_override("v_separation", 4)
	hand_col.add_child(hand_box)

	# Action row.
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	root.add_child(actions)

	selection_label = Label.new()
	selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(selection_label)

	reset_btn = Button.new()
	reset_btn.text = "Undo turn"
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

	new_game_btn = Button.new()
	new_game_btn.text = "New game"
	new_game_btn.pressed.connect(_new_game)
	actions.add_child(new_game_btn)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status_label)

	log_box = RichTextLabel.new()
	log_box.custom_minimum_size = Vector2(0, 100)
	log_box.scroll_following = true
	log_box.fit_content = false
	root.add_child(log_box)

# --- Refresh ------------------------------------------------------------------

func _refresh() -> void:
	_prune_selection()
	_refresh_players()
	_refresh_board()
	_refresh_hand()
	_refresh_buttons()

func _refresh_players() -> void:
	_clear_children(players_box)
	for p in gm.players:
		players_box.add_child(_make_player_chip(p))
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
	lbl.text = "%s%s — %d cards" % [marker, p.display_name, p.hand.size()]
	if is_current:
		lbl.add_theme_color_override("font_color", COL_CHIP_ACTIVE)
	chip.add_child(lbl)
	return chip

func _refresh_board() -> void:
	_clear_children(board_flow)
	if gm.board.melds.is_empty():
		var empty := Label.new()
		empty.text = "The table is empty — lay down the first group."
		empty.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
		board_flow.add_child(empty)
	for meld in gm.board.melds:
		board_flow.add_child(_make_meld_panel(meld))
	board_flow.add_child(_make_new_group_zone())

func _make_meld_panel(meld: CardSet) -> PanelContainer:
	var panel := PanelContainer.new()
	var valid := meld.is_valid()
	var sb := _panel_style(Color(1, 1, 1, 0.06), 10)
	sb.border_color = COL_MELD_OK if valid else COL_MELD_BAD
	sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)
	if not valid:
		panel.tooltip_text = "Not a valid group yet — fix it before ending your turn."
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	panel.add_child(row)
	for c in Rules.display_order(meld.cards):
		row.add_child(_make_card_button(c))
	var add_btn := Button.new()
	add_btn.text = "+"
	add_btn.tooltip_text = "Move selected cards into this group"
	add_btn.custom_minimum_size = Vector2(34, 76)
	add_btn.disabled = selected.is_empty() or not _is_human_turn()
	add_btn.pressed.connect(_on_add_to_meld_pressed.bind(meld))
	row.add_child(add_btn)
	return panel

func _make_new_group_zone() -> Button:
	var zone := Button.new()
	zone.text = "+ New group"
	zone.tooltip_text = "Move selected cards into a brand-new group"
	zone.custom_minimum_size = Vector2(110, 92)
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
	return zone

func _refresh_hand() -> void:
	_clear_children(hand_box)
	var hand := gm.players[0].hand
	hand_title.text = "Your hand (%d)" % hand.size()
	for c in Rules.display_order(hand):
		hand_box.add_child(_make_card_button(c))

func _refresh_buttons() -> void:
	var human_turn := _is_human_turn()
	reset_btn.disabled = not human_turn
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

func _make_card_button(c: Card) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.text = c.label()
	b.button_pressed = selected.has(c)
	b.custom_minimum_size = Vector2(56, 76)
	b.disabled = not _is_human_turn()
	b.add_theme_font_size_override("font_size", 22)
	b.focus_mode = Control.FOCUS_NONE

	var font_col := COL_CARD_RED if RED_SUITS.has(c.suit) else COL_CARD_BLACK
	for state in ["font_color", "font_pressed_color", "font_hover_color",
			"font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, font_col)
	b.add_theme_color_override("font_disabled_color", Color(font_col, 0.75))

	var bg := COL_CARD_BG
	var border := COL_CARD_BORDER
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
	return b

func _card_style(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(7)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
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
	var reachable := {}
	for c in gm.players[0].hand:
		reachable[c] = true
	for c in gm.board.all_cards():
		reachable[c] = true
	for i in range(selected.size() - 1, -1, -1):
		if not reachable.has(selected[i]):
			selected.remove_at(i)

func _is_human_turn() -> bool:
	return not gm.is_game_over and not ai_running and gm.current_player() == gm.players[0]

# --- Input handlers -----------------------------------------------------------

func _on_card_toggled(pressed: bool, c: Card) -> void:
	if pressed:
		if not selected.has(c):
			selected.append(c)
	else:
		selected.erase(c)
	_refresh()

func _on_new_meld_pressed() -> void:
	gm.move_cards_to_new_meld(selected.duplicate())
	selected.clear()
	_refresh()

func _on_add_to_meld_pressed(meld: CardSet) -> void:
	gm.add_cards_to_meld(selected.duplicate(), meld)
	selected.clear()
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
## staged through the same engine calls the human uses, refreshed on screen,
## and its cards highlighted in gold; the highlight persists until the next
## enemy starts acting (or a new game begins).
func _run_ai_turns() -> void:
	if ai_running or gm.is_game_over:
		return
	ai_running = true
	var gen := game_generation
	_refresh()
	while not gm.is_game_over and gm.current_player().is_opponent:
		var enemy := gm.current_player()
		highlighted.clear()
		_set_status("%s is thinking…" % enemy.display_name)
		_refresh()
		await get_tree().create_timer(AI_THINK_DELAY).timeout
		if gen != game_generation:
			return
		var played_any := false
		while true:
			var move: Dictionary = GreedyAI.plan_move(gm)
			if move.is_empty():
				break
			GreedyAI.apply_move(gm, move)
			played_any = true
			for c in move["cards"]:
				highlighted[c] = true
			_log("%s %s." % [enemy.display_name, move["text"]])
			_refresh()
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
		_set_status("Your turn. Click cards (hand or table) to select, then click a group's + or “+ New group”.")
	_refresh()

# --- Misc ----------------------------------------------------------------------

func _set_status(msg: String) -> void:
	status_label.text = msg

func _log(msg: String) -> void:
	log_box.append_text(msg + "\n")
