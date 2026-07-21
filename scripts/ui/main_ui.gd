class_name MainUI
extends Control

## Playable UI for vanilla Machiavelli, built entirely in code so the scene
## file stays trivial.
##
## A main menu fronts the table: Roguelike run, Vanilla sandbox (a fresh
## free-play game), Resume (shown once a game exists), Settings and Quit.
## The in-game Menu button returns to it without losing the game in progress.
##
## Roguelike run: an endless ladder of 1v1 games under the run rules from the
## Settings dialog's "Roguelike run" tab (defaults: draw 2 cards per turn, at
## most 13 cards played per turn, 13-card starting hands, all 4 jokers in).
## Beat an enemy to advance to the next round (the "New game" button becomes
## "Next round"); lose and the run is over ("New run" starts over at round
## 1). Each round faces a designed enemy picked at random from Enemy.roster():
## the Cute Slime, who slimes every heart, diamond and joker in her own deck
## (slimed cards carry a green splotch and stick to each other, so a run of them
## moves as one lump), or the Sadistic Billionaire, who turns every card in his
## own deck to glass (glass cards render transparent and are visible from the
## back — in any hand and on top of the stock — so his glass cards show face-up
## in his seat and a glass stock top is shown beside the stock count). Because
## each player brings their own deck and they only merge into the stock at combat
## start, an enemy corrupts just its own half — one copy of any card, so only two
## of the four jokers. Vanilla sandbox settings never apply during a run;
## roguelike settings apply from the next round.
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
## Right-clicking anywhere (a card, the felt, the hand) clears the selection;
## on a joker you placed this turn the stand-in menu takes precedence.
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
## half = after), drag to the hand's empty space to send it to the end, or use
## the "Sort: rank" / "Sort: suit" buttons in the hand header. Hovering a
## hand card spotlights every board spot it could play into right now with no
## rearranging — the groups it lays off onto, and a "New group" cue when it
## completes a fresh group with other cards in your hand.
##
## The table header carries "Sort" and "Randomize" (reorder the groups on the
## felt) plus a suit highlighter (♥ ♦ ♣ ♠): hover a suit to outline every card
## of it across the whole table AND your hand at once, fading the rest.
##
## The Settings dialog is split into two tabs. "Vanilla sandbox" holds: the
## enemy AI dials (apply from the next enemy turn), the number of enemies
## (1-3, next game), cards drawn per turn (1-3, applies immediately), the
## starting hand size (5-21, next game), the max hand size (none, or 10-20 —
## drawing stops at the cap and a draw on a full hand is a pass; applies
## immediately), the max cards played per turn (none, or 10-20 — only cards
## leaving your hand count, rearranging the table is free; applies
## immediately, and binds the AI too), the joker toggle (next game) and the
## starting-combo toggle (next game). "Roguelike run" holds the run's own
## copies of the same rules — draw count, starting hand size, hand cap, play
## cap, jokers, starting combos — all applying from the next round, so the
## run can be balanced without touching the sandbox. Starting combos deal
## every player a random valid three-card group from the stock onto the table
## at game start, which counts as their opening meld — nobody sits locked out
## of the table on a hand that can't lay a group. Jokers (★) count as any
## card while in a hand; the moment one lands in a valid group on the table
## it locks to the card it stands for (e.g. ★7♥) and is treated as exactly
## that card — no longer a wildcard, even when the group is rearranged or
## broken — until a swap sends it back to a hand: hold the real card it
## stands for and drop it on the joker to take the wildcard. While the turn
## that placed a joker is still yours, right-click it to pick a different
## card it could stand for (say, the other missing suit in a set of three);
## once the turn ends the choice is final.

enum Mode { SANDBOX, ROGUE }

const AI_THINK_DELAY := 0.6
const AI_MOVE_DELAY := 0.5
const DRAG_TYPE := "machiavelli_cards"

## The UI seats at most this many players: you + up to 3 opponents.
const MAX_PLAYERS := 4
const ENEMY_NAMES := ["Rosso", "Nero", "Bianco"]

## Suit order for the "Sort: straights" hand button and the table Sort: reds
## together, then blacks, so runs of the same colour sit side by side. Jokers
## are handled separately (last).
const SUIT_ORDER := {"hearts": 0, "diamonds": 1, "clubs": 2, "spades": 3}

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
# While a suit-highlighter button is hovered this holds that suit; the table and
# hand redraw with those cards outlined and every other suit faded. "" = none.
var hover_filter_suit := ""
# While a hand card is hovered, the board spots it can be played into right now
# with no rearranging: hint_meld_targets is the set of existing groups it lays
# off onto (CardSet -> true), and hint_new_group is true when it forms a
# brand-new group with other cards already in the hand. hover_hint_card is the
# card driving them, so a stale mouse_exited from the card just left doesn't wipe
# the hints the newly hovered card set.
var hint_meld_targets := {}
var hint_new_group := false
var hover_hint_card: Card = null
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

