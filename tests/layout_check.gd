extends SceneTree

## Headless check for the board-layout groundwork: meld orientation surviving
## snapshots, crossing groups sharing one card (both valid, both extendable,
## undoable, committable), shape (picture) groups on a grid, BoardGrid cluster
## and adjacency math, and the cluster/vertical rendering paths. Run:
##   godot --headless --path . --script res://tests/layout_check.gd

## A small known-geometry picture used by the play-off-picture tests below. It
## is a local fixture (the enemy's own ult templates are exercised separately),
## so those generic-mechanic tests don't move when the ult roster changes. A
## 9-cell flower: top row (indices 0-2), side walls (3-4), bottom row (5-7),
## stem (8).
const TEST_PICTURE: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
	Vector2i(0, 1), Vector2i(2, 1),
	Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2),
	Vector2i(1, 3),
]

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
	_test_projected_meter()
	_test_slime_ultimate()
	_test_slime_ultimate_gates()
	_test_ult_fills_this_turn()
	_test_picture_seal_this_turn()
	_test_ult_in_driven_games()
	_test_grid_line_rules()
	_test_play_off_picture()
	_test_picture_joker_swap()
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
	# The heart is a hollow outline: its brow row is still 5 cards wide, but
	# below it only the walls and the bottom tip carry cards.
	var row_card := heart.card_at(Vector2i(0, 1))
	if heart.line_through(row_card, true).size() != 5:
		_fail("the heart's second row should be a 5-card line")
	if heart.line_through(heart.card_at(Vector2i(0, 2)), false).size() != 3:
		_fail("the heart's left wall should be a 3-card vertical line")
	if heart.line_through(heart.card_at(Vector2i(2, 5)), false).size() != 2:
		_fail("the heart's tip should hang off a 2-card vertical line")
	if heart.card_at(Vector2i(2, 2)) != null or heart.card_at(Vector2i(2, 3)) != null:
		_fail("the heart's middle should be hollow — outline only")
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

## The meter builds live: the current player's bar previews the charge this
## turn's staged plays will bank, so it fills as cards are played and drops back
## on undo. Everyone else shows only their banked charge.
func _test_projected_meter() -> void:
	var gm := GameManager.new()
	gm.setup(["You", "Foe"], 5, 7)
	gm.meter_max = 10
	gm.meter_gain = 1
	gm.meter_per_card = true
	gm.players[0].has_opened = true
	var trips: Array[Card] = [_card(9, "hearts"), _card(9, "spades"), _card(9, "clubs")]
	gm.players[0].hand = trips.duplicate()
	gm._hand_snapshot = trips.duplicate()
	gm._undo_stack.clear()
	if gm.projected_meter(gm.players[0]) != 0:
		_fail("an untouched meter should read its banked value")
	gm.move_cards_to_new_meld(trips)
	if gm.projected_meter(gm.players[0]) != 3:
		_fail("the meter should build live as cards are played, got %d"
			% gm.projected_meter(gm.players[0]))
	if gm.projected_meter(gm.players[1]) != 0:
		_fail("only the current player's bar previews this turn's charge")
	gm.undo_action()
	if gm.projected_meter(gm.players[0]) != 0:
		_fail("undoing the play should drop the live charge back")
	gm.free()

