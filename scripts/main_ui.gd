extends Control

## Playable UI for vanilla Machiavelli, built entirely in code so the scene
## file stays trivial.
##
## A main menu fronts the table: Roguelike run, Vanilla sandbox (a fresh
## free-play game), Resume (shown once a game exists), Settings and Quit.
## The in-game Menu button returns to it without losing the game in progress.
##
## Roguelike run: an endless ladder of 1v1 games under fixed run rules —
## draw 2 cards per turn, at most 13 cards played per turn, all 4 jokers in.
## Beat an enemy to advance to the next round (the "New game" button becomes
## "Next round"); lose and the run is over ("New run" starts over at round
## 1). Each round faces a designed enemy picked at random from Enemy.roster()
## — for now the only one is the Cute Slime, who slimes half the hearts, half
## the diamonds and every joker (slimed cards carry a green splotch and stick to
## each other, so a run of them moves as one lump). Sandbox settings never apply
## during a run, so the Settings button is disabled in-game while one is active.
##
## Table layout: you sit at the bottom; opponents sit around the table showing
## the backs of their cards. The first enemy sits directly opposite you at the
## top, the second on the left, and a fourth player (when one exists) sits on
## the right — at most 4 seats in total. Backs overlap more as a hand grows so
## every seat always fits on screen.
##
## How to play: on your turn, drag cards — from your hand AND from any group
## on the table (rearranging the table is the heart of the game). Drop them
## onto a group (or any card in it) to add them there, or onto empty felt to
## start a fresh group. Cards you laid down this turn can be dragged back
## into your hand (or selected and sent back with the "Return to hand"
## button). Clicking still works too: click cards to select them (they lift
## and turn blue), then click the "+ New group" zone — it appears only while
## cards are selected, keeping the table clean. Adding to an existing group
## is done by dragging. Dragging a selected card drags the whole selection.
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
## immediately), the max hand size (none, or 10-20 — drawing stops at the
## cap and a draw on a full hand is a pass; applies immediately), the max
## cards played per turn (none, or 10-20 — only cards leaving your hand
## count, rearranging the table is free; applies immediately, and binds the
## AI too), and the joker toggle (next game). Jokers (★) count as any
## card; a joker in a valid group shows the card it currently stands for
## (e.g. ★7♥), and if you hold that exact card you can drop it on the joker
## to swap it out and take the wildcard into your hand. When a group leaves
## the joker a choice (say, two missing suits in a set of three), right-click
## the joker on your turn to pick which card it stands for — but only until
## the turn that placed it is committed: from then on the joker is locked to
## that card (no longer a wildcard, even when rearranged) until the swap
## sends it back to a hand.

const AI_THINK_DELAY := 0.6
const AI_MOVE_DELAY := 0.5
const AI_ANIM_TIME := 0.45
const RED_SUITS := ["hearts", "diamonds"]
const DRAG_TYPE := "machiavelli_cards"

## The UI seats at most this many players: you + up to 3 opponents.
const MAX_PLAYERS := 4
const ENEMY_NAMES := ["Rosso", "Nero", "Bianco"]

## Fixed rules for a roguelike run. Each round faces a designed enemy from
## Enemy.roster(), which brings its own AI profile and mechanics.
const ROGUE_DRAW_PER_TURN := 2
const ROGUE_MAX_PLAYS_PER_TURN := 13

const CARD_SIZE := Vector2(78, 108)  # hand cards
const CARD_FONT_SIZE := 28
const BOARD_CARD_SIZE := Vector2(62, 86)  # table cards are smaller, so more groups fit
const BOARD_CARD_FONT_SIZE := 22
const NEW_GROUP_SIZE := Vector2(136, 102)
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
const COL_MELD_BORDER := Color(1, 1, 1, 0.16)
const COL_MELD_BAD := Color(0.92, 0.35, 0.30)
const COL_CHIP_BG := Color(0.13, 0.14, 0.17)
const COL_CHIP_ACTIVE := Color(0.93, 0.72, 0.13)
const COL_JOKER := Color(0.48, 0.20, 0.62)
const COL_JOKER_BG := Color(0.96, 0.92, 0.98)
const COL_SLIME := Color(0.44, 0.82, 0.30)      # the slime splotch on a slimed card
const COL_SLIME_EDGE := Color(0.20, 0.52, 0.16)

