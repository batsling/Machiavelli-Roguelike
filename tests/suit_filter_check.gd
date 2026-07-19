extends SceneTree

## Headless check for the hand suit-filter and the table Sort/Randomize. Run:
##   godot --headless --path . --script res://tests/suit_filter_check.gd

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
	root.add_child.call_deferred(ui)
	await process_frame
	await process_frame
	ui._on_play_vanilla_pressed()
	await process_frame
	var ok := true

	# --- Table Sort: straights first (colour, then start rank), sets by rank ---
	var heart_run := _meld([_card(5, "hearts"), _card(6, "hearts"), _card(7, "hearts")])
	var club_run := _meld([_card(3, "clubs"), _card(4, "clubs"), _card(5, "clubs")])
	var set_9 := _meld([_card(9, "hearts"), _card(9, "diamonds"), _card(9, "spades")])
	var set_2 := _meld([_card(2, "diamonds"), _card(2, "clubs"), _card(2, "spades")])
	var board: Array[CardSet] = [set_9, club_run, set_2, heart_run]
	ui.gm.board.melds = board

	ui._on_sort_board_pressed()
	await process_frame
	var want: Array[CardSet] = [heart_run, club_run, set_2, set_9]
	if ui.gm.board.melds != want:
		printerr("table sort order wrong")
		for m in ui.gm.board.melds:
			printerr("  ", _labels(m.cards))
		ok = false

	# --- Table Randomize: keeps every group, just reorders them ----------------
	ui._on_randomize_board_pressed()
	await process_frame
	if ui.gm.board.melds.size() != want.size():
		printerr("randomize changed the group count")
		ok = false
	for m in want:
		if not ui.gm.board.melds.has(m):
			printerr("randomize dropped a group")
			ok = false

	# --- Hand suit filter hover -----------------------------------------------
	var hand: Array[Card] = [_card(5, "hearts"), _card(9, "diamonds"),
		_card(2, "clubs"), _card(7, "hearts"), _card(9, "spades")]
	ui.gm.players[0].hand = hand
	ui._refresh()
	await process_frame
	ui._on_suit_filter_enter("hearts")
	await process_frame
	if ui.hover_filter_suit != "hearts":
		printerr("hover_filter_suit not set")
		ok = false
	for c in ui.gm.players[0].hand:
		var node: Button = ui.card_nodes.get(c)
		if node == null:
			continue
		var matches: bool = c.suit == "hearts"
		var faded := node.modulate.a < 0.999
		if matches and faded:
			printerr("matching card %s should not be faded" % c.label())
			ok = false
		if not matches and not faded:
			printerr("non-matching card %s should be faded" % c.label())
			ok = false
		if matches:
			var sb: StyleBoxFlat = node.get_theme_stylebox("normal")
			if sb.border_color != UITheme.COL_FILTER_EDGE:
				printerr("matching card %s missing filter outline" % c.label())
				ok = false

	ui._on_suit_filter_exit("hearts")
	await process_frame
	if ui.hover_filter_suit != "":
		printerr("filter should clear on exit")
		ok = false
	for c in ui.gm.players[0].hand:
		var node: Button = ui.card_nodes.get(c)
		if node != null and node.modulate.a < 0.999:
			printerr("card %s still faded after filter cleared" % c.label())
			ok = false

	if ok:
		print("suit_filter_check: PASS")
		quit(0)
	else:
		printerr("suit_filter_check: FAIL")
		quit(1)

func _labels(cards: Array) -> Array:
	var out: Array = []
	for c in cards:
		out.append(c.label())
	return out