# Every tunable rule for both modes, plus persistence, lives on this model;
# the Settings dialog edits it and _new_game reads it.
var settings := GameSettings.new()

var game_root: VBoxContainer
var menu_layer: MenuScreen
var seat_top: VBoxContainer
var seat_left: VBoxContainer
var seat_right: VBoxContainer
var round_label: Label
var stock_label: Label
var stock_top_slot: HBoxContainer
var status_label: Label
var log_box: RichTextLabel
## The freeform felt: a plain canvas whose children (group panels) are each
## positioned absolutely at their group's board_pos, so a tall vertical group
## and a wide horizontal one sit side by side wherever they are dropped rather
## than being packed into flow rows. TableView owns the layout math.
var board_flow: Control
var hand_panel: PanelContainer
var hand_box: HFlowContainer
var hand_title: Label
var hand_meter_slot: HBoxContainer
var selection_label: Label
var return_btn: Button
var undo_action_btn: Button
var reset_btn: Button
var end_turn_btn: Button
var draw_btn: Button
var settings_btn: Button
var new_game_btn: Button
var sort_board_btn: Button
var randomize_board_btn: Button
var settings_dialog: SettingsDialog
var enemy_info_dialog: AcceptDialog
var enemy_info_body: RichTextLabel
var anim_layer: Control
var animator: EnemyMoveAnimator
# Renders the seats, board and hand into the containers above.
var _table := TableView.new()
## The in-progress freeform group drag, or {} when nothing is being dragged. Set
## by a panel's move handle (TableView), followed and finished in _input.
var _group_drag := {}

func _ready() -> void:
	gm = GameManager.new()
	add_child(gm)
	gm.turn_committed.connect(_on_turn_committed)
	gm.meter_charged.connect(_on_meter_charged)
	gm.cards_drawn.connect(_on_cards_drawn)
	gm.player_passed.connect(_on_player_passed)
	gm.game_over.connect(_on_game_over)
	# Seed the per-enemy AI overrides from the roster, then let any saved
	# settings override the defaults, before the settings dialog reads them.
	settings.seed_ai_overrides()
	settings.load_saved()
	_table.setup(self)
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
	var combo_start := false
	var jokers_in := false
	if game_mode == Mode.ROGUE:
		combo_start = settings.rogue_start_combo
		jokers_in = settings.rogue_jokers
		current_enemy = Enemy.random_enemy()
		settings.apply_ai_override(current_enemy)
		gm.setup(["You", current_enemy.display_name], settings.rogue_start_hand_size, -1, settings.rogue_jokers)
		gm.draw_per_turn = settings.rogue_draw_per_turn
		gm.max_hand_size = settings.rogue_max_hand_size
		gm.max_plays_per_turn = settings.rogue_max_plays_per_turn
		gm.meter_max = settings.rogue_meter_max
		gm.meter_gain = settings.rogue_meter_gain
		gm.meter_per_card = settings.rogue_meter_per_card
		# Let the enemy plant its mechanics on the freshly dealt game.
		current_enemy.on_combat_start(gm)
		_log("[b]Round %d[/b] — you face %s. Run rules: draw %d per turn, "
			% [rogue_round, current_enemy.display_name, settings.rogue_draw_per_turn]
			+ "%s cards played per turn, %d-card hands, %s."
			% ["at most %d" % settings.rogue_max_plays_per_turn if settings.rogue_max_plays_per_turn > 0
				else "unlimited", settings.rogue_start_hand_size,
				"4 jokers in" if settings.rogue_jokers else "no jokers"])
		var intro := current_enemy.mechanic_intro()
		if intro != "":
			_log(intro)
	else:
		combo_start = settings.start_combo
		jokers_in = settings.include_jokers
		current_enemy = null
		var names: Array = ["You"]
		for i in settings.enemy_count:
			names.append(ENEMY_NAMES[i])
		gm.setup(names, settings.start_hand_size, -1, settings.include_jokers)
		gm.draw_per_turn = settings.draw_per_turn
		gm.max_hand_size = settings.max_hand_size
		gm.max_plays_per_turn = settings.max_plays_per_turn
		gm.meter_max = settings.meter_max
		gm.meter_gain = settings.meter_gain
		gm.meter_per_card = settings.meter_per_card
		_log("New game: %d enem%s, %d cards each, double deck, %s." % [settings.enemy_count,
			"y" if settings.enemy_count == 1 else "ies", settings.start_hand_size,
			"4 jokers in" if settings.include_jokers else "no jokers"])
	if combo_start:
		# Dealt after the enemy's mechanics so combo cards keep their slime/glass.
		gm.deal_starting_melds()
		_set_status("Your turn. Drag cards to the table (or click to select) — "
			+ "your starting combo already opened you.")
		_log("Starting combos: every player begins with a random group on the "
			+ "table and counts as opened — the whole table is playable from turn one.")
	else:
		_set_status("Your turn. Drag cards to the table (or click to select) — "
			+ "open by laying down a valid group from your hand.")
	if jokers_in:
		_log("Jokers (★) count as any card. A joker in a valid group shows what "
			+ "it stands for — drop the real card on it to swap the joker into your hand.")
	if not combo_start:
		_log("Opening rule: lay down a valid group from your own hand before "
			+ "you can touch other groups on the table.")
	_refresh()