enum Mode { SANDBOX, ROGUE }

var gm: GameManager
var game_mode := Mode.SANDBOX
var rogue_round := 1
# The designed enemy faced in the current rogue round (null in sandbox); drives
# the AI profile and planted the round's mechanics at combat start.
var current_enemy: Enemy = null
# Whether the just-finished rogue game was won, i.e. "Next round" is on offer.
var rogue_round_won := false
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

# Settings (the Settings dialog) — sandbox games only; a roguelike run's
# rules are fixed. The AI graph and draw count apply immediately; enemy count
# and jokers take effect on the next new game.
var ai_strength := 1.0    # 0 = weak, 1 = strong
var ai_style := 0.0       # 0 = quick, 1 = conservative
var ai_attention := 1.0   # 0 = oblivious, 1 = attentive
var enemy_count := 2      # 1-3
var draw_per_turn := 1    # 1-3
var max_hand_size := 0    # 0 = no cap, otherwise 10-20
var max_plays_per_turn := 0  # 0 = no cap, otherwise 10-20
var include_jokers := false

var game_root: VBoxContainer
var menu_layer: PanelContainer
var resume_btn: Button
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
	_show_menu()

func _new_game() -> void:
	game_generation += 1
	selected.clear()
	highlighted.clear()
	ai_running = false
	rogue_round_won = false
	_clear_children(anim_layer)
	log_box.clear()
	if game_mode == Mode.ROGUE:
		current_enemy = Enemy.random_enemy()
		gm.setup(["You", current_enemy.display_name], GameManager.DEFAULT_HAND_SIZE, -1, true)
		gm.draw_per_turn = ROGUE_DRAW_PER_TURN
		gm.max_hand_size = 0
		gm.max_plays_per_turn = ROGUE_MAX_PLAYS_PER_TURN
		# Let the enemy plant its mechanics on the freshly dealt game.
		current_enemy.on_combat_start(gm)
		_log("[b]Round %d[/b] — you face %s. Run rules: draw %d per turn, "
			% [rogue_round, current_enemy.display_name, ROGUE_DRAW_PER_TURN]
			+ "at most %d cards played per turn, 4 jokers in."
			% ROGUE_MAX_PLAYS_PER_TURN)
		if current_enemy is CuteSlime:
			_log("[b]%s[/b] slimes half the hearts, half the diamonds and every "
				% current_enemy.display_name
				+ "joker (green splotch). Slimed cards stick to each other, so a "
				+ "run of them is one lump — dragging one drags them all. She "
				+ "oozes freely and each turn guards her most valuable slimed card "
				+ "(jokers, then the versatile 4-8s) to keep it out of your reach.")
	else:
		current_enemy = null
		var names: Array = ["You"]
		for i in enemy_count:
			names.append(ENEMY_NAMES[i])
		gm.setup(names, GameManager.DEFAULT_HAND_SIZE, -1, include_jokers)
		gm.draw_per_turn = draw_per_turn
		gm.max_hand_size = max_hand_size
		gm.max_plays_per_turn = max_plays_per_turn
		_log("New game: %d enem%s, 13 cards each, double deck, %s." % [enemy_count,
			"y" if enemy_count == 1 else "ies",
			"4 jokers in" if include_jokers else "no jokers"])
	_set_status("Your turn. Drag cards to the table (or click to select) — "
		+ "open by laying down a valid group from your hand.")
	if game_mode == Mode.ROGUE or include_jokers:
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
	# Paint the whole window in dark felt instead of the engine's gray.
	RenderingServer.set_default_clear_color(COL_FELT_DARK)

	game_root = VBoxContainer.new()
	game_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_root.add_theme_constant_override("separation", 6)
	game_root.offset_left = 10
	game_root.offset_top = 10
	game_root.offset_right = -10
	game_root.offset_bottom = -10
	add_child(game_root)

	# Top row: the first enemy's seat, centered directly opposite you, with the
	# stock count tucked into the corner.
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 8)
	game_root.add_child(top_bar)
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
	game_root.add_child(mid_row)
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
	game_root.add_child(hand_panel)
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
	game_root.add_child(actions)

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
	settings_btn.tooltip_text = "Enemy AI, enemy count, draw count, hand cap, play cap and jokers"
	settings_btn.pressed.connect(_on_settings_pressed)
	actions.add_child(settings_btn)

	new_game_btn = Button.new()
	new_game_btn.text = "New game"
	new_game_btn.pressed.connect(_on_new_game_pressed)
	actions.add_child(new_game_btn)

	var menu_btn := Button.new()
	menu_btn.text = "Menu"
	menu_btn.tooltip_text = "Back to the main menu — the game is kept"
	menu_btn.pressed.connect(_show_menu)
	actions.add_child(menu_btn)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game_root.add_child(status_label)

	log_box = RichTextLabel.new()
	log_box.custom_minimum_size = Vector2(0, 74)
	log_box.scroll_following = true
	log_box.fit_content = false
	game_root.add_child(log_box)

	# Overlay for the flying-card animations; never intercepts the mouse.
	anim_layer = Control.new()
	anim_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	anim_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anim_layer)

	# The menu sits above everything (including in-flight card animations).
	_build_menu()
	_build_settings_dialog()