## The ultimate: a full meter plus enough gatherable slime builds the biggest
## picture that fits, seals it as one lump, and resets the meter.
func _test_slime_ultimate() -> void:
	var slime := CuteSlime.new()
	# Table slime she can take legally: two fully slimed 5-card runs (each whole
	# group may leave) and a slimed 8 in a set of four (the leftover trio stays
	# valid) — 11 table cards. The clean set of jacks must not be touched.
	var run := _meld([_slimed(3, "hearts"), _slimed(4, "hearts"), _slimed(5, "hearts"),
		_slimed(6, "hearts"), _slimed(7, "hearts")])
	var run2 := _meld([_slimed(3, "spades"), _slimed(4, "spades"), _slimed(5, "spades"),
		_slimed(6, "spades"), _slimed(7, "spades")])
	var eights := _meld([_slimed(8, "diamonds"), _card(8, "clubs"), _card(8, "spades"),
		_card(8, "hearts")])
	var jacks := _meld([_card(11, "hearts"), _card(11, "clubs"), _card(11, "spades")])
	# Six slimed naturals in hand: 11 gathered + 6 = 17 — exactly the heart.
	var hand: Array[Card] = [_slimed(9, "diamonds"), _slimed(10, "diamonds"),
		_slimed(12, "hearts"), _slimed(13, "hearts"), _slimed(2, "diamonds"),
		_slimed(9, "clubs"), _card(2, "clubs")]
	var gm := _slime_gm(hand, [run, run2, eights, jacks] as Array[CardSet])
	var move := slime.plan_strategy_move(gm)
	if not move.get("ult", false):
		_fail("a full meter with 17 gatherable slimed cards should fire the ultimate")
		gm.free()
		return
	if (move["cards"] as Array).size() != 17:
		_fail("the ultimate should fill the 17-card heart, got %d cards"
			% (move["cards"] as Array).size())
	GreedyAI.apply_move(gm, move)
	var picture: CardSet = gm.board.melds[-1]
	if not picture.is_shape() or picture.cards.size() != 17 or not picture.is_valid():
		_fail("the ultimate should leave a valid 17-card picture on the table")
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
	if picture.sticky_cluster(picture.cards[0]).size() != 17:
		_fail("the picture should move as one 17-card lump")
	# Sealing is a mechanic, not a play: the swallowed hand cards never count,
	# so an ult-only turn can't commit — she draws, keeping the picture.
	if gm.cards_played_this_turn() != 0:
		_fail("the ultimate must not count as playing cards, counted %d"
			% gm.cards_played_this_turn())
	if gm.commit_turn() == "":
		_fail("an ult-only turn has played nothing and must not commit")
	var stock := gm.deck.size()
	gm.draw_and_end_turn()
	if gm.deck.size() != stock - 1:
		_fail("the ultimate turn should still end in a draw")
	if gm.board.melds[-1] != picture or not picture.is_shape():
		_fail("the drawn turn should keep the picture on the felt")
	# Her planner never unpicks the picture on later turns.
	if not GreedyAI._immovable_cards(gm).has(picture.cards[0]):
		_fail("picture cards should be immovable to every planner")
	gm.free()

## Gates: no ult below a full meter, and a full meter holds until the slime on
## offer can legally fill a template.
func _test_slime_ultimate_gates() -> void:
	var slime := CuteSlime.new()
	# Enough slime for the heart (two whole-leaving runs + hand top-up = 17), but
	# the meter isn't full — so only the meter gate can be holding the ult back.
	var run := _meld([_slimed(3, "hearts"), _slimed(4, "hearts"), _slimed(5, "hearts"),
		_slimed(6, "hearts"), _slimed(7, "hearts")])
	var run2 := _meld([_slimed(3, "spades"), _slimed(4, "spades"), _slimed(5, "spades"),
		_slimed(6, "spades"), _slimed(7, "spades")])
	var hand: Array[Card] = [_slimed(9, "diamonds"), _slimed(10, "diamonds"),
		_slimed(12, "hearts"), _slimed(13, "hearts"), _slimed(2, "diamonds"),
		_slimed(9, "clubs"), _slimed(2, "hearts")]
	var gm := _slime_gm(hand, [run, run2] as Array[CardSet])
	gm.players[1].meter = gm.meter_max - 1
	if slime.plan_strategy_move(gm).get("ult", false):
		_fail("the ultimate must wait for a full meter")
	gm.free()
	# Full meter, but the only table slime is locked into its group: a set of
	# three with one slimed card can't spare it (leftover pair invalid), and
	# 3 hand cards alone can't fill the 17-card heart.
	var trio := _meld([_slimed(6, "diamonds"), _card(6, "clubs"), _card(6, "spades")])
	var gm2 := _slime_gm([_slimed(9, "diamonds"), _slimed(10, "diamonds"),
		_slimed(12, "hearts")] as Array[Card], [trio] as Array[CardSet])
	var move := slime.plan_strategy_move(gm2)
	if move.get("ult", false):
		_fail("without enough legally gatherable slime the ultimate must hold")
	if trio.cards.size() != 3:
		_fail("planning alone must not touch the table")
	gm2.free()

