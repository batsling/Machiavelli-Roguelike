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
	_test_slime_ultimate()
	_test_slime_ultimate_gates()
	_test_ult_in_driven_games()
	_test_grid_line_rules()
	_test_play_off_picture()
	await _test_rendering()
	await _test_picture_ghost_cells()
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

func _slimed(rank: int, suit: String) -> Card:
	var c := _card(rank, suit)
	c.effects.append(Card.Effect.STICKY)
	return c

## A rogue-style 1v1 where the slime's seat is the current player: open,
## sticky-immune, meter full, with the given hand and table.
func _slime_gm(hand: Array[Card], melds: Array[CardSet]) -> GameManager:
	var gm := GameManager.new()
	gm.setup(["You", "Slime"], 5, 7)
	gm.board.melds.assign(melds)
	gm.turn_index = 1
	var her := gm.players[1]
	her.has_opened = true
	her.ignores_sticky = true
	her.meter = gm.meter_max
	her.hand = hand.duplicate()
	gm._begin_turn()
	return gm

## The ultimate: a full meter plus enough gatherable slime builds the biggest
## picture that fits, seals it as one lump, and resets the meter.
func _test_slime_ultimate() -> void:
	var slime := CuteSlime.new()
	# Table slime she can take legally: a fully slimed 5-card run (whole group
	# may leave) and a slimed 8 in a set of four (the leftover trio stays
	# valid). The clean set of jacks must not be touched.
	var run := _meld([_slimed(3, "hearts"), _slimed(4, "hearts"), _slimed(5, "hearts"),
		_slimed(6, "hearts"), _slimed(7, "hearts")])
	var eights := _meld([_slimed(8, "diamonds"), _card(8, "clubs"), _card(8, "spades"),
		_card(8, "hearts")])
	var jacks := _meld([_card(11, "hearts"), _card(11, "clubs"), _card(11, "spades")])
	# Three slimed naturals in hand: 5 + 1 + 3 = 9 — exactly the flower.
	var hand: Array[Card] = [_slimed(9, "diamonds"), _slimed(10, "diamonds"),
		_slimed(12, "hearts"), _card(2, "clubs")]
	var gm := _slime_gm(hand, [run, eights, jacks] as Array[CardSet])
	var move := slime.plan_strategy_move(gm)
	if not move.get("ult", false):
		_fail("a full meter with 9 gatherable slimed cards should fire the ultimate")
		gm.free()
		return
	if (move["cards"] as Array).size() != 9:
		_fail("the ultimate should fill the 9-card flower, got %d cards"
			% (move["cards"] as Array).size())
	GreedyAI.apply_move(gm, move)
	var picture: CardSet = gm.board.melds[-1]
	if not picture.is_shape() or picture.cards.size() != 9 or not picture.is_valid():
		_fail("the ultimate should leave a valid 9-card picture on the table")
	if gm.players[1].meter != 0:
		_fail("spending the ultimate should reset her meter, got %d" % gm.players[1].meter)
	if gm.board.meld_of(hand[0]) != picture:
		_fail("her slimed hand cards should be inside the picture")
	for m in gm.board.melds:
		if not m.is_valid():
			_fail("the ultimate left an invalid group behind: %d cards" % m.cards.size())
	if jacks.cards.size() != 3:
		_fail("the clean set of jacks must be untouched")
	if eights.cards.size() != 3:
		_fail("the slimed eight should leave its set of four (leftover trio valid)")
	# The picture is one sticky lump: lifting any card drags the whole picture.
	if picture.sticky_cluster(picture.cards[0]).size() != 9:
		_fail("the picture should move as one 9-card lump")
	if gm.commit_turn() != "":
		_fail("the turn ending on the ultimate should commit")
	# Her planner never unpicks the picture on later turns.
	if not GreedyAI._immovable_cards(gm).has(picture.cards[0]):
		_fail("picture cards should be immovable to every planner")
	gm.free()

