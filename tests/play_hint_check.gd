extends SceneTree

## Headless check for the hover-to-play hints: hovering a hand card lights up the
## board spots it can play into right now with no rearranging — a lay-off onto an
## existing group, or a brand-new group it forms with other cards in the hand.
## Run: godot --headless --path . --script res://tests/play_hint_check.gd

func _card(rank: int, suit: String) -> Card:
	var c := Card.new()
	c.suit = suit
	c.rank = rank
	return c

func _joker() -> Card:
	var c := Card.new()
	c.suit = "joker"
	c.is_joker = true
	return c

func _meld(cards: Array[Card]) -> CardSet:
	var m := CardSet.new()
	m.cards = cards
	return m

func _pick(hand: Array[Card], rank: int, suit: String) -> Card:
	for c in hand:
		if c.rank == rank and c.suit == suit:
			return c
	return null

func _init() -> void:
	var ui: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(ui)
	await process_frame
	await process_frame
	ui._on_play_vanilla_pressed()
	await process_frame
	var ok := true

	# --- Lay-off onto an existing run (player is open) -------------------------
	ui.gm.players[0].has_opened = true
	var run := _meld([_card(5, "hearts"), _card(6, "hearts"), _card(7, "hearts")])
	var set9 := _meld([_card(9, "hearts"), _card(9, "diamonds"), _card(9, "spades")])
	var board: Array[CardSet] = [run, set9]
	ui.gm.board.melds = board
	var eight_h := _card(8, "hearts")
	ui.gm.players[0].hand = [eight_h, _card(2, "clubs")] as Array[Card]

	ui._compute_play_hints(eight_h)
	if not ui.hint_meld_targets.has(run):
		printerr("8H should lay off onto the 5-6-7H run")
		ok = false
	if ui.hint_meld_targets.has(set9):
		printerr("8H should NOT lay off onto the set of nines")
		ok = false
	if ui.hint_new_group:
		printerr("a lone 8H forms no new group from the hand")
		ok = false

	# The dead card (2C) fits nowhere on this board and makes no group.
	ui.hint_meld_targets.clear()
	ui.hint_new_group = false
	ui._compute_play_hints(ui.gm.players[0].hand[1])
	if not ui.hint_meld_targets.is_empty() or ui.hint_new_group:
		printerr("2C should light up nothing")
		ok = false

	# --- Rendering: the hinted group panel is spotlighted ----------------------
	ui._compute_play_hints(eight_h)
	ui._table.refresh_board()
	await process_frame
	var run_card: Button = ui.card_nodes.get(run.cards[0])
	if run_card != null:
		# card -> its box -> the panel's handle+content column -> the group panel.
		var panel := run_card.get_parent().get_parent().get_parent() as PanelContainer
		var sb: StyleBoxFlat = panel.get_theme_stylebox("panel")
		if sb.border_color != UITheme.COL_HINT_EDGE:
			printerr("the hinted run panel should carry the play-hint border")
			ok = false

	# --- The opening rule gates lay-offs --------------------------------------
	ui.gm.players[0].has_opened = false
	ui.hint_meld_targets.clear()
	ui.hint_new_group = false
	ui._compute_play_hints(eight_h)
	if not ui.hint_meld_targets.is_empty():
		printerr("before opening, a lay-off onto a table group must not be hinted")
		ok = false
	ui.gm.players[0].has_opened = true

	# --- A brand-new group formed from cards already in the hand --------------
	ui.gm.board.melds = [] as Array[CardSet]
	var nine_h := _card(9, "hearts")
	ui.gm.players[0].hand = [nine_h, _card(9, "diamonds"), _card(9, "spades"),
		_card(2, "clubs")] as Array[Card]
	ui._compute_play_hints(nine_h)
	if not ui.hint_new_group:
		printerr("three nines in hand should light the new-group cue")
		ok = false
	if not ui.hint_meld_targets.is_empty():
		printerr("with an empty board there is nothing to lay off onto")
		ok = false

	# The cue renders as a spotlighted "New group" ghost on the felt.
	ui.selected.clear()
	ui._table.refresh_board()
	await process_frame
	var hint_zone_found := false
	for child in ui.board_flow.get_children():
		if child is PanelContainer:
			var sb2: StyleBoxFlat = (child as PanelContainer).get_theme_stylebox("panel")
			if sb2 != null and sb2.border_color == UITheme.COL_HINT_EDGE:
				hint_zone_found = true
	if not hint_zone_found:
		printerr("the new-group cue should render a spotlighted zone")
		ok = false

	# --- A run of naturals lights the cue -------------------------------------
	var run_lo := _card(5, "spades")
	ui.gm.players[0].hand = [run_lo, _card(6, "spades"), _card(7, "spades")] as Array[Card]
	ui._compute_play_hints(run_lo)
	if not ui.hint_new_group:
		printerr("5S + 6S + 7S should form a run (new-group cue)")
		ok = false

	# --- A run the hand can complete only with a joker is disregarded ---------
	# The hint should surface plays that need no wildcard, so a group that only
	# closes with a joker must NOT light the cue.
	var run_gap := _card(5, "spades")
	ui.gm.players[0].hand = [run_gap, _card(6, "spades"), _joker()] as Array[Card]
	ui._compute_play_hints(run_gap)
	if ui.hint_new_group:
		printerr("5S + 6S + a joker requires a joker — the cue must stay dark")
		ok = false

	# A set the hand can complete only with a joker is likewise disregarded.
	ui.gm.players[0].hand = [_card(4, "hearts"), _card(4, "clubs"), _joker()] as Array[Card]
	ui._compute_play_hints(ui.gm.players[0].hand[0])
	if ui.hint_new_group:
		printerr("two fours plus a joker requires a joker — the cue must stay dark")
		ok = false

	# A lone card with a joker but no partner makes no group.
	ui.gm.players[0].hand = [_card(5, "spades"), _joker()] as Array[Card]
	ui._compute_play_hints(ui.gm.players[0].hand[0])
	if ui.hint_new_group:
		printerr("one card plus one joker is only two — no group")
		ok = false

	# --- Double-click auto-play picks the play the marker promises ------------
	# _new_group_cards_for returns the exact cards of the group a card completes.
	ui.gm.players[0].hand = [_card(5, "spades"), _card(6, "spades"),
		_card(7, "spades")] as Array[Card]
	var a_run: Array = ui._new_group_cards_for(_pick(ui.gm.players[0].hand, 5, "spades"))
	if a_run.size() != 3:
		printerr("auto-play should gather the 5-6-7S run (got %d cards)" % a_run.size())
		ok = false

	# A rank with three suits in hand gathers the whole set.
	ui.gm.players[0].hand = [_card(9, "hearts"), _card(9, "diamonds"),
		_card(9, "spades"), _card(2, "clubs")] as Array[Card]
	var nines: Array = ui._new_group_cards_for(ui.gm.players[0].hand[0])
	if nines.size() != 3:
		printerr("auto-play should gather the three nines (got %d)" % nines.size())
		ok = false
	# The dead 2C forms nothing.
	if not ui._new_group_cards_for(ui.gm.players[0].hand[3]).is_empty():
		printerr("2C forms no group, so auto-play must gather nothing")
		ok = false

	# Integration: a green (playable) hand card keeps BOTH interactions — it can
	# still be dragged, and now it can also be double-clicked to auto-play.
	ui.gm.board.melds = [_meld([_card(5, "hearts"), _card(6, "hearts"),
		_card(7, "hearts")])] as Array[CardSet]
	var lay_run: CardSet = ui.gm.board.melds[0]
	var eight := _card(8, "hearts")
	ui.gm.players[0].hand = [eight, _card(2, "clubs")] as Array[Card]
	ui.gm.players[0].has_opened = true
	ui._refresh()
	await process_frame

	# The green cap is painted, and the card stays a live drag source: its button
	# is enabled and still catches the mouse (drag detection runs through it), so
	# the double-click never came at the cost of dragging. (Actual drag payloads —
	# _get_card_drag_data — are exercised end to end in view_check; that path can
	# only run mid-drag, when set_drag_preview is legal.)
	var eight_btn: Button = ui.card_nodes.get(eight)
	if eight_btn == null or eight_btn.disabled:
		printerr("a playable hand card must stay an enabled, draggable button")
		ok = false
	elif eight_btn.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		printerr("a playable hand card must still catch the mouse to be dragged")
		ok = false

	# And the double-click path lays it straight off onto the run on the felt.
	if not ui._auto_play_card(eight):
		printerr("double-clicking a playable 8H should stage a play")
		ok = false
	if not lay_run.cards.has(eight):
		printerr("auto-play should have laid the 8H onto the run")
		ok = false
	if ui.gm.players[0].hand.has(eight):
		printerr("the 8H should have left the hand once auto-played")
		ok = false

	if ok:
		print("play_hint_check: PASS")
		quit(0)
	else:
		printerr("play_hint_check: FAIL")
		quit(1)
