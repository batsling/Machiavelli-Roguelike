class_name MainUIBuilder
extends RefCounted

## Builds MainUI's widget tree once at startup: the felt/seats/hand/action-row
## shell, the flying-card overlay, and the menu, settings and enemy-info pop-ups.
## Pure construction — it creates the nodes, stores the ones the controller
## refreshes into `ui`'s fields, and wires every button back to the controller's
## handlers. All behaviour (what those handlers do) stays on MainUI; this class
## only assembles the tree, keeping ~330 lines of `.new()`/`add_child`/`connect`
## boilerplate out of the controller. GDScript has no partial classes, so the
## builder reaches into `ui` directly — the construction-time mirror of how
## TableView reads `ui` state at refresh.

## Assemble the whole screen into `ui` and populate its node references.
func build(ui: MainUI) -> void:
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	var ui_theme := Theme.new()
	ui_theme.default_font_size = UITheme.UI_FONT_SIZE
	ui.theme = ui_theme
	# Paint the whole window in dark felt instead of the engine's gray.
	RenderingServer.set_default_clear_color(UITheme.COL_FELT_DARK)

	# The screen: one column of seats, felt and hand. The log opens over its left
	# side (see _build_log_panel) rather than taking room from it.
	ui.game_root = HBoxContainer.new()
	ui.game_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.game_root.add_theme_constant_override("separation", 10)
	ui.game_root.offset_left = 10
	ui.game_root.offset_top = 10
	ui.game_root.offset_right = -10
	ui.game_root.offset_bottom = -10
	ui.add_child(ui.game_root)
	var main_col := VBoxContainer.new()
	main_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_col.add_theme_constant_override("separation", 6)
	ui.game_root.add_child(main_col)

	# Top row: the log button and match status in the top-left corner, the first
	# enemy's seat (with their deck beside their cards) centered opposite you, and
	# the game menu in the top-right corner.
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 8)
	main_col.add_child(top_bar)
	ui.log_btn = Button.new()
	ui.log_btn.text = "Log"
	ui.log_btn.toggle_mode = true
	ui.log_btn.focus_mode = Control.FOCUS_NONE
	ui.log_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ui.log_btn.tooltip_text = "Show the game log over the left of the table"
	ui.log_btn.toggled.connect(ui._on_log_toggled)
	top_bar.add_child(ui.log_btn)
	# Round counter: one round is a full lap of the table (every player takes a
	# turn), ticking up when play returns to you.
	ui.round_label = Label.new()
	ui.round_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ui.round_label.add_theme_font_size_override("font_size", 18)
	ui.round_label.add_theme_color_override("font_color", UITheme.COL_CHIP_ACTIVE)
	top_bar.add_child(ui.round_label)
	# Lives and map progress beside it during a run; refresh_seats fills it.
	ui.lives_label = Label.new()
	ui.lives_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ui.lives_label.add_theme_font_size_override("font_size", 18)
	ui.lives_label.add_theme_color_override("font_color", UITheme.COL_LIFE)
	top_bar.add_child(ui.lives_label)
	# The round's turn order (Instances → You → each enemy, clockwise), with
	# whoever is acting lit; refresh_seats fills it.
	ui.turn_order_row = HBoxContainer.new()
	ui.turn_order_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ui.turn_order_row.add_theme_constant_override("separation", 6)
	ui.turn_order_row.mouse_filter = Control.MOUSE_FILTER_STOP
	top_bar.add_child(ui.turn_order_row)
	var top_pad_left := Control.new()
	top_pad_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(top_pad_left)
	ui.seat_top = _make_seat()
	top_bar.add_child(ui.seat_top)
	var top_pad_right := Control.new()
	top_pad_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(top_pad_right)
	_build_game_menu(ui, top_bar)

	# Middle row: the instances, left seat, the felt, right seat (hidden until a
	# 4th player).
	var mid_row := HBoxContainer.new()
	mid_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid_row.add_theme_constant_override("separation", 8)
	main_col.add_child(mid_row)
	# Instances: the match's rule cards in a column beside the felt, face up once
	# revealed and face down (with the round they turn up on) until then.
	# TableView fills it; hidden when the match has no instances.
	ui.instances_row = VBoxContainer.new()
	ui.instances_row.add_theme_constant_override("separation", 8)
	ui.instances_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mid_row.add_child(ui.instances_row)
	ui.seat_left = _make_seat()
	ui.seat_left.custom_minimum_size = Vector2(UITheme.SIDE_SEAT_WIDTH, 0)
	mid_row.add_child(ui.seat_left)

	# Table: green felt panel holding a flow of meld panels. The felt itself
	# (panel, scroll area and flow) accepts drops to start a new group.
	var table_panel := PanelContainer.new()
	table_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table_panel.add_theme_stylebox_override("panel", CardRenderer.panel_style(UITheme.COL_FELT, 10))
	mid_row.add_child(table_panel)
	var table_col := VBoxContainer.new()
	table_col.add_theme_constant_override("separation", 4)
	table_panel.add_child(table_col)

	# Table header: a title, the suit highlighter, and buttons that reorder the
	# groups on the felt so a crowded table is easy to read. Sort lays straights
	# out first (by colour, then starting rank) and sets after (by rank);
	# Randomize keeps each group intact but shuffles where the groups sit. The
	# highlighter (♥ ♦ ♣ ♠) outlines that suit across the whole table AND your
	# hand at once, so a colour can be picked out of everything in play at a glance.
	var table_top := HBoxContainer.new()
	table_top.add_theme_constant_override("separation", 8)
	table_col.add_child(table_top)
	# The status line — what to do right now — heads the table, where the eye
	# already is.
	ui.status_label = Label.new()
	ui.status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.status_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ui.status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui.status_label.add_theme_font_size_override("font_size", 16)
	ui.status_label.add_theme_color_override("font_color", UITheme.COL_CHIP_ACTIVE)
	table_top.add_child(ui.status_label)
	# Suit highlighter: hovering a suit outlines those cards everywhere in play
	# (hand and table) and fades the rest.
	var highlight_hint := Label.new()
	highlight_hint.text = "Highlight suit:"
	highlight_hint.add_theme_font_size_override("font_size", 12)
	highlight_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	highlight_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	table_top.add_child(highlight_hint)
	for suit in ["hearts", "diamonds", "clubs", "spades"]:
		table_top.add_child(ui._make_suit_filter_button(suit))
	ui.sort_board_btn = Button.new()
	ui.sort_board_btn.text = "Sort"
	ui.sort_board_btn.tooltip_text = "Reorder the groups on the table: straights first " \
		+ "(by colour, then starting rank), then sets (by rank)"
	ui.sort_board_btn.focus_mode = Control.FOCUS_NONE
	ui.sort_board_btn.pressed.connect(ui._on_sort_board_pressed)
	table_top.add_child(ui.sort_board_btn)
	ui.randomize_board_btn = Button.new()
	ui.randomize_board_btn.text = "Randomize"
	ui.randomize_board_btn.tooltip_text = "Shuffle where the groups sit on the table, " \
		+ "keeping each group together"
	ui.randomize_board_btn.focus_mode = Control.FOCUS_NONE
	ui.randomize_board_btn.pressed.connect(ui._on_randomize_board_pressed)
	table_top.add_child(ui.randomize_board_btn)

	var table_scroll := ScrollContainer.new()
	table_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	table_col.add_child(table_scroll)
	ui.board_flow = Control.new()
	ui.board_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.board_flow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui.board_flow.mouse_filter = Control.MOUSE_FILTER_PASS
	ui.board_flow.clip_contents = true
	table_scroll.add_child(ui.board_flow)
	for zone: Control in [table_panel, table_scroll, ui.board_flow]:
		zone.set_drag_forwarding(Callable(), ui._can_drop_new_group, ui._drop_new_group)
		zone.gui_input.connect(ui._on_background_gui_input)

	ui.seat_right = _make_seat()
	ui.seat_right.custom_minimum_size = Vector2(UITheme.SIDE_SEAT_WIDTH, 0)
	mid_row.add_child(ui.seat_right)

	# Bottom row: your hand, then your deck and the turn controls on its right.
	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 10)
	main_col.add_child(bottom_row)

	# Hand: darker felt panel at the bottom. The whole panel accepts drops so
	# cards played this turn can be dragged back into the hand.
	ui.hand_panel = PanelContainer.new()
	ui.hand_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_row.add_child(ui.hand_panel)
	var hand_col := VBoxContainer.new()
	hand_col.add_theme_constant_override("separation", 4)
	ui.hand_panel.add_child(hand_col)
	var hand_top := HBoxContainer.new()
	hand_top.add_theme_constant_override("separation", 8)
	hand_col.add_child(hand_top)
	ui.hand_title = Label.new()
	ui.hand_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ui.hand_title.add_theme_font_size_override("font_size", 15)
	ui.hand_title.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	hand_top.add_child(ui.hand_title)
	# What you have selected, beside the hand's title.
	ui.selection_label = Label.new()
	ui.selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.selection_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ui.selection_label.clip_text = true
	ui.selection_label.add_theme_font_size_override("font_size", 14)
	ui.selection_label.add_theme_color_override("font_color", UITheme.COL_SELECT_BG)
	hand_top.add_child(ui.selection_label)

	# Your own ultimate meter sits in the hand header; refresh_hand fills it (a
	# label + bar) when the meter is enabled, and leaves it empty otherwise.
	ui.hand_meter_slot = HBoxContainer.new()
	ui.hand_meter_slot.add_theme_constant_override("separation", 6)
	ui.hand_meter_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hand_top.add_child(ui.hand_meter_slot)
	# The coins your staged turn will earn when you end it (combo coins, Coin
	# Rush); refresh_hand fills it, blank while there are none.
	ui.coin_label = Label.new()
	ui.coin_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ui.coin_label.add_theme_font_size_override("font_size", 15)
	ui.coin_label.add_theme_color_override("font_color", UITheme.COL_COIN)
	hand_top.add_child(ui.coin_label)
	# Your energy for the turn: a label + pips, filled by refresh_hand when
	# energy is on (a roguelike run) and left empty otherwise.
	ui.energy_slot = HBoxContainer.new()
	ui.energy_slot.add_theme_constant_override("separation", 4)
	ui.energy_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hand_top.add_child(ui.energy_slot)

	var hand_row := HBoxContainer.new()
	hand_row.add_theme_constant_override("separation", 8)
	hand_col.add_child(hand_row)
	# Your discard pile at the hand's left: everything discarded or destroyed
	# from your deck. Click it to see the cards; TableView fills its count.
	ui.discard_btn = _make_discard_pile_button()
	ui.discard_btn.pressed.connect(ui._on_discard_pressed)
	hand_row.add_child(ui.discard_btn)
	ui.hand_box = HFlowContainer.new()
	ui.hand_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.hand_box.add_theme_constant_override("h_separation", 4)
	ui.hand_box.add_theme_constant_override("v_separation", 4)
	hand_row.add_child(ui.hand_box)
	# Hand sort buttons, small icons at the hand's right edge: the hand keeps
	# whatever order you give it, but these lay it out the two plain ways players
	# read a hand — by rank (increasing, left to right) or by suit (reds then
	# blacks, rank order within). Jokers sort last.
	var sort_col := VBoxContainer.new()
	sort_col.add_theme_constant_override("separation", 4)
	sort_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hand_row.add_child(sort_col)
	sort_col.add_child(_make_sort_icon("A–K",
		"Sort your hand by rank, increasing left to right (jokers last)",
		ui._on_sort_rank_pressed))
	sort_col.add_child(_make_sort_icon("♥♠",
		"Sort your hand by suit, reds then blacks (jokers last)",
		ui._on_sort_suit_pressed))
	for zone: Control in [ui.hand_panel, hand_col, hand_top, hand_row, ui.hand_title,
			ui.selection_label, ui.hand_box]:
		zone.set_drag_forwarding(Callable(), ui._can_drop_on_hand, ui._drop_on_hand)
		zone.gui_input.connect(ui._on_background_gui_input)

	# Right of the hand: your deck, which is the Draw button (if you won't or
	# can't play, click it to draw and end your turn), and the turn controls
	# beside it. The deck's top card shows left of it when that card's status is
	# public (a glass top shows your next draw). TableView fills the pile's count.
	var turn_box := HBoxContainer.new()
	turn_box.add_theme_constant_override("separation", 10)
	turn_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom_row.add_child(turn_box)
	ui.stock_top_slot = HBoxContainer.new()
	ui.stock_top_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	turn_box.add_child(ui.stock_top_slot)
	ui.draw_btn = _make_deck_pile_button()
	ui.draw_btn.pressed.connect(ui._on_draw_pressed)
	turn_box.add_child(ui.draw_btn)
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 4)
	controls.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	turn_box.add_child(controls)

	# Confirms the cards picked for an instance's choice (Cycle, Gift); shown only
	# while you owe one.
	ui.choice_btn = Button.new()
	ui.choice_btn.visible = false
	ui.choice_btn.pressed.connect(ui._on_choice_confirm_pressed)
	controls.add_child(ui.choice_btn)

	# The main action. Ending the turn needs a card played from your hand; with
	# nothing to play, draw from your deck (the pile beside it) instead.
	ui.end_turn_btn = _make_primary_button("End turn")
	ui.end_turn_btn.pressed.connect(ui._on_end_turn_pressed)
	controls.add_child(ui.end_turn_btn)

	# Once a match is over: Back to map / New run / New game. Mid-match restarts
	# live in the game menu instead.
	ui.new_game_btn = _make_primary_button("New game")
	ui.new_game_btn.visible = false
	ui.new_game_btn.pressed.connect(ui._on_new_game_pressed)
	controls.add_child(ui.new_game_btn)

	var undo_row := HBoxContainer.new()
	undo_row.add_theme_constant_override("separation", 4)
	controls.add_child(undo_row)
	ui.undo_action_btn = _make_small_button("Undo action",
		"Take back only the last move you staged this turn")
	ui.undo_action_btn.pressed.connect(ui._on_undo_action_pressed)
	undo_row.add_child(ui.undo_action_btn)
	ui.reset_btn = _make_small_button("Undo turn", "Take back everything staged this turn")
	ui.reset_btn.pressed.connect(ui._on_reset_pressed)
	undo_row.add_child(ui.reset_btn)
	ui.return_btn = _make_small_button("Return to hand",
		"Put the selected cards you played this turn back in your hand")
	ui.return_btn.pressed.connect(ui._on_return_pressed)
	controls.add_child(ui.return_btn)

	_build_log_panel(ui)

	# Overlay for the flying-card animations; never intercepts the mouse.
	ui.anim_layer = Control.new()
	ui.anim_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.anim_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(ui.anim_layer)
	ui.animator = EnemyMoveAnimator.new()
	ui.add_child(ui.animator)
	ui.animator.setup(ui.anim_layer, ui)

	_build_opponent_hand_overlay(ui)

	# The map and the menu sit above everything (including in-flight card
	# animations).
	_build_map(ui)
	_build_menu(ui)
	_build_settings_dialog(ui)
	_build_enemy_info_dialog(ui)
	_build_discard_dialog(ui)