# --- Layout -------------------------------------------------------------------

func _build_layout() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var ui_theme := Theme.new()
	ui_theme.default_font_size = UITheme.UI_FONT_SIZE
	theme = ui_theme
	# Paint the whole window in dark felt instead of the engine's gray.
	RenderingServer.set_default_clear_color(UITheme.COL_FELT_DARK)

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
	# Round counter tucked into the top-left corner: one round is a full lap of
	# the table (every player takes a turn), ticking up when play returns to you.
	round_label = Label.new()
	round_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	round_label.add_theme_font_size_override("font_size", 18)
	round_label.add_theme_color_override("font_color", UITheme.COL_CHIP_ACTIVE)
	top_bar.add_child(round_label)
	var top_pad_left := Control.new()
	top_pad_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(top_pad_left)
	seat_top = _make_seat()
	top_bar.add_child(seat_top)
	var top_pad_right := Control.new()
	top_pad_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(top_pad_right)
	# Stock corner: the count, plus the top card of the stock when it is glass
	# (a glass top is public — everyone can see the next draw).
	var stock_box := HBoxContainer.new()
	stock_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	stock_box.add_theme_constant_override("separation", 6)
	top_bar.add_child(stock_box)
	stock_label = Label.new()
	stock_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stock_box.add_child(stock_label)
	stock_top_slot = HBoxContainer.new()
	stock_box.add_child(stock_top_slot)

	# Middle row: left seat, the felt, right seat (hidden until a 4th player).
	var mid_row := HBoxContainer.new()
	mid_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid_row.add_theme_constant_override("separation", 8)
	game_root.add_child(mid_row)
	seat_left = _make_seat()
	seat_left.custom_minimum_size = Vector2(UITheme.SIDE_SEAT_WIDTH, 0)
	mid_row.add_child(seat_left)

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
		table_top.add_child(_make_suit_filter_button(suit))
	sort_board_btn = Button.new()
	sort_board_btn.text = "Sort"
	sort_board_btn.tooltip_text = "Reorder the groups on the table: straights first " \
		+ "(by colour, then starting rank), then sets (by rank)"
	sort_board_btn.focus_mode = Control.FOCUS_NONE
	sort_board_btn.pressed.connect(_on_sort_board_pressed)
	table_top.add_child(sort_board_btn)
	randomize_board_btn = Button.new()
	randomize_board_btn.text = "Randomize"
	randomize_board_btn.tooltip_text = "Shuffle where the groups sit on the table, " \
		+ "keeping each group together"
	randomize_board_btn.focus_mode = Control.FOCUS_NONE
	randomize_board_btn.pressed.connect(_on_randomize_board_pressed)
	table_top.add_child(randomize_board_btn)

	var table_scroll := ScrollContainer.new()
	table_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	table_col.add_child(table_scroll)
	board_flow = Control.new()
	board_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_flow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_flow.mouse_filter = Control.MOUSE_FILTER_PASS
	board_flow.clip_contents = true
	table_scroll.add_child(board_flow)
	for zone: Control in [table_panel, table_scroll, board_flow]:
		zone.set_drag_forwarding(Callable(), _can_drop_new_group, _drop_new_group)
		zone.gui_input.connect(_on_background_gui_input)

	seat_right = _make_seat()
	seat_right.custom_minimum_size = Vector2(UITheme.SIDE_SEAT_WIDTH, 0)
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
	hand_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hand_title.add_theme_font_size_override("font_size", 15)
	hand_title.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	hand_top.add_child(hand_title)

	# Your own ultimate meter sits in the hand header; refresh_hand fills it (a
	# label + bar) when the meter is enabled, and leaves it empty otherwise.
	hand_meter_slot = HBoxContainer.new()
	hand_meter_slot.add_theme_constant_override("separation", 6)
	hand_meter_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hand_top.add_child(hand_meter_slot)

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
	sort_rank_btn.pressed.connect(_on_sort_rank_pressed)
	sort_row.add_child(sort_rank_btn)
	var sort_suit_btn := Button.new()
	sort_suit_btn.text = "Sort: suit"
	sort_suit_btn.tooltip_text = "Sort your hand by suit, reds then blacks (jokers last)"
	sort_suit_btn.focus_mode = Control.FOCUS_NONE
	sort_suit_btn.pressed.connect(_on_sort_suit_pressed)
	sort_row.add_child(sort_suit_btn)

	hand_box = HFlowContainer.new()
	hand_box.add_theme_constant_override("h_separation", 4)
	hand_box.add_theme_constant_override("v_separation", 4)
	hand_col.add_child(hand_box)
	for zone: Control in [hand_panel, hand_col, hand_top, hand_title, hand_box]:
		zone.set_drag_forwarding(Callable(), _can_drop_on_hand, _drop_on_hand)
		zone.gui_input.connect(_on_background_gui_input)

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
	animator = EnemyMoveAnimator.new()
	add_child(animator)
	animator.setup(anim_layer, self)

	# The menu sits above everything (including in-flight card animations).
	_build_menu()
	_build_settings_dialog()
	_build_enemy_info_dialog()