## Gates: no ult below a full meter, and a full meter holds until the slime on
## offer can legally fill a template.
func _test_slime_ultimate_gates() -> void:
	var slime := CuteSlime.new()
	# Enough slime, but the meter isn't full.
	var run := _meld([_slimed(3, "hearts"), _slimed(4, "hearts"), _slimed(5, "hearts"),
		_slimed(6, "hearts"), _slimed(7, "hearts")])
	var hand: Array[Card] = [_slimed(9, "diamonds"), _slimed(10, "diamonds"),
		_slimed(12, "hearts"), _slimed(2, "hearts")]
	var gm := _slime_gm(hand, [run] as Array[CardSet])
	gm.players[1].meter = gm.meter_max - 1
	if slime.plan_strategy_move(gm).get("ult", false):
		_fail("the ultimate must wait for a full meter")
	gm.free()
	# Full meter, but the only table slime is locked into its group: a set of
	# three with one slimed card can't spare it (leftover pair invalid), and
	# 3 hand cards alone can't fill the 9-card flower.
	var trio := _meld([_slimed(6, "diamonds"), _card(6, "clubs"), _card(6, "spades")])
	var gm2 := _slime_gm([_slimed(9, "diamonds"), _slimed(10, "diamonds"),
		_slimed(12, "hearts")] as Array[Card], [trio] as Array[CardSet])
	var move := slime.plan_strategy_move(gm2)
	if move.get("ult", false):
		_fail("without enough legally gatherable slime the ultimate must hold")
	if trio.cards.size() != 3:
		_fail("planning alone must not touch the table")
	gm2.free()

## The ultimate fires inside real driven games: seeded 1v1s against the slime
## with a tiny per-card meter so it charges fast. Core invariants (valid
## table, card conservation) hold after every turn, every game still
## finishes, and at least one game grows a picture on the felt.
func _test_ult_in_driven_games() -> void:
	var pictures := 0
	for seed_value in [1, 2, 3]:
		var gm := GameManager.new()
		gm.setup(["You", "The Cute Slime"], 13, seed_value, true)
		gm.draw_per_turn = 2
		gm.max_plays_per_turn = 13
		gm.meter_max = 5
		gm.meter_gain = 1
		gm.meter_per_card = true
		var slime := CuteSlime.new()
		slime.on_combat_start(gm)
		var profile := slime.make_profile(seed_value)
		var turns := 0
		var saw_picture := false
		while not gm.is_game_over and turns < 400:
			var enemy: Enemy = slime if gm.current_player().is_opponent else null
			GreedyAI.take_turn(gm, profile, enemy)
			turns += 1
			if not gm.board.all_valid():
				_fail("ult game %d: invalid table after turn %d" % [seed_value, turns])
				break
			var count := gm.deck.size() + gm.board.all_cards().size()
			for p in gm.players:
				count += p.hand.size()
			if count != 108:
				_fail("ult game %d: card conservation broken (%d) after turn %d"
					% [seed_value, count, turns])
				break
			for m in gm.board.melds:
				if m.is_shape():
					saw_picture = true
		if not gm.is_game_over:
			_fail("ult game %d: did not finish within 400 turns" % seed_value)
		if saw_picture:
			pictures += 1
		gm.free()
	print("ult games: %d of 3 grew a picture" % pictures)
	if pictures == 0:
		_fail("no seeded ult game ever built a picture — the ultimate never fired")