## The game log, opened by the Log button: a panel laid over the left side of
## the screen (below the top bar, above your hand) so opening it never squeezes
## the table, and the hand and turn buttons stay clear. Hidden until opened;
## MainUI keeps its bottom edge above the hand.
func _build_log_panel(ui: MainUI) -> void:
	ui.log_panel = PanelContainer.new()
	ui.log_panel.visible = false
	ui.log_panel.anchor_left = 0
	ui.log_panel.anchor_right = 0
	ui.log_panel.anchor_top = 0
	ui.log_panel.anchor_bottom = 1
	ui.log_panel.offset_left = 10
	ui.log_panel.offset_right = 10 + UITheme.LOG_PANEL_WIDTH
	ui.log_panel.offset_top = UITheme.LOG_PANEL_TOP
	ui.log_panel.offset_bottom = -200
	var sb := CardRenderer.panel_style(UITheme.COL_LOG_PANEL, 10)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(1)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 12
	ui.log_panel.add_theme_stylebox_override("panel", sb)
	ui.add_child(ui.log_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	ui.log_panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := Label.new()
	title.text = "Log"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	head.add_child(title)
	var close := Button.new()
	close.text = "✕"
	close.tooltip_text = "Hide the log"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: ui.log_btn.button_pressed = false)
	head.add_child(close)
	ui.log_box = RichTextLabel.new()
	ui.log_box.bbcode_enabled = true
	ui.log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui.log_box.scroll_following = true
	ui.log_box.fit_content = false
	ui.log_box.add_theme_font_size_override("normal_font_size", 14)
	ui.log_box.add_theme_font_size_override("bold_font_size", 14)
	col.add_child(ui.log_box)