## A meter that fills from THIS turn's plays fires the ultimate the same turn,
## not a turn later: the play that tops the bar off lets the ult go at once.
func _test_ult_fills_this_turn() -> void:
	var slime := CuteSlime.new()
	var run := _meld([_slimed(3, "hearts"), _slimed(4, "hearts"), _slimed(5, "hearts"),
		_slimed(6, "hearts"), _slimed(7, "hearts")])
	var run2 := _meld([_slimed(3, "spades"), _slimed(4, "spades"), _slimed(5, "spades"),
		_slimed(6, "spades"), _slimed(7, "spades")])
	var eights := _meld([_slimed(8, "diamonds"), _card(8, "clubs"), _card(8, "spades"),
		_card(8, "hearts")])
	var jacks := _meld([_card(11, "hearts"), _card(11, "clubs"), _card(11, "spades")])
	# Six slimed naturals for the heart top-up, plus a clean set of 2s to play
	# (a real, valid play so the leftover table stays sound).
	var twos: Array[Card] = [_card(2, "clubs"), _card(2, "spades"), _card(2, "hearts")]
	var hand: Array[Card] = [_slimed(9, "diamonds"), _slimed(10, "diamonds"),
		_slimed(12, "hearts"), _slimed(13, "hearts"), _slimed(2, "diamonds"),
		_slimed(9, "clubs")]
	hand.append_array(twos)
	var gm := _slime_gm(hand, [run, run2, eights, jacks] as Array[CardSet])
	gm.players[1].meter = gm.meter_max - 1  # one short of full
	if slime.plan_strategy_move(gm).get("ult", false):
		_fail("a meter one short with no play yet this turn must not fire")
	# Play the clean set from hand: the live charge tops the bar off, and the
	# ultimate is available immediately — this same turn.
	if gm.move_cards_to_new_meld(twos) != "":
		_fail("staging the throwaway play failed")
	if gm.projected_meter(gm.players[1]) != gm.meter_max:
		_fail("this turn's play should top the meter off, got %d"
			% gm.projected_meter(gm.players[1]))
	if not slime.plan_strategy_move(gm).get("ult", false):
		_fail("the ult should fire the turn its meter completes, not a turn later")
	gm.free()

## A slimed picture card can be lifted back off the turn it is sealed in (like
## anything you played this turn), but is sealed for good from the next turn on.
func _test_picture_seal_this_turn() -> void:
	var slime := CuteSlime.new()
	var run := _meld([_slimed(3, "hearts"), _slimed(4, "hearts"), _slimed(5, "hearts"),
		_slimed(6, "hearts"), _slimed(7, "hearts")])
	var run2 := _meld([_slimed(3, "spades"), _slimed(4, "spades"), _slimed(5, "spades"),
		_slimed(6, "spades"), _slimed(7, "spades")])
	var eights := _meld([_slimed(8, "diamonds"), _card(8, "clubs"), _card(8, "spades"),
		_card(8, "hearts")])
	var jacks := _meld([_card(11, "hearts"), _card(11, "clubs"), _card(11, "spades")])
	var hand: Array[Card] = [_slimed(9, "diamonds"), _slimed(10, "diamonds"),
		_slimed(12, "hearts"), _slimed(13, "hearts"), _slimed(2, "diamonds"),
		_slimed(9, "clubs"), _card(2, "clubs")]
	var gm := _slime_gm(hand, [run, run2, eights, jacks] as Array[CardSet])
	GreedyAI.apply_move(gm, slime.plan_strategy_move(gm))
	var sealed_card: Card = gm.board.melds[-1].cards[0]
	if not gm.board.meld_of(sealed_card).is_shape():
		_fail("the ultimate should have sealed the card into a picture")
		gm.free()
		return
	# Same turn: the card she just squeezed in can still be lifted back off.
	if gm.move_cards_to_new_meld([sealed_card] as Array[Card]) != "":
		_fail("a picture card placed this turn should still be movable off it")
	gm.undo_action()  # put the picture back before ending her turn
	if not gm.board.meld_of(sealed_card).is_shape():
		_fail("undo should restore the card into the picture")
	# End her turn (an ult-only turn draws, keeping the picture), then the next
	# player finds the picture sealed shut.
	gm.draw_and_end_turn()
	if not gm.board.meld_of(sealed_card).is_shape():
		_fail("the picture should survive into the next turn")
	if gm.move_cards_to_new_meld([sealed_card] as Array[Card]) == "":
		_fail("a picture card is sealed once its turn has ended")
	gm.free()

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
	# Vertical straights read lower rank on top: ranks must rise going down
	# the felt. Sets and horizontal lines carry no direction.
	var up_pair: Array[Card] = [_card(7, "hearts"), _card(8, "hearts")]
	if Rules.line_direction_ok(up_pair, Vector2i.UP):
		_fail("8H above 7H puts the higher rank on top")
	if not Rules.line_direction_ok(up_pair, Vector2i.DOWN):
		_fail("8H below 7H reads low-on-top")
	var down_pair: Array[Card] = [_card(7, "hearts"), _card(6, "hearts")]
	if not Rules.line_direction_ok(down_pair, Vector2i.UP):
		_fail("6H above 7H reads low-on-top")
	var set_pair: Array[Card] = [_card(7, "hearts"), _card(7, "spades")]
	if not Rules.line_direction_ok(set_pair, Vector2i.UP):
		_fail("a set line has no direction to it")
	if not Rules.line_direction_ok(up_pair, Vector2i.RIGHT):
		_fail("horizontal lines have no direction rule")
	var ace_pair: Array[Card] = [_card(13, "spades"), _card(1, "spades")]
	if not Rules.line_direction_ok(ace_pair, Vector2i.DOWN):
		_fail("an ace under a king plays high — low-on-top holds")
	if Rules.line_direction_ok(ace_pair, Vector2i.UP):
		_fail("an ace above a king would put the high ace on top")