## A small pop-up describing an opponent: its mechanic (in a roguelike round)
## and the AI brain it is running. Opened by the "Info" button on its name chip.
func _build_enemy_info_dialog() -> void:
	enemy_info_dialog = AcceptDialog.new()
	enemy_info_dialog.title = "Enemy info"
	enemy_info_dialog.ok_button_text = "Close"
	add_child(enemy_info_dialog)
	enemy_info_body = RichTextLabel.new()
	enemy_info_body.bbcode_enabled = true
	enemy_info_body.fit_content = true
	enemy_info_body.custom_minimum_size = Vector2(440, 120)
	enemy_info_dialog.add_child(enemy_info_body)

func _on_enemy_info_pressed(player_index: int) -> void:
	enemy_info_body.text = _enemy_info_text(player_index)
	enemy_info_dialog.popup_centered()

## The info-panel text for the opponent in the given seat: name, mechanic and
## AI. In a roguelike round the sole opponent (seat 1) is the designed enemy, so
## its mechanic and tuned dials are shown; a sandbox opponent has no mechanic
## and reports the shared sandbox AI dials.
func _enemy_info_text(player_index: int) -> String:
	if player_index < 0 or player_index >= gm.players.size():
		return ""
	var p := gm.players[player_index]
	var lines := PackedStringArray()
	lines.append("[b]%s[/b]" % p.display_name)
	if current_enemy != null and player_index == 1:
		var intro := current_enemy.mechanic_intro()
		if intro != "":
			lines.append(intro)
		lines.append("AI: plays %s." % GameSettings.personality_desc(current_enemy.strength,
			current_enemy.style, current_enemy.attention, current_enemy.planning))
	else:
		lines.append("A vanilla opponent with no special mechanic.")
		lines.append("AI: plays %s." % GameSettings.personality_desc(
			settings.ai_strength, settings.ai_style, settings.ai_attention, settings.ai_planning))
	return "\n\n".join(lines)

## Instantiate the menu scene and wire each button's intent signal to the
## controller. The menu itself owns no game state.
func _build_menu() -> void:
	menu_layer = preload("res://scenes/ui/menu_screen.tscn").instantiate()
	add_child(menu_layer)
	menu_layer.play_vanilla_requested.connect(_on_play_vanilla_pressed)
	menu_layer.play_rogue_requested.connect(_on_play_rogue_pressed)
	menu_layer.resume_requested.connect(_on_resume_pressed)
	menu_layer.settings_requested.connect(_on_settings_pressed)
	menu_layer.quit_requested.connect(_on_quit_pressed)

func _show_menu() -> void:
	menu_layer.show_menu(not gm.players.is_empty())
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

## Instantiate the settings scene against the shared settings model. Sandbox
## rules that take effect mid-game are pushed onto the running game by
## _apply_live_settings whenever the dialog reports a change.
func _build_settings_dialog() -> void:
	settings_dialog = preload("res://scenes/ui/settings_dialog.tscn").instantiate()
	add_child(settings_dialog)
	settings_dialog.setup(settings, _apply_live_settings)

func _on_settings_pressed() -> void:
	settings_dialog.open()

## Push the settings whose changes apply immediately onto the running game, but
## only in sandbox — a roguelike run keeps the rules it started under.
func _apply_live_settings() -> void:
	if game_mode == Mode.SANDBOX:
		gm.draw_per_turn = settings.draw_per_turn
		gm.max_hand_size = settings.max_hand_size
		gm.max_plays_per_turn = settings.max_plays_per_turn
		gm.meter_max = settings.meter_max
		gm.meter_gain = settings.meter_gain
		gm.meter_per_card = settings.meter_per_card

func _make_seat() -> VBoxContainer:
	var seat := VBoxContainer.new()
	seat.alignment = BoxContainer.ALIGNMENT_CENTER
	seat.add_theme_constant_override("separation", 6)
	return seat

# --- Refresh ------------------------------------------------------------------