func _build_menu() -> void:
	menu_layer = PanelContainer.new()
	menu_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_theme_stylebox_override("panel", _panel_style(COL_FELT_DARK, 0))
	add_child(menu_layer)
	var center := CenterContainer.new()
	menu_layer.add_child(center)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	center.add_child(col)

	var title := Label.new()
	title.text = "Machiavelli"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 54)
	title.add_theme_color_override("font_color", COL_CHIP_ACTIVE)
	col.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "the Italian rummy of rearranging the whole table"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	col.add_child(subtitle)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	col.add_child(gap)

	resume_btn = _make_menu_button("Resume game", _on_resume_pressed)
	col.add_child(resume_btn)
	col.add_child(_make_menu_button("Roguelike run", _on_play_rogue_pressed))
	col.add_child(_make_menu_button("Vanilla sandbox", _on_play_vanilla_pressed))
	col.add_child(_make_menu_button("Settings", _on_settings_pressed))
	col.add_child(_make_menu_button("Quit", _on_quit_pressed))

func _make_menu_button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280, 54)
	b.add_theme_font_size_override("font_size", 21)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_pressed)
	return b

func _show_menu() -> void:
	resume_btn.visible = not gm.players.is_empty()
	menu_layer.visible = true
	game_root.visible = false

func _show_game() -> void:
	menu_layer.visible = false
	game_root.visible = true
	_refresh()

func _on_play_vanilla_pressed() -> void:
	game_mode = Mode.SANDBOX
	_new_game()
	_show_game()

func _on_play_rogue_pressed() -> void:
	game_mode = Mode.ROGUE
	rogue_round = 1
	_new_game()
	_show_game()

func _on_resume_pressed() -> void:
	_show_game()

