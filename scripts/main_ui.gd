extends Control

## Minimal playable UI for vanilla Machiavelli, built entirely in code so the
## scene file stays trivial.
##
## How to play: on your turn, click cards to select them — from your hand AND
## from any meld on the table (rearranging the table is the heart of the game).
## Then either press "Selected → new group" or a group's "+" button to move
## them. The table only has to be valid when you press "End turn"; "Undo turn"
## puts everything back. If you can't (or won't) play, "Draw & end turn".

const AI_TURN_DELAY := 0.6
const RED_SUITS := ["hearts", "diamonds"]
const CARD_RED := Color(0.85, 0.25, 0.25)

var gm: GameManager
var selected: Array[Card] = []
var ai_running := false

var players_label: Label
var stock_label: Label
var status_label: Label
var log_box: RichTextLabel
var board_box: VBoxContainer
var hand_box: HFlowContainer
var new_meld_btn: Button
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
	selected.clear()
	ai_running = false
	gm.setup(["You", "Rosso", "Nero"])
	log_box.clear()
	_set_status("Your turn. Play at least one card, or draw.")
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

	players_label = Label.new()
	root.add_child(players_label)

	stock_label = Label.new()
	root.add_child(stock_label)

	var table_title := Label.new()
	table_title.text = "Table"
	root.add_child(table_title)

	var board_scroll := ScrollContainer.new()
	board_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(board_scroll)
	board_box = VBoxContainer.new()
	board_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_box.add_theme_constant_override("separation", 4)
	board_scroll.add_child(board_box)

	var hand_title := Label.new()
	hand_title.text = "Your hand"
	root.add_child(hand_title)

	hand_box = HFlowContainer.new()
	hand_box.add_theme_constant_override("h_separation", 4)
	hand_box.add_theme_constant_override("v_separation", 4)
	root.add_child(hand_box)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	root.add_child(actions)

	new_meld_btn = Button.new()
	new_meld_btn.text = "Selected → new group"
	new_meld_btn.pressed.connect(_on_new_meld_pressed)
	actions.add_child(new_meld_btn)

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
	log_box.custom_minimum_size = Vector2(0, 110)
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
	var parts := PackedStringArray()
	for p in gm.players:
		var marker := ""
		if p == gm.current_player() and not gm.is_game_over:
			marker = "▶ "
		parts.append("%s%s: %d cards" % [marker, p.display_name, p.hand.size()])
	players_label.text = "    ".join(parts)
	stock_label.text = "Stock: %d cards" % gm.deck.size()

func _refresh_board() -> void:
	_clear_children(board_box)
	if gm.board.melds.is_empty():
		var empty := Label.new()
		empty.text = "(table is empty)"
		board_box.add_child(empty)
		return
	for meld in gm.board.melds:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var add_btn := Button.new()
		add_btn.text = "+"
		add_btn.tooltip_text = "Move selected cards into this group"
		add_btn.disabled = selected.is_empty() or not _is_human_turn()
		add_btn.pressed.connect(_on_add_to_meld_pressed.bind(meld))
		row.add_child(add_btn)
		for c in Rules.display_order(meld.cards):
			row.add_child(_make_card_button(c))
		var validity := Label.new()
		validity.text = "✓" if meld.is_valid() else "✗"
		row.add_child(validity)
		board_box.add_child(row)

func _refresh_hand() -> void:
	_clear_children(hand_box)
	for c in Rules.display_order(gm.players[0].hand):
		hand_box.add_child(_make_card_button(c))

func _refresh_buttons() -> void:
	var human_turn := _is_human_turn()
	new_meld_btn.disabled = not human_turn or selected.is_empty()
	reset_btn.disabled = not human_turn
	end_turn_btn.disabled = not human_turn
	draw_btn.disabled = not human_turn

func _make_card_button(c: Card) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.text = c.label()
	b.button_pressed = selected.has(c)
	b.custom_minimum_size = Vector2(52, 40)
	b.disabled = not _is_human_turn()
	if RED_SUITS.has(c.suit):
		b.add_theme_color_override("font_color", CARD_RED)
		b.add_theme_color_override("font_pressed_color", CARD_RED)
		b.add_theme_color_override("font_hover_color", CARD_RED)
	b.toggled.connect(_on_card_toggled.bind(c))
	return b

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

func _run_ai_turns() -> void:
	if ai_running or gm.is_game_over:
		return
	ai_running = true
	_refresh()
	while not gm.is_game_over and gm.current_player().is_opponent:
		await get_tree().create_timer(AI_TURN_DELAY).timeout
		GreedyAI.take_turn(gm)
		_refresh()
	ai_running = false
	if not gm.is_game_over:
		_set_status("Your turn. Play at least one card, or draw.")
	_refresh()

# --- Misc ----------------------------------------------------------------------

func _set_status(msg: String) -> void:
	status_label.text = msg

func _log(msg: String) -> void:
	log_box.append_text(msg + "\n")