func _refresh() -> void:
	card_nodes.clear()
	# Any real state change (a play, an AI move, a new turn) invalidates the
	# transient hover hints, which point at now-stale groups.
	hint_meld_targets.clear()
	hint_new_group = false
	hover_hint_card = null
	_prune_selection()
	_table.refresh_seats()
	_table.refresh_board()
	_table.refresh_hand()
	_refresh_buttons()

func _refresh_buttons() -> void:
	var human_turn := _is_human_turn()
	return_btn.disabled = not human_turn or not gm.can_return_to_hand(selected)
	undo_action_btn.disabled = not human_turn or not gm.can_undo_action()
	reset_btn.disabled = not human_turn or not gm.can_undo_action()
	end_turn_btn.disabled = not human_turn
	draw_btn.disabled = not human_turn
	# Table tidy-ups need at least two groups to do anything, and never while the
	# enemies' cards are still flying around.
	var can_tidy := not ai_running and gm.board.melds.size() > 1
	sort_board_btn.disabled = not can_tidy
	randomize_board_btn.disabled = not can_tidy
	if game_mode == Mode.ROGUE:
		new_game_btn.text = "Next round" if gm.is_game_over and rogue_round_won \
			else "New run"
		settings_btn.tooltip_text = "Roguelike run rules (apply from the next " \
			+ "round) — the vanilla tab never touches a run"
	else:
		new_game_btn.text = "New game"
		settings_btn.tooltip_text = \
			"Enemy AI, enemy count, draw count, hand size, caps, jokers and starting combos"
	if selected.is_empty():
		selection_label.text = ""
	else:
		var parts := PackedStringArray()
		for c in Rules.display_order(selected):
			parts.append(c.label())
		selection_label.text = "Selected: %s" % " ".join(parts)

# --- Suit filter --------------------------------------------------------------

## One suit symbol in the highlighter row. It does nothing on click — hovering is
## the whole interaction: entering sets hover_filter_suit and redraws the table
## and hand so this suit is outlined everywhere and the others fade; leaving
## clears it again.
func _make_suit_filter_button(suit: String) -> Button:
	var b := Button.new()
	b.text = Card.SUIT_SYMBOLS.get(suit, suit)
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(30, 26)
	b.add_theme_font_size_override("font_size", 18)
	b.tooltip_text = "Hover to highlight every %s in play (hand and table) and fade the rest." % suit
	var col := UITheme.COL_CARD_RED if UITheme.RED_SUITS.has(suit) else UITheme.COL_CARD_BLACK
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, col)
	b.mouse_entered.connect(_on_suit_filter_enter.bind(suit))
	b.mouse_exited.connect(_on_suit_filter_exit.bind(suit))
	return b

func _on_suit_filter_enter(suit: String) -> void:
	# Never redraw mid enemy animation: rebuilding the board frees the buttons
	# the flying cards are heading for.
	if ai_running or hover_filter_suit == suit:
		return
	hover_filter_suit = suit
	_table.refresh_board()
	_table.refresh_hand()

func _on_suit_filter_exit(suit: String) -> void:
	# Guarded so sliding straight from one suit onto the next (exit fires after
	# the new enter) doesn't wipe the filter the new button just set.
	if ai_running or hover_filter_suit != suit:
		return
	hover_filter_suit = ""
	_table.refresh_board()
	_table.refresh_hand()

# --- Play hints ---------------------------------------------------------------

## Hovering a hand card spotlights every board spot it could play into right now
## with no rearranging (see _compute_play_hints). Only on your own turn. Skipped
## outright while enemy cards are flying — redrawing the board would free their
## destination buttons mid-flight.
func _on_hand_card_hover_enter(c: Card) -> void:
	if ai_running:
		return
	hover_hint_card = c
	hint_meld_targets.clear()
	hint_new_group = false
	if _is_human_turn():
		_compute_play_hints(c)
	_table.refresh_board()

func _on_hand_card_hover_exit(c: Card) -> void:
	# Guarded like the suit highlighter: sliding onto the next card fires that
	# card's enter before this exit, so only clear when we are still that card.
	if ai_running or hover_hint_card != c:
		return
	hover_hint_card = null
	if hint_meld_targets.is_empty() and not hint_new_group:
		return
	hint_meld_targets.clear()
	hint_new_group = false
	_table.refresh_board()

## Fill hint_meld_targets / hint_new_group for the hovered card: which existing
## valid groups it lays off onto as-is (respecting the opening rule — before you
## open, only your own just-laid groups count), and whether it completes a
## brand-new valid group with other cards already in your hand.
func _compute_play_hints(c: Card) -> void:
	var open := gm.current_player_is_open()
	for meld in gm.board.melds:
		# Pictures and their extension lines play by grid rules; the plain
		# lay-off hint doesn't read them (the ghost cells are their guide).
		if meld.is_shape() or meld.is_attached():
			continue
		if not meld.is_valid():
			continue
		if not open and not gm.is_own_staged_meld(meld):
			continue
		var candidate: Array[Card] = meld.cards.duplicate()
		candidate.append(c)
		if Rules.is_valid_meld(candidate):
			hint_meld_targets[meld] = true
	hint_new_group = _hand_forms_new_group(c)