func _on_quit_pressed() -> void:
	get_tree().quit()

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
	ai_label.text = "Enemy AI — three independent dials for the opponents' brains."
	ai_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(ai_label)

	col.add_child(_make_ai_slider_row("Skill", "Weak", "Strong", ai_strength,
		func(v: float) -> void:
			ai_strength = v
			_refresh_ai_desc()))
	col.add_child(_make_ai_slider_row("Style", "Quick", "Conservative", ai_style,
		func(v: float) -> void:
			ai_style = v
			_refresh_ai_desc()))
	col.add_child(_make_ai_slider_row("Attention", "Oblivious", "Attentive", ai_attention,
		func(v: float) -> void:
			ai_attention = v
			_refresh_ai_desc()))

	ai_desc_label = Label.new()
	ai_desc_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	ai_desc_label.text = _ai_description()
	col.add_child(ai_desc_label)

	col.add_child(HSeparator.new())

	col.add_child(_make_spin_row("Enemies (next game):", 1, 3, enemy_count,
		_on_enemy_count_changed))
	col.add_child(_make_spin_row("Cards drawn per turn:", 1, 3, draw_per_turn,
		_on_draw_count_changed))
	# Max hand size: with a cap, drawing stops at the cap and a draw attempted
	# on a full hand becomes a pass. Applies immediately — but never to a
	# roguelike run, whose rules are fixed.
	col.add_child(_make_cap_row("Max hand size:", max_hand_size,
		func(v: int) -> void:
			max_hand_size = v
			if game_mode == Mode.SANDBOX:
				gm.max_hand_size = v))
	# Max cards played per turn: only cards leaving the hand count, and the
	# same cap binds the AI. Applies immediately (sandbox only).
	col.add_child(_make_cap_row("Max cards played per turn:", max_plays_per_turn,
		func(v: int) -> void:
			max_plays_per_turn = v
			if game_mode == Mode.SANDBOX:
				gm.max_plays_per_turn = v))

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

