extends SceneTree

## Headless check that the Riichi UI additions render: the face-up discard pile
## beside the stock, and the RIICHI seat badge. Run:
##   godot --headless --path . --script res://tests/riichi_view_check.gd

func _card(rank: int, suit: String) -> Card:
	var c := Card.new()
	c.suit = suit
	c.rank = rank
	return c

func _init() -> void:
	var ui: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui._on_play_vanilla_pressed()
	await process_frame
	var ok := true

	# The discard slot is empty until something is discarded.
	if ui.discard_slot.get_child_count() != 0:
		printerr("discard slot should start empty")
		ok = false

	# Discard a couple of cards and declare Riichi on seat 1, then refresh.
	ui.gm.deck.discard(_card(4, "hearts"))
	ui.gm.deck.discard(_card(9, "spades"))
	ui.gm.players[1].declared_riichi = true
	ui._refresh()
	await process_frame

	# The discard slot now shows a label plus the face-up cards.
	if ui.discard_slot.get_child_count() < 2:
		printerr("discard slot should render a count label and the face-up cards, got %d"
			% ui.discard_slot.get_child_count())
		ok = false

	# The declaring seat carries a RIICHI badge somewhere in its chip.
	if not _has_riichi_badge(ui.seat_top):
		printerr("the declaring opponent's seat should show a RIICHI badge")
		ok = false

	if ok:
		print("riichi_view_check: PASS")
		quit(0)
	else:
		printerr("riichi_view_check: FAIL")
		quit(1)

func _has_riichi_badge(node: Node) -> bool:
	if node is Label and (node as Label).text == "RIICHI":
		return true
	for child in node.get_children():
		if _has_riichi_badge(child):
			return true
	return false
