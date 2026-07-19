extends SceneTree

## Headless check for the hand suit-filter + colour-grouped sort. Run with:
##   godot --headless --path . --script res://tests/suit_filter_check.gd

func _init() -> void:
	var ui: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(ui)
	await process_frame
	await process_frame
	ui._on_play_vanilla_pressed()
	await process_frame
	var ok := true

	# --- Colour-grouped straight sort -----------------------------------------
	ui._on_sort_suit_pressed()
	await process_frame
	var order := {"hearts": 0, "diamonds": 1, "clubs": 2, "spades": 3}
	var prev := -1
	for c in ui.gm.players[0].hand:
		if c.is_joker:
			continue
		var rank_of: int = order.get(c.suit, 99)
		if rank_of < prev:
			printerr("suit sort not colour-grouped: %s after order %d" % [c.suit, prev])
			ok = false
		prev = rank_of
	# Jokers must sink to the end.
	var seen_joker := false
	for c in ui.gm.players[0].hand:
		if c.is_joker:
			seen_joker = true
		elif seen_joker:
			printerr("joker should sort last")
			ok = false

	# --- Suit filter hover ----------------------------------------------------
	# Pick a suit that is actually present in the hand so there is a match.
	var target := ""
	for c in ui.gm.players[0].hand:
		if not c.is_joker:
			target = c.suit
			break
	ui._on_suit_filter_enter(target)
	await process_frame
	if ui.hover_filter_suit != target:
		printerr("hover_filter_suit not set")
		ok = false
	for c in ui.gm.players[0].hand:
		var node: Button = ui.card_nodes.get(c)
		if node == null:
			continue
		var matches: bool = c.is_joker or c.suit == target
		var faded := node.modulate.a < 0.999
		if matches and faded:
			printerr("matching card %s should not be faded" % c.label())
			ok = false
		if not matches and not faded:
			printerr("non-matching card %s should be faded" % c.label())
			ok = false
		# Matching, un-selected, un-highlighted cards get the filter outline.
		if matches and not c.is_joker and not ui.selected.has(c) and not ui.highlighted.has(c):
			var sb: StyleBoxFlat = node.get_theme_stylebox("normal")
			if sb.border_color != ui.COL_FILTER_EDGE:
				printerr("matching card %s missing filter outline" % c.label())
				ok = false

	# Leaving the suit clears the filter and restores every card.
	ui._on_suit_filter_exit(target)
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