## The Scrabble-style line reading: could-grow pairs and ordered grid lines.
func _test_grid_line_rules() -> void:
	if not Rules.could_pair(_card(7, "hearts"), _card(8, "hearts")):
		_fail("7H beside 8H could grow into a run")
	if not Rules.could_pair(_card(1, "spades"), _card(13, "spades")):
		_fail("an ace beside a king could grow ace-high")
	if not Rules.could_pair(_card(7, "hearts"), _card(7, "spades")):
		_fail("two sevens of different suits could grow into a set")
	if Rules.could_pair(_card(7, "hearts"), _card(7, "hearts")):
		_fail("two copies of the same card can never share a group")
	if Rules.could_pair(_card(2, "clubs"), _card(9, "diamonds")):
		_fail("2C beside 9D is a dead pair")
	if Rules.could_pair(_card(5, "hearts"), _card(7, "hearts")):
		_fail("a one-rank gap is dead on the grid — there is no room for the 6")
	var run_line: Array[Card] = [_card(7, "hearts"), _card(8, "hearts"), _card(9, "hearts")]
	if not Rules.is_valid_grid_line(run_line):
		_fail("7-8-9 of hearts should read as a grid run")
	var scrambled: Array[Card] = [_card(8, "hearts"), _card(7, "hearts"), _card(9, "hearts")]
	if Rules.is_valid_grid_line(scrambled):
		_fail("8-7-9 is out of spatial order — not a grid run")
	var down_line: Array[Card] = [_card(9, "hearts"), _card(8, "hearts"), _card(7, "hearts")]
	if not Rules.is_valid_grid_line(down_line):
		_fail("a grid run reads descending too")
	var set_line: Array[Card] = [_card(7, "hearts"), _card(7, "spades"), _card(7, "clubs")]
	if not Rules.is_valid_grid_line(set_line):
		_fail("three sevens should read as a grid set in any order")

## A picture on the felt with the player open: the flower's cards are known,
## so plays off its cards are deterministic. Template order maps card i to
## cell i — index 0 is the top petal at (1,0), index 1 the left petal at (0,1).
func _picture_gm() -> Dictionary:
	var flower_cards: Array[Card] = []
	for i in CuteSlime.ULT_FLOWER.size():
		flower_cards.append(_slimed((i % 13) + 3, "diamonds"))
	var top := _slimed(7, "hearts")
	var left := _slimed(5, "diamonds")
	flower_cards[0] = top
	flower_cards[1] = left
	var picture := CuteSlime.build_shape_meld(CuteSlime.ULT_FLOWER, flower_cards)
	var gm := GameManager.new()
	gm.setup(["You", "Foe"], 5, 7)
	gm.board.melds.assign([picture] as Array[CardSet])
	gm.players[0].has_opened = true
	return {"gm": gm, "picture": picture, "top": top, "left": left}

func _give_hand(gm: GameManager, hand: Array[Card]) -> void:
	gm.players[0].hand = hand.duplicate()
	gm._hand_snapshot = hand.duplicate()
	gm._undo_stack.clear()