## A "None or 10-20" dropdown row; `on_changed` gets the chosen value (0 for
## "None"). Used for the hand cap and the play cap.
func _make_cap_row(text: String, value: int, on_changed: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var opt := OptionButton.new()
	opt.add_item("None", 0)
	for v in range(10, 21):
		opt.add_item(str(v), v)
	opt.select(0 if value == 0 else value - 9)
	opt.item_selected.connect(func(idx: int) -> void:
		on_changed.call(opt.get_item_id(idx)))
	row.add_child(opt)
	return row

func _on_settings_pressed() -> void:
	settings_dialog.popup_centered()

func _on_enemy_count_changed(value: float) -> void:
	enemy_count = int(value)

func _on_draw_count_changed(value: float) -> void:
	draw_per_turn = int(value)
	if game_mode == Mode.SANDBOX:
		gm.draw_per_turn = draw_per_turn

func _on_jokers_toggled(on: bool) -> void:
	include_jokers = on

## A titled 0..1 slider with its two end labels underneath. `on_changed` gets
## the new value. Used for the three enemy-AI dials.
func _make_ai_slider_row(title: String, left: String, right: String,
		value: float, on_changed: Callable) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var head := Label.new()
	head.text = title
	box.add_child(head)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(on_changed)
	box.add_child(slider)
	var ends := HBoxContainer.new()
	var l := Label.new()
	l.text = left
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	l.add_theme_font_size_override("font_size", 12)
	var r := Label.new()
	r.text = right
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	r.add_theme_font_size_override("font_size", 12)
	ends.add_child(l)
	ends.add_child(r)
	box.add_child(ends)
	return box

func _refresh_ai_desc() -> void:
	ai_desc_label.text = _ai_description()

func _ai_description() -> String:
	var skill := "capable"
	if ai_strength < 0.35:
		skill = "weak"
	elif ai_strength >= AIProfile.SMART_BRAIN_SKILL:
		skill = "cutthroat"
	elif ai_strength >= 0.7:
		skill = "strong"
	var pace := "quick"
	if ai_style >= 0.75:
		pace = "conservative"
	elif ai_style >= 0.4:
		pace = "balanced"
	var focus := "attentive"
	if ai_attention < 0.4:
		focus = "oblivious"
	elif ai_attention < 0.75:
		focus = "distractible"
	return "Enemies play %s, %s and %s. Applies from their next turn." % [skill, pace, focus]

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
	# The "+ New group" click target only appears while cards are selected;
	# drags can always land on empty felt instead.
	if not selected.is_empty() and _is_human_turn():
		board_flow.add_child(_make_new_group_zone())

func _make_meld_panel(meld: CardSet) -> PanelContainer:
	Rules.assign_jokers(meld.cards)
	var panel := PanelContainer.new()
	var valid := meld.is_valid()
	var locked := _is_human_turn() and not gm.current_player_is_open() \
		and not gm.is_own_staged_meld(meld)
	# Valid groups sit quietly on the felt; only broken ones shout.
	var sb := _panel_style(Color(1, 1, 1, 0.045), 10)
	sb.border_color = COL_MELD_BORDER if valid else COL_MELD_BAD
	sb.set_border_width_all(1 if valid else 2)
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
	return panel

func _make_new_group_zone() -> Button:
	var zone := Button.new()
	zone.text = "+ New group"
	zone.tooltip_text = "Drop or move selected cards here to start a brand-new group"
	zone.custom_minimum_size = NEW_GROUP_SIZE
	zone.focus_mode = Control.FOCUS_NONE
	var sb := _panel_style(Color(1, 1, 1, 0.04), 10)
	sb.border_color = Color(1, 1, 1, 0.35)
	sb.set_border_width_all(2)
	zone.add_theme_stylebox_override("normal", sb)
	zone.add_theme_stylebox_override("hover", _hover_variant(sb))
	zone.add_theme_stylebox_override("pressed", sb)
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
			c.joker_lock_rank = 0
			c.joker_lock_suit = ""
	for c in hand:
		hand_box.add_child(_make_card_button(c))

func _refresh_buttons() -> void:
	var human_turn := _is_human_turn()
	return_btn.disabled = not human_turn or not gm.can_return_to_hand(selected)
	undo_action_btn.disabled = not human_turn or not gm.can_undo_action()
	reset_btn.disabled = not human_turn or not gm.can_undo_action()
	end_turn_btn.disabled = not human_turn
	draw_btn.disabled = not human_turn
	if game_mode == Mode.ROGUE:
		new_game_btn.text = "Next round" if gm.is_game_over and rogue_round_won \
			else "New run"
		settings_btn.disabled = true
		settings_btn.tooltip_text = "Sandbox settings — a run's rules are fixed " \
			+ "(draw %d, %d plays max, jokers in)" \
			% [ROGUE_DRAW_PER_TURN, ROGUE_MAX_PLAYS_PER_TURN]
	else:
		new_game_btn.text = "New game"
		settings_btn.disabled = false
		settings_btn.tooltip_text = \
			"Enemy AI, enemy count, draw count, hand cap, play cap and jokers"
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
	b.custom_minimum_size = BOARD_CARD_SIZE if on_board else CARD_SIZE
	b.disabled = not _card_is_interactive(meld)
	if on_board and b.disabled and _is_human_turn():
		b.tooltip_text = "Locked until you open — lay down a valid group " \
			+ "from your own hand first."
	b.add_theme_font_size_override("font_size",
		BOARD_CARD_FONT_SIZE if on_board else CARD_FONT_SIZE)
	b.focus_mode = Control.FOCUS_NONE

	var font_col := COL_CARD_RED if RED_SUITS.has(c.suit) else COL_CARD_BLACK
	if c.is_joker:
		font_col = COL_JOKER
		if not b.disabled:
			if c.joker_lock_rank > 0:
				b.tooltip_text = ("Joker placed as %s — it stays that card until " \
					+ "it leaves the table. Hold the real %s? Drop it on this " \
					+ "joker to swap it into your hand.") % [c.rep_label(), c.rep_label()]
			elif c.joker_rank > 0:
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

	if c.is_sticky():
		_add_slime_blob(b)

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

## A little green slime splotch pinned to the top-right corner of a card, the
## visible mark of the Cute Slime's Sticky effect. Non-interactive so it never
## steals the card's clicks or drags.
func _add_slime_blob(parent: Control) -> void:
	const BLOB := 15.0
	const MARGIN := 3.0
	var blob := Panel.new()
	blob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blob.anchor_left = 1.0
	blob.anchor_right = 1.0
	blob.anchor_top = 0.0
	blob.anchor_bottom = 0.0
	blob.offset_left = -(BLOB + MARGIN)
	blob.offset_right = -MARGIN
	blob.offset_top = MARGIN
	blob.offset_bottom = MARGIN + BLOB
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_SLIME
	sb.border_color = COL_SLIME_EDGE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(BLOB / 2.0))
	blob.add_theme_stylebox_override("panel", sb)
	blob.tooltip_text = "Slimed — sticks to adjacent slimed cards; moving one drags the lump."
	parent.add_child(blob)

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
	# A slimed card on the table drags its whole cluster; expand the drag so the
	# preview shows what will actually move (the engine expands again to be sure).
	cards = _expand_sticky(cards)
	source.set_drag_preview(_make_drag_preview(cards))
	return {"type": DRAG_TYPE, "cards": cards}

