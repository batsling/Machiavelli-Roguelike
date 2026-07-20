extends SceneTree

## Headless check for the board-layout groundwork: meld orientation surviving
## snapshots, crossing groups sharing one card (both valid, both extendable,
## undoable, committable), shape (picture) groups on a grid, BoardGrid cluster
## and adjacency math, and the cluster/vertical rendering paths. Run:
##   godot --headless --path . --script res://tests/layout_check.gd

func _card(rank: int, suit: String) -> Card:
	var c := Card.new()
	c.suit = suit
	c.rank = rank
	return c

func _meld(cards: Array[Card]) -> CardSet:
	var m := CardSet.new()
	m.cards = cards
	return m

var ok := true

func _fail(msg: String) -> void:
	printerr(msg)
	ok = false

func _init() -> void:
	_test_orientation_snapshot()
	_test_cross_meld()
	_test_cross_meld_undo_and_removal()
	_test_shape_groups()
	_test_board_grid()
	await _test_rendering()
	if ok:
		print("layout_check: PASS")
		quit(0)
	else:
		printerr("layout_check: FAIL")
		quit(1)

## Orientation and shape cells are part of the board snapshot, so an undo puts
## the layout back, not just the membership.
func _test_orientation_snapshot() -> void:
	var board := Board.new()
	var run := _meld([_card(3, "clubs"), _card(4, "clubs"), _card(5, "clubs")])
	run.orientation = CardSet.Orientation.VERTICAL
	board.melds.append(run)
	var pic := CardSet.new()
	var a := _card(9, "hearts")
	var b := _card(9, "spades")
	var c := _card(9, "clubs")
	pic.set_shape({a: Vector2i(0, 0), b: Vector2i(1, 0), c: Vector2i(1, 1)})
	board.melds.append(pic)
	var snap := board.snapshot()
	board.melds[0].orientation = CardSet.Orientation.HORIZONTAL
	board.melds[1].shape_cells.clear()
	board.restore(snap)
	if board.melds[0].orientation != CardSet.Orientation.VERTICAL:
		_fail("restore should bring back the vertical orientation")
	if not board.melds[1].is_shape() or board.melds[1].cell_of(c) != Vector2i(1, 1):
		_fail("restore should bring back the shape cells")

## A game manager with a hand-built table: one horizontal run 3-4-5C on the
## felt, the player open, holding the cards the test wants to play.
func _staged_gm(hand: Array[Card]) -> GameManager:
	var gm := GameManager.new()
	gm.setup(["You", "Foe"], 5, 7)
	gm.board.melds.clear()
	gm.board.melds.append(_meld([_card(3, "clubs"), _card(4, "clubs"), _card(5, "clubs")]))
	gm.players[0].has_opened = true
	gm.players[0].hand = hand.duplicate()
	gm._hand_snapshot = hand.duplicate()
	gm._undo_stack.clear()
	return gm

## stage_cross_meld: the pivot joins a new perpendicular group without leaving
## its host; both groups are valid and the turn commits.
func _test_cross_meld() -> void:
	var four_d := _card(4, "diamonds")
	var four_h := _card(4, "hearts")
	var gm := _staged_gm([four_d, four_h, _card(11, "spades")])
	var host: CardSet = gm.board.melds[0]
	var pivot: Card = host.cards[1]  # the 4C
	var err := gm.stage_cross_meld(pivot, [four_d, four_h] as Array[Card])
	if err != "":
		_fail("stage_cross_meld should succeed, got: %s" % err)
		return
	if gm.board.melds.size() != 2:
		_fail("crossing should add one new group, got %d" % gm.board.melds.size())
		return
	var cross: CardSet = gm.board.melds[1]
	if cross.orientation != CardSet.Orientation.VERTICAL:
		_fail("a cross on a horizontal group should lie vertical")
	if gm.board.melds_of(pivot).size() != 2:
		_fail("the pivot should sit in both groups, got %d" % gm.board.melds_of(pivot).size())
	if not host.is_valid() or not cross.is_valid():
		_fail("both crossing groups should be valid with the pivot counted in")
	var hits := gm.board.intersections()
	if hits.size() != 1 or hits[0]["card"] != pivot:
		_fail("intersections() should report the pivot")
	# Both groups still take cards: extend the cross with the fourth four.
	var four_s := _card(4, "spades")
	gm.players[0].hand.append(four_s)
	gm._hand_snapshot.append(four_s)
	if gm.add_cards_to_meld([four_s] as Array[Card], cross) != "":
		_fail("the crossing group should still accept lay-offs")
	if gm.commit_turn() != "":
		_fail("a turn ending on a valid crossing should commit")
	if gm.stage_cross_meld(pivot, [_card(4, "spades")] as Array[Card]) == "":
		_fail("a pivot already shared must refuse a second crossing")
	gm.free()