## True when the hovered card plus other naturals already in the hand make a
## valid new group — a set of its rank across distinct suits, or a run of its
## suit. Plays that would need a joker to complete are disregarded, so the cue
## only lights for groups you can form without spending a wildcard. A hovered
## joker can't anchor a group on its own, so it never lights the new-group cue.
func _hand_forms_new_group(c: Card) -> bool:
	if c.is_joker:
		return false
	var hand := gm.players[0].hand
	# Set: c plus other naturals of the same rank in distinct suits (no jokers).
	var suits := {c.suit: true}
	for h in hand:
		if h != c and not h.is_joker and h.rank == c.rank:
			suits[h.suit] = true
	if suits.size() >= Rules.MIN_MELD_SIZE:
		return true
	# Run: c plus other naturals of the same suit, with no jokers to bridge gaps.
	var ranks := {c.rank: true}
	for h in hand:
		if h != c and not h.is_joker and h.suit == c.suit:
			ranks[h.rank] = true
	return _run_reachable(c.rank, ranks, 0)

## Whether a run of at least MIN_MELD_SIZE cards covering `target` fits within one
## suit given the natural ranks present and `jokers` wildcards to fill gaps or
## extend the ends. Tries the ace both low and high, never wrapping.
func _run_reachable(target: int, ranks: Dictionary, jokers: int) -> bool:
	for ace_high in [false, true]:
		var present := {}
		for r: int in ranks:
			present[14 if ace_high and r == 1 else r] = true
		var t := 14 if ace_high and target == 1 else target
		var low := 2 if ace_high else 1
		var high := 14 if ace_high else 13
		for s in range(low, t + 1):
			for e in range(t, high + 1):
				if e - s + 1 < Rules.MIN_MELD_SIZE:
					continue
				var nat := 0
				for r in range(s, e + 1):
					if present.has(r):
						nat += 1
				if (e - s + 1) - nat <= jokers:
					return true
	return false

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

# --- Freeform group dragging --------------------------------------------------

## Begin dragging a whole group by its move handle: remember which melds move
## together (a crossing/picture cluster moves as one lump) and where the cursor
## grabbed the panel, so _input can follow the motion. Disabled mid-AI-turn,
## when the board is being rebuilt under us. Purely visual — no engine move.
func begin_group_drag(panel: Control, melds: Array[CardSet]) -> void:
	if ai_running:
		return
	_group_drag = {"panel": panel, "melds": melds, "grab": panel.get_local_mouse_position()}
	panel.move_to_front()

## Follow and finish a group drag. Motion slides the live panel under the cursor
## (kept on the felt); release writes the resting spot onto every meld of the
## group and rebuilds the felt so the canvas re-measures its bounds.
func _input(event: InputEvent) -> void:
	if _group_drag.is_empty():
		return
	var panel: Control = _group_drag["panel"]
	if not is_instance_valid(panel):
		_group_drag = {}
		return
	if event is InputEventMouseMotion:
		var pos: Vector2 = board_flow.get_local_mouse_position() - (_group_drag["grab"] as Vector2)
		panel.position = Vector2(maxf(pos.x, 0.0), maxf(pos.y, 0.0))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var pos := Vector2(maxf(panel.position.x, 0.0), maxf(panel.position.y, 0.0))
		for m: CardSet in _group_drag["melds"]:
			m.board_pos = pos
		_group_drag = {}
		get_viewport().set_input_as_handled()
		_refresh()

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
	source.set_drag_preview(CardRenderer.make_drag_preview(cards))
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
	if at_position.x > UITheme.CARD_SIZE.x / 2.0:
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

## Right-click on any card: a joker you placed this turn opens the stand-in
## menu; everything else clears the selection.
func _on_card_gui_input(event: InputEvent, c: Card, meld: CardSet) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		if meld != null and c.is_joker and _show_joker_menu(c, meld):
			return
		_clear_selection()

## Right-click on the felt or the hand panel (not on a card) clears the
## selection.
func _on_background_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		_clear_selection()

func _clear_selection() -> void:
	if selected.is_empty():
		return
	selected.clear()
	_refresh()

## True when the player can still pick what this table joker stands for: it
## is their turn, they placed the joker this turn (a joker locks the moment
## its group is valid, and only the placer may re-point it before the turn
## ends), and the group actually offers a choice.
func _joker_is_rechoosable(joker: Card, meld: CardSet) -> bool:
	return _card_is_interactive(meld) and gm.placed_this_turn(joker) \
		and not Rules.rechoice_alternatives(meld.cards, joker).is_empty()