## A small icon button for the hand's sort column.
func _make_sort_icon(text: String, tip: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(40, 32)
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(on_press)
	return b

## The turn's main button: big, and gold while it can be pressed.
func _make_primary_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = UITheme.PRIMARY_BUTTON_SIZE
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	var states := {
		"normal": UITheme.COL_CHIP_ACTIVE,
		"hover": UITheme.COL_CHIP_ACTIVE.lightened(0.15),
		"pressed": UITheme.COL_CHIP_ACTIVE.darkened(0.15),
		"disabled": Color(1, 1, 1, 0.08),
	}
	for state: String in states:
		var sb := CardRenderer.panel_style(states[state], 8)
		b.add_theme_stylebox_override(state, sb)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(state, UITheme.COL_CARD_BLACK)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))
	return b

## A secondary turn control (undo, return to hand): small and quiet.
func _make_small_button(text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 13)
	return b

## The ☰ Menu button in the top-left corner: Settings, restarting (the run, or
## a new sandbox game) and the main menu, kept out of the action row.
func _build_game_menu(ui: MainUI, parent: Control) -> void:
	ui.game_menu_btn = MenuButton.new()
	ui.game_menu_btn.text = "☰ Menu"
	ui.game_menu_btn.flat = false
	ui.game_menu_btn.focus_mode = Control.FOCUS_NONE
	ui.game_menu_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ui.game_menu_btn.tooltip_text = "Settings, restart, and the main menu"
	var popup := ui.game_menu_btn.get_popup()
	popup.add_item("Settings", MainUI.GameMenu.SETTINGS)
	popup.add_item("Restart run", MainUI.GameMenu.RESTART)
	popup.add_separator()
	popup.add_item("Main menu", MainUI.GameMenu.MAIN_MENU)
	popup.id_pressed.connect(ui._on_game_menu_id_pressed)
	parent.add_child(ui.game_menu_btn)