## A picture on the felt with the player open: the flower's cards are known,
## so plays off its cards are deterministic. Template order maps card i to
## cell i — index 1 is the blossom's top-middle at (1,0), index 3 the left
## wall at (0,1), index 8 the stem at (1,3).
func _picture_gm() -> Dictionary:
	var flower_cards: Array[Card] = []
	for i in TEST_PICTURE.size():
		flower_cards.append(_slimed((i % 13) + 3, "diamonds"))
	var top := _slimed(7, "hearts")
	var left := _slimed(5, "diamonds")
	flower_cards[1] = top
	flower_cards[3] = left
	var picture := CuteSlime.build_shape_meld(TEST_PICTURE, flower_cards)
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
## run, the lower-rank-on-top rule for vertical straights, the outward-only
## and one-line-per-axis rules, loose line cards (they come off one at a
## time), sealed picture cards, no jokers, and a clean commit.
func _test_play_off_picture() -> void:
	var setup := _picture_gm()
	var gm: GameManager = setup["gm"]
	var top: Card = setup["top"]      # 7H at (1,0)
	var left: Card = setup["left"]    # 5D at (0,1)
	var six := _card(6, "hearts")
	var five := _card(5, "hearts")
	var eight := _card(8, "hearts")
	var queen := _card(12, "diamonds")
	var king := _card(13, "diamonds")
	var two := _card(2, "clubs")
	var joker := Card.new()
	joker.is_joker = true
	joker.suit = "joker"
	_give_hand(gm, [six, five, eight, queen, king, two, joker] as Array[Card])

	# Vertical straights read lower rank on top: an 8H above the 7H would put
	# the higher rank on top, so upward plays off the 7H must descend.
	if gm.play_off_picture(top, Vector2i.UP, [eight] as Array[Card]) == "":
		_fail("8H above the 7H puts the higher rank on top — must be refused")
	# A single 6H up from the 7H petal: a growable pair, lower rank on top.
	var err := gm.play_off_picture(top, Vector2i.UP, [six] as Array[Card])
	if err != "":
		_fail("6H off the 7H petal should stage as a growable pair, got: %s" % err)
		return
	var line: CardSet = gm.board.melds[-1]
	if not line.is_attached() or line.attach_anchor != top or not line.is_valid():
		_fail("the pair should live in a valid attached line off the 7H")
	# Extending the line with 5H completes the run 7-6-5 reading outward — on
	# screen that is 5 on top, 7 at the picture: lower rank on top.
	if gm.add_cards_to_meld([five] as Array[Card], line) != "":
		_fail("5H should extend the line into 7-6-5")
	if line.cards != ([six, five] as Array[Card]):
		_fail("the line should hold 6H then 5H outward")
	# The other way on the same axis is that line's, not a second one's.
	if gm.play_off_picture(top, Vector2i.DOWN, [eight] as Array[Card]) == "":
		_fail("the 7H already carries its vertical line — no second one")
	# A dead pair never sticks; neither do jokers; picture cards are sealed.
	if gm.play_off_picture(left, Vector2i.LEFT, [two] as Array[Card]) == "":
		_fail("2C off the 5D petal is a dead pair and must be refused")
	if gm.play_off_picture(left, Vector2i.LEFT, [joker] as Array[Card]) == "":
		_fail("jokers don't stick to pictures")
	if gm.move_cards_to_new_meld([top] as Array[Card]) == "":
		_fail("picture cards are sealed in place")
	# Outward only: left from the stem could grow (JD then QD reads as a run),
	# but the cell (0,3) hugs the picture's bottom wall at (0,2) — refused.
	var stem: Card = (setup["picture"] as CardSet).card_at(Vector2i(1, 3))
	if gm.play_off_picture(stem, Vector2i.LEFT, [queen] as Array[Card]) == "":
		_fail("a line hugging the picture must be refused (outward only)")
	# Line cards stay loose: the outer card comes back on its own...
	if gm.return_cards_to_hand([five] as Array[Card]) != "":
		_fail("taking the outer line card back alone should be allowed")
	if line.cards != ([six] as Array[Card]) or not line.is_valid():
		_fail("the line should shrink back to the growable 7-6 pair")
	# ...and so can the inner one, the rest sliding in toward the anchor: 5H
	# alone then reads 7-5, broken until the turn is cleaned up.
	if gm.add_cards_to_meld([five] as Array[Card], line) != "":
		_fail("5H should re-extend the line")
	if gm.return_cards_to_hand([six] as Array[Card]) != "":
		_fail("the inner line card should be free to leave mid-turn")
	if line.is_valid():
		_fail("7H then 5H does not read — the broken line must show invalid")
	if gm.commit_turn() == "":
		_fail("a turn ending on a broken line must not commit")
	if gm.return_cards_to_hand([five] as Array[Card]) != "":
		_fail("clearing the broken line should be allowed")
	if gm.board.melds.size() != 1:
		_fail("the emptied line should dissolve, leaving just the picture")
	# A downward straight ascends instead (again lower rank on top): Q K
	# hanging below the J stem, then the turn commits.
	if gm.play_off_picture(stem, Vector2i.DOWN, [queen, king] as Array[Card]) != "":
		_fail("Q K downward off the J stem should stage the run")
	if gm.commit_turn() != "":
		_fail("a turn ending on a legal extension line should commit")
	gm.free()