## Menu of the cards a joker placed this turn could stand for; picking one
## re-locks the joker to it (an undoable move). Returns false when there is
## nothing to choose, so the right-click can fall through to deselection.
func _show_joker_menu(joker: Card, meld: CardSet) -> bool:
	if not _joker_is_rechoosable(joker, meld):
		return false
	Rules.assign_jokers(meld.cards)
	var alts := Rules.rechoice_alternatives(meld.cards, joker)
	var menu := PopupMenu.new()
	add_child(menu)
	for i in alts.size():
		var alt: Dictionary = alts[i]
		menu.add_radio_check_item("Stands for %s" % _rep_text(alt["rank"], alt["suit"]), i)
		menu.set_item_checked(i,
			alt["rank"] == joker.joker_rank and alt["suit"] == joker.joker_suit)
	menu.id_pressed.connect(func(id: int) -> void:
		var alt: Dictionary = alts[id]
		_set_status(gm.set_joker_stand_in(joker, meld, alt["rank"], alt["suit"]))
		_refresh())
	menu.popup_hide.connect(menu.queue_free)
	menu.position = Vector2i(get_global_mouse_position())
	menu.popup()
	return true

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

# --- Plays off a picture --------------------------------------------------------

## A ghost cell beside a picture: drop cards (or click with a selection) to
## lay them as a line reading outward from that picture card.
func _can_drop_line_start(_at_position: Vector2, data: Variant, _anchor: Card,
		_step: Vector2i) -> bool:
	return _is_human_turn() and not _drag_cards(data).is_empty()

func _drop_line_start(_at_position: Vector2, data: Variant, anchor: Card,
		step: Vector2i) -> void:
	_play_line_start(anchor, step, _drag_cards(data))

func _on_line_start_pressed(anchor: Card, step: Vector2i) -> void:
	_play_line_start(anchor, step, selected.duplicate())

## The ghost at an existing extension line's outward end: same flow as
## dropping on the line itself (add_cards_to_meld routes it as an extension).
func _on_extend_line_pressed(meld: CardSet) -> void:
	_stage_move(selected.duplicate(), meld)

func _play_line_start(anchor: Card, step: Vector2i, cards: Array[Card]) -> void:
	if cards.is_empty():
		return
	var err := gm.play_off_picture(anchor, step, cards)
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

## "Sort": tidy the freeform felt back into a readable arrangement. Straights
## come first — by colour, then by their starting rank — and sets after, by
## rank; any group that is momentarily invalid (mid-rearrange) keeps its place
## at the end. Groups the player has scattered are cleared of their spots and
## re-laid in that order (left to right, wrapping down the felt) — the sort
## doing as best it can to organize whatever the table has become.
func _on_sort_board_pressed() -> void:
	if ai_running:
		return
	var keyed: Array = []
	for i in gm.board.melds.size():
		keyed.append({"meld": gm.board.melds[i], "key": _board_meld_key(gm.board.melds[i], i)})
	keyed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _key_less(a["key"], b["key"]))
	var out: Array[CardSet] = []
	for e: Dictionary in keyed:
		out.append(e["meld"])
	gm.board.melds.assign(out)
	_reset_board_positions()
	_refresh()

## Clear every group's spot on the felt so the next refresh re-places them all
## from scratch, in board order — the tidy packing Sort and Randomize rely on.
func _reset_board_positions() -> void:
	for m in gm.board.melds:
		m.board_pos = CardSet.UNPLACED

## The ⟳ control on a group: stand it upright or lay it flat on the felt.
## Purely visual (like Sort/Randomize) — the group itself is untouched — but
## it exercises the orientation groundwork the crossing/picture layouts build on.
func _on_rotate_meld_pressed(meld: CardSet) -> void:
	meld.orientation = CardSet.Orientation.HORIZONTAL \
		if meld.orientation == CardSet.Orientation.VERTICAL \
		else CardSet.Orientation.VERTICAL
	_refresh()

## "Randomize": keep every group intact but shuffle where the groups sit on the
## table, to jog loose a rearrangement you had not spotted.
func _on_randomize_board_pressed() -> void:
	if ai_running:
		return
	gm.board.melds.shuffle()
	_reset_board_positions()
	_refresh()