## Scrabble-style plays off a picture: growable pair, extension to a full
## run, the outward-only and one-line-per-axis rules, whole-line tear-down,
## sealed picture cards, no jokers, and a clean commit.
func _test_play_off_picture() -> void:
	var setup := _picture_gm()
	var gm: GameManager = setup["gm"]
	var top: Card = setup["top"]      # 7H at (1,0)
	var left: Card = setup["left"]    # 5D at (0,1)
	var eight := _card(8, "hearts")
	var nine := _card(9, "hearts")
	var joker := Card.new()
	joker.is_joker = true
	joker.suit = "joker"
	_give_hand(gm, [eight, nine, joker, _card(2, "clubs")] as Array[Card])

	# A single 8H up from the 7H petal: a growable pair, legal to stage.
	var err := gm.play_off_picture(top, Vector2i.UP, [eight] as Array[Card])
	if err != "":
		_fail("8H off the 7H petal should stage as a growable pair, got: %s" % err)
		return
	var line: CardSet = gm.board.melds[-1]
	if not line.is_attached() or line.attach_anchor != top or not line.is_valid():
		_fail("the pair should live in a valid attached line off the 7H")
	# Extending the line with 9H completes the run 7-8-9 reading outward.
	if gm.add_cards_to_meld([nine] as Array[Card], line) != "":
		_fail("9H should extend the line into 7-8-9")
	if line.cards != ([eight, nine] as Array[Card]):
		_fail("the line should hold 8H then 9H outward")
	# The other way on the same axis is that line's, not a second one's.
	if gm.play_off_picture(top, Vector2i.DOWN, [_card(6, "hearts")] as Array[Card]) == "":
		_fail("the 7H already carries its vertical line — no second one")
	# A dead pair never sticks; neither do jokers; picture cards are sealed.
	if gm.play_off_picture(left, Vector2i.LEFT, [_card(2, "clubs")] as Array[Card]) == "":
		_fail("2C off the 5D petal is a dead pair and must be refused")
	if gm.play_off_picture(left, Vector2i.LEFT, [joker] as Array[Card]) == "":
		_fail("jokers don't stick to pictures")
	if gm.move_cards_to_new_meld([top] as Array[Card]) == "":
		_fail("picture cards are sealed in place")
	# Outward only: up from the left petal hugs the top petal diagonally' —
	# the cell (0,0) touches the picture at (1,0) — so it is refused.
	if gm.play_off_picture(left, Vector2i.UP, [_card(6, "diamonds")] as Array[Card]) == "":
		_fail("a line hugging the picture must be refused (outward only)")
	# Whole line or nothing: a lone card can't leave the line, the pair can.
	if gm.move_cards_to_new_meld([eight] as Array[Card]) == "":
		_fail("a single card must not tear out of an extension line")
	if gm.return_cards_to_hand([nine] as Array[Card]) == "":
		_fail("a take-back must also honor whole-line-or-nothing")
	if gm.return_cards_to_hand([eight, nine] as Array[Card]) != "":
		_fail("taking the whole line back to hand should be allowed")
		return
	if gm.board.melds.size() != 1:
		_fail("the emptied line should dissolve, leaving just the picture")
	# Re-play the run and commit the turn.
	if gm.play_off_picture(top, Vector2i.UP, [eight, nine] as Array[Card]) != "":
		_fail("re-playing 8H 9H together should stage the run")
	if gm.commit_turn() != "":
		_fail("a turn ending on a legal extension line should commit")
	gm.free()

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

## Ghost cells render around a picture on the player's turn, and a play off
## one lays a line that renders inside the cluster grid.
func _test_picture_ghost_cells() -> void:
	var ui: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(ui)
	await process_frame
	await process_frame
	ui._on_play_vanilla_pressed()
	await process_frame
	var flower_cards: Array[Card] = []
	for i in CuteSlime.ULT_FLOWER.size():
		flower_cards.append(_slimed((i % 13) + 3, "diamonds"))
	var top := _slimed(7, "hearts")
	flower_cards[0] = top
	var picture := CuteSlime.build_shape_meld(CuteSlime.ULT_FLOWER, flower_cards)
	ui.gm.board.melds.assign([picture] as Array[CardSet])
	ui.gm.players[0].has_opened = true
	var eight := _card(8, "hearts")
	ui.gm.players[0].hand = [eight] as Array[Card]
	ui.gm._hand_snapshot = ui.gm.players[0].hand.duplicate()
	ui._refresh()
	await process_frame
	if _count_ghosts(ui) == 0:
		_fail("a picture on your turn should show ghost play cells")
	ui._play_line_start(top, Vector2i.UP, [eight] as Array[Card])
	await process_frame
	var btn: Button = ui.card_nodes.get(eight)
	if btn == null or not (btn.get_parent() is GridContainer):
		_fail("the played line should render inside the picture's grid")
	ui.queue_free()
	await process_frame

func _count_ghosts(ui: Control) -> int:
	var n := 0
	for panel in ui.board_flow.get_children():
		n += _ghosts_in(panel)
	return n

func _ghosts_in(node: Node) -> int:
	var n := 0
	for child in node.get_children():
		if child is Button and (child as Button).text == "+":
			n += 1
		n += _ghosts_in(child)
	return n