## Undo unwinds a staged crossing completely, and pulling the pivot off the
## table removes it from BOTH groups.
func _test_cross_meld_undo_and_removal() -> void:
	var four_d := _card(4, "diamonds")
	var four_h := _card(4, "hearts")
	var gm := _staged_gm([four_d, four_h])
	var host: CardSet = gm.board.melds[0]
	var pivot: Card = host.cards[1]
	if gm.stage_cross_meld(pivot, [four_d, four_h] as Array[Card]) != "":
		_fail("crossing setup failed")
		return
	if not gm.undo_action():
		_fail("a staged crossing should be undoable")
		return
	if gm.board.melds.size() != 1 or gm.board.melds_of(pivot).size() != 1:
		_fail("undo should dissolve the crossing and leave the pivot in its host")
	if gm.players[0].hand.size() != 2:
		_fail("undo should return the crossed cards to the hand")
	# Re-stage, then take the pivot off the table: it leaves both groups.
	if gm.stage_cross_meld(gm.board.melds[0].cards[1], [four_d, four_h] as Array[Card]) != "":
		_fail("re-staging the crossing failed")
		return
	var shared: Card = gm.board.intersections()[0]["card"]
	gm.board.remove_card(shared)
	for m in gm.board.melds:
		if m.cards.has(shared):
			_fail("removing a shared card should pull it out of every group")
	gm.free()

## Shape groups: valid when one connected picture, invalid when torn apart;
## the line helpers read straight lines out of the picture.
func _test_shape_groups() -> void:
	var cards: Array[Card] = []
	for i in CuteSlime.ULT_HEART.size():
		cards.append(_card((i % 13) + 1, "hearts"))
	var heart := CuteSlime.build_shape_meld(CuteSlime.ULT_HEART, cards)
	if heart == null or not heart.is_shape():
		_fail("the heart template should build a shape group")
		return
	if not heart.is_valid():
		_fail("the heart picture should be a well-formed (connected) shape")
	# The heart's widest rows are 5 cards; line_through reads them off.
	var row_card := heart.card_at(Vector2i(0, 1))
	if heart.line_through(row_card, true).size() != 5:
		_fail("the heart's second row should be a 5-card line")
	if heart.line_through(heart.card_at(Vector2i(2, 4)), false).size() != 4:
		_fail("the heart's spine should be a 4-card vertical line")
	# A disconnected picture is not a valid shape.
	var torn := CardSet.new()
	torn.set_shape({_card(2, "clubs"): Vector2i(0, 0), _card(3, "clubs"): Vector2i(1, 0),
		_card(4, "clubs"): Vector2i(5, 5)})
	if torn.is_valid():
		_fail("a disconnected shape must not be valid")
	# Wrong card count for the template is refused.
	if CuteSlime.build_shape_meld(CuteSlime.ULT_HEART,
			[_card(2, "clubs")] as Array[Card]) != null:
		_fail("build_shape_meld must refuse a card count that doesn't fill the template")

