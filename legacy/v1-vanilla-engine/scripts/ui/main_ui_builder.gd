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

	ui.game_root = VBoxContainer.new()
	ui.game_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.game_root.add_theme_constant_override("separation", 6)
	ui.game_root.offset_left = 10
	ui.game_root.offset_top = 10
	ui.game_root.offset_right = -10
	ui.game_root.offset_bottom = -10
	ui.add_child(ui.game_root)

	# Top row: the first enemy's seat, centered directly opposite you, with the
	# stock count tucked into the corner.
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 8)
	ui.game_root.add_child(top_bar)
	# Round counter tucked into the top-left corner: one round is a full lap of
	# the table (every player takes a turn), ticking up when play returns to you.
	ui.round_label = Label.new()
	ui.round_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ui.round_label.add_theme_font_size_override("font_size", 18)
	ui.round_label.add_theme_color_override("font_color", UITheme.COL_CHIP_ACTIVE)
	top_bar.add_child(ui.round_label)
	var top_pad_left := Control.new()
	top_pad_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(top_pad_left)
	ui.seat_top = _make_seat()
	top_bar.add_child(ui.seat_top)
	var top_pad_right := Control.new()
	top_pad_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(top_pad_right)
	# Stock corner: the count, plus the top card of the stock when it is glass
	# (a glass top is public — everyone can see the next draw).
	var stock_box := HBoxContainer.new()
	stock_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	stock_box.add_theme_constant_override("separation", 6)
	top_bar.add_child(stock_box)
	ui.stock_label = Label.new()
	ui.stock_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stock_box.add_child(ui.stock_label)
	ui.stock_top_slot = HBoxContainer.new()
	stock_box.add_child(ui.stock_top_slot)
	# The face-up discard pile sits just after the stock, appearing only once a
	# card has been discarded (the Billionaire's Riichi).
	ui.discard_slot = HBoxContainer.new()
	ui.discard_slot.add_theme_constant_override("separation", 6)
	stock_box.add_child(ui.discard_slot)

	# Middle row: left seat, the felt, right seat (hidden until a 4th player).
	var mid_row := HBoxContainer.new()
	mid_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid_row.add_theme_constant_override("separation", 8)
	ui.game_root.add_child(mid_row)
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
	var table_title := Label.new()
	table_title.text = "Table"
	table_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table_title.add_theme_font_size_override("font_size", 15)
	table_title.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	table_top.add_child(table_title)
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

	# Hand: darker felt panel at the bottom. The whole panel accepts drops so
	# cards played this turn can be dragged back into the hand.
	ui.hand_panel = PanelContainer.new()
	ui.game_root.add_child(ui.hand_panel)
	var hand_col := VBoxContainer.new()
	hand_col.add_theme_constant_override("separation", 4)
	ui.hand_panel.add_child(hand_col)
	var hand_top := HBoxContainer.new()
	hand_top.add_theme_constant_override("separation", 8)
	hand_col.add_child(hand_top)
	ui.hand_title = Label.new()
	ui.hand_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.hand_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ui.hand_title.add_theme_font_size_override("font_size", 15)
	ui.hand_title.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	hand_top.add_child(ui.hand_title)

	# Your own ultimate meter sits in the hand header; refresh_hand fills it (a
	# label + bar) when the meter is enabled, and leaves it empty otherwise.
	ui.hand_meter_slot = HBoxContainer.new()
	ui.hand_meter_slot.add_theme_constant_override("separation", 6)
	ui.hand_meter_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hand_top.add_child(ui.hand_meter_slot)

	# Hand sort buttons: the hand keeps whatever order you give it, but these lay
	# it out the two plain ways players read a hand — by rank (increasing, left to
	# right) or by suit (reds then blacks, rank order within). Jokers sort last.
	var sort_row := HBoxContainer.new()
	sort_row.add_theme_constant_override("separation", 4)
	sort_row.alignment = BoxContainer.ALIGNMENT_END
	hand_top.add_child(sort_row)
	var sort_rank_btn := Button.new()
	sort_rank_btn.text = "Sort: rank"
	sort_rank_btn.tooltip_text = "Sort your hand by rank, increasing left to right (jokers last)"
	sort_rank_btn.focus_mode = Control.FOCUS_NONE
	sort_rank_btn.pressed.connect(ui._on_sort_rank_pressed)
	sort_row.add_child(sort_rank_btn)
	var sort_suit_btn := Button.new()
	sort_suit_btn.text = "Sort: suit"
	sort_suit_btn.tooltip_text = "Sort your hand by suit, reds then blacks (jokers last)"
	sort_suit_btn.focus_mode = Control.FOCUS_NONE
	sort_suit_btn.pressed.connect(ui._on_sort_suit_pressed)
	sort_row.add_child(sort_suit_btn)

	ui.hand_box = HFlowContainer.new()
	ui.hand_box.add_theme_constant_override("h_separation", 4)
	ui.hand_box.add_theme_constant_override("v_separation", 4)
	hand_col.add_child(ui.hand_box)
	for zone: Control in [ui.hand_panel, hand_col, hand_top, ui.hand_title, ui.hand_box]:
		zone.set_drag_forwarding(Callable(), ui._can_drop_on_hand, ui._drop_on_hand)
		zone.gui_input.connect(ui._on_background_gui_input)

	# Action row.
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	ui.game_root.add_child(actions)

	ui.selection_label = Label.new()
	ui.selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(ui.selection_label)

	ui.return_btn = Button.new()
	ui.return_btn.text = "Return to hand"
	ui.return_btn.tooltip_text = "Put the selected cards you played this turn back in your hand"
	ui.return_btn.pressed.connect(ui._on_return_pressed)
	actions.add_child(ui.return_btn)

	ui.undo_action_btn = Button.new()
	ui.undo_action_btn.text = "Undo action"
	ui.undo_action_btn.tooltip_text = "Take back only the last move you staged this turn"
	ui.undo_action_btn.pressed.connect(ui._on_undo_action_pressed)
	actions.add_child(ui.undo_action_btn)

	ui.reset_btn = Button.new()
	ui.reset_btn.text = "Undo turn"
	ui.reset_btn.tooltip_text = "Take back everything staged this turn"
	ui.reset_btn.pressed.connect(ui._on_reset_pressed)
	actions.add_child(ui.reset_btn)

	ui.end_turn_btn = Button.new()
	ui.end_turn_btn.text = "End turn"
	ui.end_turn_btn.pressed.connect(ui._on_end_turn_pressed)
	actions.add_child(ui.end_turn_btn)

	ui.draw_btn = Button.new()
	ui.draw_btn.text = "Draw & end turn"
	ui.draw_btn.pressed.connect(ui._on_draw_pressed)
	actions.add_child(ui.draw_btn)

	ui.settings_btn = Button.new()
	ui.settings_btn.text = "Settings"
	ui.settings_btn.tooltip_text = "Enemy AI, enemy count, draw count, hand cap, play cap and jokers"
	ui.settings_btn.pressed.connect(ui._on_settings_pressed)
	actions.add_child(ui.settings_btn)

	ui.new_game_btn = Button.new()
	ui.new_game_btn.text = "New game"
	ui.new_game_btn.pressed.connect(ui._on_new_game_pressed)
	actions.add_child(ui.new_game_btn)

	var menu_btn := Button.new()
	menu_btn.text = "Menu"
	menu_btn.tooltip_text = "Back to the main menu — the game is kept"
	menu_btn.pressed.connect(ui._show_menu)
	actions.add_child(menu_btn)

	ui.status_label = Label.new()
	ui.status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui.game_root.add_child(ui.status_label)

	ui.log_box = RichTextLabel.new()
	ui.log_box.custom_minimum_size = Vector2(0, 74)
	ui.log_box.scroll_following = true
	ui.log_box.fit_content = false
	ui.game_root.add_child(ui.log_box)

	# Overlay for the flying-card animations; never intercepts the mouse.
	ui.anim_layer = Control.new()
	ui.anim_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.anim_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(ui.anim_layer)
	ui.animator = EnemyMoveAnimator.new()
	ui.add_child(ui.animator)
	ui.animator.setup(ui.anim_layer, ui)

	_build_opponent_hand_overlay(ui)

	# The menu sits above everything (including in-flight card animations).
	_build_menu(ui)
	_build_settings_dialog(ui)
	_build_enemy_info_dialog(ui)

## A plain centered seat column (an opponent's name chip + card backs go here).
func _make_seat() -> VBoxContainer:
	var seat := VBoxContainer.new()
	seat.alignment = BoxContainer.ALIGNMENT_CENTER
	seat.add_theme_constant_override("separation", 6)
	return seat

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
