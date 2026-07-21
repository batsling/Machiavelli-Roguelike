extends SceneTree

## Headless check for two visibility aids:
##   1. Hovering an opponent whose hand holds a visible-status card (a glass card)
##      pops an enlarged reveal of that hand — glass cards face-up, the rest as
##      plain backs; a plain opponent grows no reveal.
##   2. A hand card that can be played right now (no rearranging) is capped with a
##      green play marker, matching the green its destination group lights on hover.
## Run: godot --headless --path . --script res://tests/opponent_view_check.gd

func _card(rank: int, suit: String) -> Card:
	var c := Card.new()
	c.suit = suit
	c.rank = rank
	return c

func _glass(rank: int, suit: String) -> Card:
	var c := _card(rank, suit)
	c.effects.append(Card.Effect.CLEAR)
	return c

func _meld(cards: Array[Card]) -> CardSet:
	var m := CardSet.new()
	m.cards = cards
	return m

## Does button `b` carry a green play-marker strip (a Panel filled COL_HINT_EDGE)?
func _has_play_marker(b: Button) -> bool:
	for child in b.get_children():
		if child is Panel:
			var sb: StyleBoxFlat = (child as Panel).get_theme_stylebox("panel")
			if sb != null and sb.bg_color == UITheme.COL_HINT_EDGE:
				return true
	return false

func _init() -> void:
	var ui: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui._on_play_vanilla_pressed()
	await process_frame
	var ok := true

	# --- 1. The opponent-hand reveal --------------------------------------------
	# The visible-status gate: a plain hand hides the reveal, a glass card unlocks it.
	var plain_hand: Array[Card] = [_card(3, "clubs"), _card(9, "hearts")]
	if ui._hand_has_visible_card(plain_hand):
		printerr("a hand with no glass card should not unlock the reveal")
		ok = false
	var mixed_hand: Array[Card] = [_card(3, "clubs"), _glass(9, "hearts"), _card(4, "spades")]
	if not ui._hand_has_visible_card(mixed_hand):
		printerr("a hand with a glass card should unlock the reveal")
		ok = false

	# Give the opponent a known mixed hand and show its reveal.
	ui.gm.players[1].hand = mixed_hand.duplicate()
	ui._refresh()
	await process_frame
	if ui.opponent_hand_overlay.visible:
		printerr("the reveal should start hidden")
		ok = false
	ui._show_opponent_hand(1)
	await process_frame
	if not ui.opponent_hand_overlay.visible:
		printerr("hovering an opponent with a glass card should show the reveal")
		ok = false
	if ui.opponent_hand_body.get_child_count() != mixed_hand.size():
		printerr("the reveal should render every card of the hand, got %d of %d"
			% [ui.opponent_hand_body.get_child_count(), mixed_hand.size()])
		ok = false
	# The glass card shows a face (a Panel carrying a Label); the naturals are
	# plain backs (a Panel with no Label child).
	var faces := 0
	var backs := 0
	for node in ui.opponent_hand_body.get_children():
		var has_label := false
		for sub in node.get_children():
			if sub is Label:
				has_label = true
		if has_label:
			faces += 1
		else:
			backs += 1
	if faces != 1 or backs != 2:
		printerr("reveal should show 1 glass face and 2 backs, got %d faces / %d backs"
			% [faces, backs])
		ok = false
	ui._hide_opponent_hand()
	if ui.opponent_hand_overlay.visible:
		printerr("leaving the seat should hide the reveal")
		ok = false

	# --- 2. The green play marker on immediately-playable hand cards -------------
	ui.gm.players[0].has_opened = true
	var run := _meld([_card(5, "hearts"), _card(6, "hearts"), _card(7, "hearts")])
	ui.gm.board.melds = [run] as Array[CardSet]
	var eight_h := _card(8, "hearts")   # lays off onto the run
	var two_c := _card(2, "clubs")      # fits nowhere, makes no group
	ui.gm.players[0].hand = [eight_h, two_c] as Array[Card]
	ui._refresh()
	await process_frame

	if not ui._card_is_playable_now(eight_h):
		printerr("8H should read as playable (lays off onto the 5-6-7H run)")
		ok = false
	if ui._card_is_playable_now(two_c):
		printerr("2C should read as unplayable")
		ok = false

	var eight_btn: Button = ui.card_nodes.get(eight_h)
	var two_btn: Button = ui.card_nodes.get(two_c)
	if eight_btn == null or not _has_play_marker(eight_btn):
		printerr("the playable 8H should carry the green play marker")
		ok = false
	if two_btn != null and _has_play_marker(two_btn):
		printerr("the dead 2C must not carry a play marker")
		ok = false

	# Not your turn → nothing is playable and no marker shows.
	ui.ai_running = true
	if ui._card_is_playable_now(eight_h):
		printerr("no card is playable while it isn't your turn")
		ok = false
	ui.ai_running = false

	if ok:
		print("opponent_view_check: PASS")
		quit(0)
	else:
		printerr("opponent_view_check: FAIL")
		quit(1)