## Your deck as a face-down pile you click to draw: a card back with the cards
## left (and the action) written on it.
func _make_deck_pile_button() -> Button:
	var pile := Button.new()
	pile.custom_minimum_size = UITheme.CARD_SIZE
	pile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pile.focus_mode = Control.FOCUS_NONE
	pile.add_theme_font_size_override("font_size", 15)
	var states := {
		"normal": UITheme.COL_CARD_BACK,
		"hover": UITheme.COL_CARD_BACK.lightened(0.18),
		"pressed": UITheme.COL_CARD_BACK.darkened(0.2),
		"disabled": UITheme.COL_CARD_BACK.darkened(0.35),
	}
	for state: String in states:
		var sb := StyleBoxFlat.new()
		sb.bg_color = states[state]
		sb.border_color = UITheme.COL_CHIP_ACTIVE if state == "hover" \
			else UITheme.COL_CARD_BACK_EDGE
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		pile.add_theme_stylebox_override(state, sb)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		pile.add_theme_color_override(state, Color.WHITE)
	pile.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.45))
	return pile

## A plain centered seat column (an opponent's name chip + card backs go here).
func _make_seat() -> VBoxContainer:
	var seat := VBoxContainer.new()
	seat.alignment = BoxContainer.ALIGNMENT_CENTER
	seat.add_theme_constant_override("separation", 6)
	return seat