## BoardGrid: a cross lays out as one cluster with the pivot at the shared
## cell, and neighbors() reads adjacency straight off the grid.
func _test_board_grid() -> void:
	var board := Board.new()
	var three_c := _card(3, "clubs")
	var four_c := _card(4, "clubs")
	var five_c := _card(5, "clubs")
	var host := _meld([three_c, four_c, five_c])
	board.melds.append(host)
	var four_d := _card(4, "diamonds")
	var four_h := _card(4, "hearts")
	var cross := _meld([four_c, four_d, four_h])  # shares the 4C
	cross.orientation = CardSet.Orientation.VERTICAL
	board.melds.append(cross)
	var lone := _meld([_card(9, "hearts"), _card(9, "spades"), _card(9, "clubs")])
	board.melds.append(lone)

	var clusters := BoardGrid.clusters(board)
	if clusters.size() != 2:
		_fail("expected 2 clusters (the cross and the lone set), got %d" % clusters.size())
		return
	var cluster: Dictionary = clusters[0]
	if (cluster["melds"] as Array).size() != 2:
		_fail("the cross cluster should hold both groups")
	if cluster["size"] != Vector2i(3, 3):
		_fail("the cross should span a 3x3 grid, got %s" % cluster["size"])
	var cells: Dictionary = cluster["cells"]
	# Host row across the top, the cross hanging below the shared 4C.
	if cells.get(Vector2i(1, 0)) != four_c:
		_fail("the shared 4C should sit where the groups meet")
	if cells.get(Vector2i(0, 0)) != three_c or cells.get(Vector2i(2, 0)) != five_c:
		_fail("the host run should lie across the top row")
	if cells.get(Vector2i(1, 1)) != four_d or cells.get(Vector2i(1, 2)) != four_h:
		_fail("the cross should hang below the pivot in display order")
	if cluster["meld_at"].get(Vector2i(1, 0)) != host:
		_fail("the shared cell should answer for its host group")
	var around := BoardGrid.neighbors(board, four_c)
	if around.size() != 3 or not around.has(three_c) or not around.has(five_c) \
			or not around.has(four_d):
		_fail("the pivot's neighbors should be 3C, 5C and 4D")
	if BoardGrid.neighbors(board, four_h).size() != 1:
		_fail("the tail of the cross has exactly one neighbor")

## Rendering: a vertical group lays its cards out in a column, and a cross
## renders as one grid panel with gaps where no card sits.
func _test_rendering() -> void:
	var ui: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(ui)
	await process_frame
	await process_frame
	ui._on_play_vanilla_pressed()
	await process_frame

	var upright := _meld([_card(3, "clubs"), _card(4, "clubs"), _card(5, "clubs")])
	upright.orientation = CardSet.Orientation.VERTICAL
	var host := _meld([_card(7, "hearts"), _card(8, "hearts"), _card(9, "hearts")])
	var cross := _meld([host.cards[1], _card(8, "spades"), _card(8, "diamonds")])
	cross.orientation = CardSet.Orientation.VERTICAL
	ui.gm.board.melds = [upright, host, cross] as Array[CardSet]
	ui._refresh()
	await process_frame

	var upright_btn: Button = ui.card_nodes.get(upright.cards[0])
	if upright_btn == null or not (upright_btn.get_parent() is VBoxContainer):
		_fail("a vertical group should render its cards in a column")
	var pivot_btn: Button = ui.card_nodes.get(host.cards[1])
	if pivot_btn == null or not (pivot_btn.get_parent() is GridContainer):
		_fail("crossing groups should render on a grid")
	else:
		var grid := pivot_btn.get_parent() as GridContainer
		if grid.columns != 3 or grid.get_child_count() != 9:
			_fail("the cross grid should be 3x3 (cards + gap fillers), got %d cols %d cells"
				% [grid.columns, grid.get_child_count()])
		var buttons := 0
		for child in grid.get_children():
			if child is Button:
				buttons += 1
		if buttons != 5:
			_fail("the cross grid should hold 5 card buttons, got %d" % buttons)
	ui.queue_free()
	await process_frame
