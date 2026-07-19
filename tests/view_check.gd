extends SceneTree

## Headless check for the table rendering + drag/drop that the interactive UI
## depends on: seats, board meld panels, the "+ New group" zone, card-node
## registration, drag-data extraction, and a new-group drop that opens the
## player. These paths aren't exercised by the other checks. Run:
##   godot --headless --path . --script res://tests/view_check.gd

func _card(rank: int, suit: String) -> Card:
	var c := Card.new()
	c.suit = suit
	c.rank = rank
	return c

func _meld(cards: Array[Card]) -> CardSet:
	var m := CardSet.new()
	m.cards = cards
	return m

func _init() -> void:
	var ui: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui.settings.enemy_count = 2
	ui._on_play_vanilla_pressed()
	await process_frame
	var ok := true

	# --- Seats: two opponents seated, each with a card-back container ----------
	if not ui.seat_top.visible:
		printerr("top seat should be visible with 2 enemies")
		ok = false
	if ui.opponent_backs.size() != 2:
		printerr("expected 2 opponent card-back containers, got %d" % ui.opponent_backs.size())
		ok = false

	# --- A known hand so the rest is deterministic ----------------------------
	var run: Array[Card] = [_card(3, "clubs"), _card(4, "clubs"), _card(5, "clubs")]
	var hand: Array[Card] = run.duplicate()
	hand.append(_card(9, "hearts"))
	hand.append(_card(2, "spades"))
	ui.gm.players[0].hand = hand
	ui._refresh()
	await process_frame
	if ui.hand_box.get_child_count() != hand.size():
		printerr("hand should render %d buttons, got %d" % [hand.size(), ui.hand_box.get_child_count()])
		ok = false
	for c in hand:
		if not ui.card_nodes.has(c):
			printerr("hand card %s not registered in card_nodes" % c.label())
			ok = false

	# --- Drag helpers: cards round-trip through drag data; a lone hand card
	#     expands to just itself (no slime cluster) -----------------------------
	var payload := {"type": "machiavelli_cards", "cards": run}
	var carried: Array = ui._drag_cards(payload)
	if carried.size() != run.size() or carried[0] != run[0]:
		printerr("_drag_cards did not round-trip the payload")
		ok = false
	var one: Array[Card] = [run[0]]
	var expanded: Array = ui._expand_sticky(one)
	if expanded.size() != 1 or expanded[0] != run[0]:
		printerr("_expand_sticky changed a lone hand card")
		ok = false

	# --- The "+ New group" zone only appears while cards are selected ---------
	if _has_new_group_zone(ui):
		printerr("new-group zone should be hidden with nothing selected")
		ok = false
	ui.selected.assign(run)
	ui._refresh()
	await process_frame
	if not _has_new_group_zone(ui):
		printerr("new-group zone should appear once cards are selected")
		ok = false

	# --- Dropping a valid hand group on new felt opens the player -------------
	ui.selected.clear()
	ui._drop_new_group(Vector2.ZERO, payload)
	await process_frame
	if ui.gm.board.melds.size() != 1:
		printerr("new-group drop should stage one meld, got %d" % ui.gm.board.melds.size())
		ok = false
	# The board now renders that meld's three cards as buttons.
	var board_cards := 0
	for panel in ui.board_flow.get_children():
		if panel is PanelContainer:
			board_cards += _count_buttons(panel)
	if board_cards != 3:
		printerr("board should render 3 card buttons for the staged meld, got %d" % board_cards)
		ok = false

	if ok:
		print("view_check: PASS")
		quit(0)
	else:
		printerr("view_check: FAIL")
		quit(1)

func _has_new_group_zone(ui: Control) -> bool:
	for child in ui.board_flow.get_children():
		if child is Button and (child as Button).text == "+ New group":
			return true
	return false

func _count_buttons(node: Node) -> int:
	var n := 0
	for child in node.get_children():
		if child is Button:
			n += 1
		n += _count_buttons(child)
	return n