## Your discard pile as a face-up pile: a pale card with the count on it.
func _make_discard_pile_button() -> Button:
	var pile := Button.new()
	pile.custom_minimum_size = UITheme.CARD_SIZE
	pile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pile.focus_mode = Control.FOCUS_NONE
	pile.add_theme_font_size_override("font_size", 14)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = UITheme.COL_DISCARD_PILE.lightened(0.12 if state == "hover" else 0.0)
		sb.border_color = UITheme.COL_CHIP_ACTIVE if state == "hover" \
			else Color(1, 1, 1, 0.35)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		pile.add_theme_stylebox_override(state, sb)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		pile.add_theme_color_override(state, Color(1, 1, 1, 0.85))
	return pile

## The pop-up listing the cards in your discard pile, opened from the pile.
func _build_discard_dialog(ui: MainUI) -> void:
	ui.discard_dialog = AcceptDialog.new()
	ui.discard_dialog.title = "Your discard pile"
	ui.discard_dialog.ok_button_text = "Close"
	ui.add_child(ui.discard_dialog)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(620, 0)
	col.add_theme_constant_override("separation", 8)
	ui.discard_dialog.add_child(col)
	ui.discard_note = Label.new()
	ui.discard_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A wrapping label needs a width, or it measures itself absurdly tall.
	ui.discard_note.custom_minimum_size = Vector2(620, 0)
	col.add_child(ui.discard_note)
	# A grid, not a flow: a flow measures itself one card per row before it is
	# laid out, which makes the pop-up far too tall.
	ui.discard_body = GridContainer.new()
	ui.discard_body.columns = 10
	ui.discard_body.add_theme_constant_override("h_separation", 6)
	ui.discard_body.add_theme_constant_override("v_separation", 6)
	col.add_child(ui.discard_body)