## A lexicographic sort key for one table group, compared field by field:
##   [valid, type, primary, secondary, order]
## Valid groups sort ahead of broken ones (which keep their current order via the
## trailing `order`). Straights (type 0) come before sets (type 1). A straight is
## keyed by colour then starting rank; a set by rank then suit. Jokers are read
## as the card they currently stand for.
func _board_meld_key(meld: CardSet, order: int) -> Array:
	Rules.assign_jokers(meld.cards)
	var anchor: Card = Rules.display_order(meld.cards)[0]
	var suit := anchor.joker_suit if anchor.is_joker else anchor.suit
	var rank := anchor.joker_rank if anchor.is_joker else anchor.rank
	var suit_order: int = SUIT_ORDER.get(suit, 99)
	if not meld.is_valid():
		return [1, 0, 0, 0, order]
	if Rules.is_valid_run(meld.cards):
		return [0, 0, suit_order, rank, order]  # straights: colour, then start
	return [0, 1, rank, suit_order, order]       # sets: rank, then suit

## True when key `a` sorts before key `b`, comparing element by element.
func _key_less(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] != b[i]:
			return a[i] < b[i]
	return false

## "Sort: rank": lay the hand out by rank, increasing from left to right; ties
## break by suit. Jokers sort to the end.
func _on_sort_rank_pressed() -> void:
	gm.players[0].hand.sort_custom(func(a: Card, b: Card) -> bool:
		if a.is_joker != b.is_joker:
			return b.is_joker
		if a.rank != b.rank:
			return a.rank < b.rank
		return a.suit < b.suit)
	_refresh()

## "Sort: suit": lay the hand out grouped by suit, reds then blacks, each suit in
## rank order. Jokers sort to the end.
func _on_sort_suit_pressed() -> void:
	gm.players[0].hand.sort_custom(func(a: Card, b: Card) -> bool:
		if a.is_joker != b.is_joker:
			return b.is_joker
		var order_a: int = SUIT_ORDER.get(a.suit, 99)
		var order_b: int = SUIT_ORDER.get(b.suit, 99)
		if order_a != order_b:
			return order_a < order_b
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

## A committed hand charged a meter; only announce the moment it fills, so the
## log stays quiet while meters tick up. The bars themselves show the running
## charge (refreshed with the rest of the table after the turn).
func _on_meter_charged(p: PlayerState, _amount: int, now_full: bool) -> void:
	if now_full:
		_log("[b]%s's ultimate meter is fully charged![/b]" % p.display_name)

## Announce a draw as one line. Your own cards are named (a single card, or
## "2 cards, X and Y" for a multi-draw); an opponent's stay face-down, so only
## the count shows.
func _on_cards_drawn(p: PlayerState, cards: Array[Card]) -> void:
	var n := cards.size()
	if p == gm.players[0]:
		if n == 1:
			_log("You drew %s." % cards[0].label())
		else:
			_log("You drew %d cards, %s." % [n, _join_card_labels(cards)])
	elif n == 1:
		_log("%s drew a card." % p.display_name)
	else:
		# An opponent's cards stay face-down — announce the count, not the faces.
		_log("%s drew %d cards." % [p.display_name, n])

## Join card labels for a log line: "X", "X and Y", or "X, Y and Z".
func _join_card_labels(cards: Array[Card]) -> String:
	var labels := PackedStringArray()
	for c in cards:
		labels.append(c.label())
	if labels.size() == 1:
		return labels[0]
	var head := ", ".join(labels.slice(0, labels.size() - 1))
	return "%s and %s" % [head, labels[labels.size() - 1]]

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
		else AIProfile.new(settings.ai_strength, settings.ai_style, settings.ai_attention, -1, settings.ai_planning)
	# The designed enemy drives its strategy (e.g. the slime guarding jokers).
	var enemy_def: Enemy = current_enemy if in_rogue else null
	highlighted.clear()
	_refresh()
	while not gm.is_game_over and gm.current_player().is_opponent:
		var enemy := gm.current_player()
		_set_status("%s is thinking…" % enemy.display_name)
		_refresh()
		await get_tree().create_timer(AI_THINK_DELAY).timeout
		if gen != game_generation:
			return
		while true:
			var move: Dictionary = GreedyAI.plan_move(gm, profile, enemy_def)
			if move.is_empty():
				break
			var moved: Array[Card] = move["cards"]
			var sources := animator.capture_positions(enemy, moved, card_nodes, opponent_backs)
			GreedyAI.apply_move(gm, move, profile)
			for c in moved:
				highlighted[c] = true
			_log("%s %s." % [enemy.display_name, move["text"]])
			_refresh()
			await animator.animate(moved, sources, card_nodes)
			if gen != game_generation:
				return
			await get_tree().create_timer(AI_MOVE_DELAY).timeout
			if gen != game_generation:
				return
		# A turn that laid a card from hand commits; a turn that only reworked the
		# table (the slime herding her slime) draws, and GameManager keeps that
		# valid rearrangement on the felt instead of rolling it back.
		if gm.cards_played_this_turn() > 0:
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

# --- Misc ----------------------------------------------------------------------

func _set_status(msg: String) -> void:
	status_label.text = msg

func _log(msg: String) -> void:
	log_box.append_text(msg + "\n")