## A joker sealed inside a picture can still be claimed the usual way: drop
## the exact card it stands for and the joker comes back to the hand, the real
## card taking over the joker's cell.
func _test_picture_joker_swap() -> void:
	var flower_cards: Array[Card] = []
	for i in TEST_PICTURE.size():
		flower_cards.append(_slimed((i % 13) + 3, "diamonds"))
	var joker := Card.new()
	joker.is_joker = true
	joker.suit = "joker"
	joker.joker_lock_rank = 9
	joker.joker_lock_suit = "hearts"
	flower_cards[4] = joker  # the right wall cell (2,1)
	var picture := CuteSlime.build_shape_meld(TEST_PICTURE, flower_cards)
	var gm := GameManager.new()
	gm.setup(["You", "Foe"], 5, 7)
	gm.board.melds.assign([picture] as Array[CardSet])
	gm.players[0].has_opened = true
	var nine := _card(9, "hearts")
	_give_hand(gm, [nine] as Array[Card])
	Rules.assign_jokers(picture.cards)
	var cell := picture.cell_of(joker)
	if gm.swap_joker(nine, joker, picture) != "":
		_fail("a locked joker in a picture should swap for its exact card")
		gm.free()
		return
	if picture.cell_of(nine) != cell or picture.cards.has(joker):
		_fail("the swap should seat the real card in the joker's cell")
	if not gm.players[0].hand.has(joker) or joker.joker_lock_rank != 0:
		_fail("the joker should return to the hand as a free wildcard")
	if not picture.is_valid():
		_fail("the picture must stay a well-formed shape after the swap")
	# The swapped-in card is sealed like any picture card, and the swap itself
	# counts as the turn's play, so the turn commits.
	if gm.move_cards_to_new_meld([nine] as Array[Card]) == "":
		_fail("the swapped-in card is sealed inside the picture")
	if gm.commit_turn() != "":
		_fail("a turn ending on the picture swap should commit")
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
	for i in TEST_PICTURE.size():
		flower_cards.append(_slimed((i % 13) + 3, "diamonds"))
	var top := _slimed(7, "hearts")
	flower_cards[1] = top  # the blossom's top-middle cell (1,0)
	var picture := CuteSlime.build_shape_meld(TEST_PICTURE, flower_cards)
	ui.gm.board.melds.assign([picture] as Array[CardSet])
	ui.gm.players[0].has_opened = true
	# A 6H above the 7H petal: descending upward, so the lower rank is on top.
	var six := _card(6, "hearts")
	ui.gm.players[0].hand = [six] as Array[Card]
	ui.gm._hand_snapshot = ui.gm.players[0].hand.duplicate()
	ui._refresh()
	await process_frame
	if _count_ghosts(ui) == 0:
		_fail("a picture on your turn should show ghost play cells")
	ui._play_line_start(top, Vector2i.UP, [six] as Array[Card])
	await process_frame
	var btn: Button = ui.card_nodes.get(six)
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