## A small pop-up describing an opponent: its mechanic (in a roguelike round)
## and the AI brain it is running. Opened by the "Info" button on its name chip.
func _build_enemy_info_dialog(ui: MainUI) -> void:
	ui.enemy_info_dialog = AcceptDialog.new()
	ui.enemy_info_dialog.title = "Enemy info"
	ui.enemy_info_dialog.ok_button_text = "Close"
	ui.add_child(ui.enemy_info_dialog)
	ui.enemy_info_body = RichTextLabel.new()
	ui.enemy_info_body.bbcode_enabled = true
	ui.enemy_info_body.fit_content = true
	ui.enemy_info_body.custom_minimum_size = Vector2(440, 120)
	ui.enemy_info_dialog.add_child(ui.enemy_info_body)

## The run map, hidden until a run starts. Like the menu it owns no game state:
## picking a node or Menu is handed straight to the controller.
func _build_map(ui: MainUI) -> void:
	ui.map_layer = MapScreen.new()
	ui.map_layer.visible = false
	ui.add_child(ui.map_layer)
	ui.map_layer.node_chosen.connect(ui._on_map_node_chosen)
	ui.map_layer.menu_requested.connect(ui._show_menu)

## Instantiate the menu scene and wire each button's intent signal to the
## controller. The menu itself owns no game state.
func _build_menu(ui: MainUI) -> void:
	ui.menu_layer = preload("res://scenes/ui/menu_screen.tscn").instantiate()
	ui.add_child(ui.menu_layer)
	ui.menu_layer.play_vanilla_requested.connect(ui._on_play_vanilla_pressed)
	ui.menu_layer.play_rogue_requested.connect(ui._on_play_rogue_pressed)
	ui.menu_layer.resume_requested.connect(ui._on_resume_pressed)
	ui.menu_layer.settings_requested.connect(ui._on_settings_pressed)
	ui.menu_layer.quit_requested.connect(ui._on_quit_pressed)

## Instantiate the settings scene against the shared settings model. Sandbox
## rules that take effect mid-game are pushed onto the running game by
## _apply_live_settings whenever the dialog reports a change.
func _build_settings_dialog(ui: MainUI) -> void:
	ui.settings_dialog = preload("res://scenes/ui/settings_dialog.tscn").instantiate()
	ui.add_child(ui.settings_dialog)
	ui.settings_dialog.setup(ui.settings, ui._apply_live_settings)

## The enlarged opponent-hand reveal: a full-screen centering layer (so it always
## lands in the middle whatever the hand's size) holding a titled panel of
## enlarged card backs. Non-interactive throughout — it only reveals, never
## catches the mouse — and hidden until _show_opponent_hand fills and shows it.
func _build_opponent_hand_overlay(ui: MainUI) -> void:
	ui.opponent_hand_overlay = CenterContainer.new()
	ui.opponent_hand_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.opponent_hand_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.opponent_hand_overlay.visible = false
	ui.add_child(ui.opponent_hand_overlay)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := CardRenderer.panel_style(UITheme.COL_OPP_HAND_BG, 12)
	sb.border_color = UITheme.COL_GLASS_EDGE
	sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)
	ui.opponent_hand_overlay.add_child(panel)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	ui.opponent_hand_title = Label.new()
	ui.opponent_hand_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.opponent_hand_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.opponent_hand_title.add_theme_font_size_override("font_size", 15)
	ui.opponent_hand_title.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	col.add_child(ui.opponent_hand_title)
	ui.opponent_hand_body = HFlowContainer.new()
	ui.opponent_hand_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.opponent_hand_body.add_theme_constant_override("h_separation", 6)
	ui.opponent_hand_body.add_theme_constant_override("v_separation", 6)
	col.add_child(ui.opponent_hand_body)
