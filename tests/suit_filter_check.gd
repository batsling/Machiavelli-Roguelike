extends SceneTree

## Headless check for the hand controls: combo-aware Sort, combo-preserving
## Randomize, and the suit-filter hover. Run with:
##   godot --headless --path . --script res://tests/suit_filter_check.gd

func _card(rank: int, suit: String) -> Card:
	var c := Card.new()
	c.suit = suit
	c.rank = rank
	return c

func _joker() -> Card:
	var j := Card.new()
	j.suit = "joker"
	j.rank = 0
	j.is_joker = true
	return j

func _labels(cards: Array) -> Array:
	var out: Array = []
	for c in cards:
		out.append(c.label())
	return out

func _init() -> void:
	var ui: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(ui)
	await process_frame
	await process_frame
	ui._on_play_vanilla_pressed()
	await process_frame
	var ok := true

	# A hand with a clear heart run, a set of nines, one loose card and a joker,
	# fed in scrambled so ordering actually has to do something.
	var run_h: Array = [_card(5, "hearts"), _card(6, "hearts"), _card(7, "hearts")]
	var set_9: Array = [_card(9, "spades"), _card(9, "diamonds"), _card(9, "clubs")]
	var loose := _card(2, "diamonds")
	var jk := _joker()
	var hand: Array[Card] = [set_9[1], loose, run_h[0], jk, set_9[0], run_h[2], set_9[2], run_h[1]]
	ui.gm.players[0].hand = hand

	# --- Sort: straights first, then sets, loose cards then jokers last --------
	ui._on_sort_pressed()
	await process_frame
	var got := _labels(ui.gm.players[0].hand)
	var want := ["5♥", "6♥", "7♥", "9♣", "9♦", "9♠", "2♦", "★"]
	if got != want:
		printerr("sort order wrong: got %s want %s" % [got, want])
		ok = false

	# --- Randomize: combos stay glued together, order shuffled ----------------
	# Run 20 shuffles; every time the run and the set must each stay contiguous.
	for _i in 20:
		ui._on_randomize_pressed()
		await process_frame
		if not _is_contiguous(ui.gm.players[0].hand, run_h):
			printerr("randomize split the heart run")
			ok = false
			break
		if not _is_contiguous(ui.gm.players[0].hand, set_9):
			printerr("randomize split the nines")
			ok = false
			break

	# --- Suit filter hover ----------------------------------------------------
	ui._on_sort_pressed()
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
		var matches: bool = c.is_joker or c.suit == "hearts"
		var faded := node.modulate.a < 0.999
		if matches and faded:
			printerr("matching card %s should not be faded" % c.label())
			ok = false
		if not matches and not faded:
			printerr("non-matching card %s should be faded" % c.label())
			ok = false
		if matches and not c.is_joker:
			var sb: StyleBoxFlat = node.get_theme_stylebox("normal")
			if sb.border_color != ui.COL_FILTER_EDGE:
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

## True when every card in `combo` sits at consecutive positions in `hand`.
func _is_contiguous(hand: Array, combo: Array) -> bool:
	var positions: Array = []
	for c in combo:
		var idx := hand.find(c)
		if idx == -1:
			return false
		positions.append(idx)
	positions.sort()
	return positions[-1] - positions[0] == positions.size() - 1