## Grow a drag set so a slimed table card brings its whole slime cluster along,
## mirroring GameManager._expand_sticky. Hand cards (not on any meld) are left
## untouched. Purely for the preview and selection feel — the engine expands
## again when the move is staged, so this only has to match, not be trusted.
func _expand_sticky(cards: Array[Card]) -> Array[Card]:
	var out: Array[Card] = []
	for c in cards:
		if out.has(c):
			continue
		var meld := gm.board.meld_of(c)
		if meld == null:
			out.append(c)
			continue
		for m in meld.sticky_cluster(c):
			if not out.has(m):
				out.append(m)
	return out

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
	if not _card_is_interactive(meld) or joker.joker_lock_rank > 0:
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

## Sandbox: always a fresh game. Roguelike: "Next round" after a won game
## advances the ladder; otherwise the run restarts from round 1.
func _on_new_game_pressed() -> void:
	if game_mode == Mode.ROGUE:
		if gm.is_game_over and rogue_round_won:
			rogue_round += 1
		else:
			rogue_round = 1
	_new_game()

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
	var why := "stock is empty" if gm.deck.is_empty() else "hand is full"
	_log("%s passed (%s)." % [p.display_name, why])

func _on_game_over(winners: Array) -> void:
	var names := PackedStringArray()
	for p in winners:
		names.append(p.display_name)
	var who := ", ".join(names)
	_log("[b]Game over — winner: %s[/b]" % who)
	if game_mode == Mode.ROGUE:
		# A shared fewest-cards tie counts as surviving the round.
		rogue_round_won = winners.has(gm.players[0])
		if rogue_round_won:
			_set_status("Round %d cleared! Press \"Next round\" for the next enemy."
				% rogue_round)
		else:
			_set_status("Run over — %s beat you on round %d. Press \"New run\" to try again."
				% [who, rogue_round])
	else:
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
	var in_rogue := game_mode == Mode.ROGUE and current_enemy != null
	var profile := current_enemy.make_profile() if in_rogue \
		else AIProfile.new(ai_strength, ai_style, ai_attention)
	# The designed enemy drives its strategy (e.g. the slime guarding jokers).
	var enemy_def: Enemy = current_enemy if in_rogue else null
	highlighted.clear()
	_refresh()
	while not gm.is_game_over and gm.current_player().is_opponent:
		var enemy := gm.current_player()
		if enemy_def != null:
			enemy_def.on_turn_begin(gm)
		_set_status("%s is thinking…" % enemy.display_name)
		_refresh()
		await get_tree().create_timer(AI_THINK_DELAY).timeout
		if gen != game_generation:
			return
		var played_any := false
		while true:
			var move: Dictionary = GreedyAI.plan_move(gm, profile, enemy_def)
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
			+ "or click to select, then use \"+ New group\".")
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
		return backs.get_global_rect().get_center() - BOARD_CARD_SIZE / 2.0
	return get_global_rect().get_center() - BOARD_CARD_SIZE / 2.0

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

## A non-interactive card face used as an animation proxy; sized like the
## board card it lands on and styled like the gold highlight it will carry.
func _make_card_face(c: Card) -> Control:
	var face := PanelContainer.new()
	face.custom_minimum_size = BOARD_CARD_SIZE
	face.size = BOARD_CARD_SIZE
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_theme_stylebox_override("panel", _card_style(COL_HILITE_BG, COL_HILITE, 3))
	var lbl := Label.new()
	lbl.text = c.label()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", BOARD_CARD_FONT_SIZE)
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
