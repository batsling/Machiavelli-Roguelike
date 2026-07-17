extends SceneTree

## Headless smoke test for the vanilla engine. Run with:
##   godot --headless --path . --import        (first time, builds the class cache)
##   godot --headless --path . --script res://tests/smoke_test.gd
## Plays full AI-vs-AI games from fixed seeds (plain, with jokers, with AI
## profiles, with multi-card draws) and asserts core invariants after every
## single turn, plus unit tests for joker rules and the joker swap.

const GAMES := 25
const MAX_TURNS := 2000

func _init() -> void:
	var failures := 0
	if not _test_return_to_hand():
		failures += 1
	if not _test_joker_rules():
		failures += 1
	if not _test_joker_swap():
		failures += 1
	if not _test_joker_choice():
		failures += 1
	if not _test_safe_joker_reps():
		failures += 1
	if not _test_joker_lock():
		failures += 1
	if not _test_hand_cap():
		failures += 1
	for seed_value in GAMES:
		if not _play_game(seed_value, "game"):
			failures += 1
	for seed_value in 10:
		if not _play_game(seed_value, "joker game", true):
			failures += 1
	# Strong AIs pick safe joker stand-ins; make sure games stay clean.
	for seed_value in 5:
		var strong := AIProfile.new(1.0, 0.0, seed_value)
		if not _play_game(seed_value, "smart joker game", true, strong):
			failures += 1
	# The four corners of the AI graph, seeded so replays are exact.
	for corner: Array in [[0.0, 0.0], [0.0, 1.0], [1.0, 0.0], [1.0, 1.0]]:
		for seed_value in 5:
			var profile := AIProfile.new(corner[0], corner[1], seed_value)
			var label := "profile(%.0f,%.0f) game" % [corner[0], corner[1]]
			if not _play_game(seed_value, label, false, profile):
				failures += 1
	for seed_value in 5:
		if not _play_game(seed_value, "draw-3 game", false, null, 3):
			failures += 1
	for seed_value in 5:
		if not _play_game(seed_value, "capped game", false, null, 1, 15):
			failures += 1
	if failures == 0:
		print("SMOKE TEST OK: all games completed cleanly")
		quit(0)
	else:
		printerr("SMOKE TEST FAILED: %d test(s)/game(s) had problems" % failures)
		quit(1)

func _card(rank: int, suit: String) -> Card:
	var c := Card.new()
	c.rank = rank
	c.suit = suit
	return c

func _joker() -> Card:
	var c := Card.new()
	c.suit = "joker"
	c.is_joker = true
	return c

## With a hand cap, drawing stops at the cap and a draw attempted on a full
## hand counts as a pass; a full round of full-hand passes ends the game.
func _test_hand_cap() -> bool:
	var gm := GameManager.new()
	var ok := true
	gm.setup(["P0", "P1"], 13, 5)
	gm.draw_per_turn = 3
	gm.max_hand_size = 14
	var p := gm.current_player()
	gm.draw_and_end_turn()
	if p.hand.size() != 14:
		printerr("hand cap: draw-3 should stop at the cap of 14, got %d" % p.hand.size())
		ok = false
	gm.draw_and_end_turn()  # P1 draws to 14 too
	gm.draw_and_end_turn()  # P0 is full: this is a pass
	if p.hand.size() != 14:
		printerr("hand cap: a full hand should not draw, got %d" % p.hand.size())
		ok = false
	elif gm.is_game_over:
		printerr("hand cap: one pass should not end the game")
		ok = false
	gm.draw_and_end_turn()  # P1 is full too: second pass in the round — game ends
	if not gm.is_game_over:
		printerr("hand cap: a full round of full-hand passes should end the game")
		ok = false
	gm.free()
	if ok:
		print("hand cap test OK")
	return ok

## Cards staged from the hand this turn can be taken back into the hand;
## cards still in the hand (or never played) cannot be "returned".
func _test_return_to_hand() -> bool:
	var gm := GameManager.new()
	var ok := true
	gm.setup(["P0", "P1"], 13, 3)
	var p := gm.current_player()
	var played: Array[Card] = [p.hand[0], p.hand[1]]
	if gm.move_cards_to_new_meld(played) != "":
		printerr("return test: staging own hand cards was rejected")
		ok = false
	elif not gm.can_return_to_hand(played):
		printerr("return test: staged cards not returnable")
		ok = false
	elif gm.return_cards_to_hand(played) != "":
		printerr("return test: returning staged cards was rejected")
		ok = false
	elif p.hand.size() != 13 or not p.hand.has(played[0]) or not p.hand.has(played[1]):
		printerr("return test: hand not restored after return")
		ok = false
	elif not gm.board.melds.is_empty():
		printerr("return test: emptied meld not pruned from the board")
		ok = false
	elif gm.can_return_to_hand(played):
		printerr("return test: cards already in hand reported returnable")
		ok = false
	gm.free()
	if ok:
		print("return-to-hand test OK")
	return ok

func _test_joker_rules() -> bool:
	var ok := true
	var checks: Array = [
		# [description, cards, expected validity]
		["set + joker", [_card(7, "hearts"), _card(7, "spades"), _joker()], true],
		["4-set via joker", [_card(7, "hearts"), _card(7, "diamonds"),
			_card(7, "clubs"), _joker()], true],
		["5th set card via joker", [_card(7, "hearts"), _card(7, "diamonds"),
			_card(7, "clubs"), _card(7, "spades"), _joker()], false],
		["run gap fill", [_card(5, "hearts"), _card(7, "hearts"), _joker()], true],
		["run extension", [_card(5, "hearts"), _card(6, "hearts"), _joker()], true],
		["ace-high via joker", [_card(12, "clubs"), _card(13, "clubs"), _joker()], true],
		["one natural + 2 jokers", [_card(1, "spades"), _joker(), _joker()], true],
		["wrap-around stays illegal", [_card(13, "hearts"), _card(2, "hearts"), _joker()], false],
		["jokers need an anchor", [_joker(), _joker(), _joker()], false],
		["gap too wide", [_card(2, "hearts"), _card(6, "hearts"), _joker()], false],
	]
	for check: Array in checks:
		var cards: Array[Card] = []
		cards.assign(check[1])
		if Rules.is_valid_meld(cards) != check[2]:
			printerr("joker rules: '%s' expected %s" % [check[0], check[2]])
			ok = false
	# Assignment: gaps are filled first, then the run extends high.
	var run: Array[Card] = [_card(5, "hearts"), _card(6, "hearts"), _joker()]
	Rules.assign_jokers(run)
	if run[2].joker_rank != 7 or run[2].joker_suit != "hearts":
		printerr("joker rules: extension joker should stand for 7 of hearts, got %s"
			% run[2].rep_label())
		ok = false
	var gapped: Array[Card] = [_card(5, "clubs"), _joker(), _card(7, "clubs")]
	Rules.assign_jokers(gapped)
	if gapped[1].joker_rank != 6 or gapped[1].joker_suit != "clubs":
		printerr("joker rules: gap joker should stand for 6 of clubs, got %s"
			% gapped[1].rep_label())
		ok = false
	var joker_set: Array[Card] = [_card(9, "hearts"), _card(9, "spades"), _joker()]
	Rules.assign_jokers(joker_set)
	if joker_set[2].joker_rank != 9 or joker_set[2].joker_suit == "":
		printerr("joker rules: set joker should stand for a 9, got %s"
			% joker_set[2].rep_label())
		ok = false
	if ok:
		print("joker rules test OK")
	return ok

## When a meld leaves a joker a choice, joker_alternatives lists the options
## and a joker_pref_* choice steers assign_jokers; a preference that no
## longer fits is ignored.
func _test_joker_choice() -> bool:
	var ok := true
	# Set of three: two suits missing, so the joker has a genuine choice.
	var joker := _joker()
	var trio: Array[Card] = [_card(9, "hearts"), _card(9, "spades"), joker]
	var alts := Rules.joker_alternatives(trio)
	if alts.size() != 2:
		printerr("joker choice: 3-set should offer 2 suits, got %d" % alts.size())
		ok = false
	Rules.assign_jokers(trio)
	if joker.joker_suit != "diamonds":
		printerr("joker choice: default set suit should be diamonds, got %s"
			% joker.joker_suit)
		ok = false
	joker.joker_pref_rank = 9
	joker.joker_pref_suit = "clubs"
	Rules.assign_jokers(trio)
	if joker.joker_suit != "clubs":
		printerr("joker choice: clubs preference ignored, got %s" % joker.joker_suit)
		ok = false
	joker.joker_pref_suit = "hearts"  # taken by a natural — must be ignored
	Rules.assign_jokers(trio)
	if joker.joker_suit != "diamonds":
		printerr("joker choice: unusable preference should fall back to diamonds, got %s"
			% joker.joker_suit)
		ok = false
	# Run extension: the spare joker can sit at either end.
	var run_joker := _joker()
	var run: Array[Card] = [_card(5, "hearts"), _card(6, "hearts"), run_joker]
	var run_alts := Rules.joker_alternatives(run)
	if run_alts.size() != 2 or run_alts[0]["rank"] != 4 or run_alts[1]["rank"] != 7:
		printerr("joker choice: 5-6 run should offer ranks 4 and 7")
		ok = false
	run_joker.joker_pref_rank = 4
	run_joker.joker_pref_suit = "hearts"
	Rules.assign_jokers(run)
	if run_joker.joker_rank != 4:
		printerr("joker choice: low-end run preference ignored, got %d"
			% run_joker.joker_rank)
		ok = false
	if not Rules.is_valid_meld(run):
		printerr("joker choice: preferred run no longer valid")
		ok = false
	# A joker forced into an inner gap has no choice to offer.
	var gapped: Array[Card] = [_card(5, "clubs"), _joker(), _card(7, "clubs")]
	if not Rules.joker_alternatives(gapped).is_empty():
		printerr("joker choice: gap joker should have no alternatives")
		ok = false
	# Two jokers covering both missing suits of a set: nothing left to pick.
	var full_set: Array[Card] = [_card(4, "hearts"), _card(4, "spades"),
		_joker(), _joker()]
	if not Rules.joker_alternatives(full_set).is_empty():
		printerr("joker choice: fully-jokered set should have no alternatives")
		ok = false
	if ok:
		print("joker choice test OK")
	return ok

## A capable AI points a played joker at the stand-in with the fewest unseen
## copies, so opponents are unlikely to hold the card that swap-claims it.
func _test_safe_joker_reps() -> bool:
	var gm := GameManager.new()
	var ok := true
	gm.setup(["P0", "P1"], 13, 11, true)
	# Both 9 of diamonds are accounted for (one on the table, one in the AI's
	# hand); both 9 of clubs are still out there.
	var seen_meld := CardSet.new()
	seen_meld.cards.assign([_card(8, "diamonds"), _card(9, "diamonds"),
		_card(10, "diamonds")])
	gm.board.melds.append(seen_meld)
	gm.current_player().hand.append(_card(9, "diamonds"))
	var joker := _joker()
	var meld := CardSet.new()
	meld.cards.assign([_card(9, "hearts"), _card(9, "spades"), joker])
	gm.board.melds.append(meld)
	GreedyAI._choose_joker_reps(gm, meld)
	Rules.assign_jokers(meld.cards)
	if joker.joker_suit != "diamonds":
		printerr("safe reps: joker should stand for the fully-seen 9 of diamonds, got %s"
			% joker.rep_label())
		ok = false
	gm.free()
	if ok:
		print("safe joker reps test OK")
	return ok

## Committing a turn locks every joker on the table to what it was placed
## as: it is then treated as exactly that card (not a wildcard) when
## rearranged, keeps its face even in a broken meld, and only unlocks when
## the swap takes it off the board — with undo restoring the lock.
func _test_joker_lock() -> bool:
	var gm := GameManager.new()
	var ok := true
	gm.setup(["P0", "P1"], 13, 21, true)
	var p := gm.current_player()
	p.has_opened = true
	var joker := _joker()
	var played: Array[Card] = [_card(5, "hearts"), _card(6, "hearts"), joker]
	for c: Card in played:
		p.hand.append(c)
		gm._hand_snapshot.append(c)
	if gm.move_cards_to_new_meld(played) != "":
		printerr("lock test: staging the joker run was rejected")
		ok = false
	elif joker.joker_lock_rank != 0:
		printerr("lock test: joker locked before the turn was committed")
		ok = false
	elif gm.commit_turn() != "":
		printerr("lock test: committing the joker run failed")
		ok = false
	elif joker.joker_lock_rank != 7 or joker.joker_lock_suit != "hearts":
		printerr("lock test: joker should lock as 7 of hearts at commit, got %s"
			% joker.rep_label())
		ok = false
	if not ok:
		gm.free()
		return false
	# Locked, the joker is exactly the 7 of hearts wherever it goes.
	var as_seven: Array[Card] = [joker, _card(8, "hearts"), _card(9, "hearts")]
	if not Rules.is_valid_meld(as_seven):
		printerr("lock test: locked joker should count as 7 of hearts in a new run")
		ok = false
	var as_wild: Array[Card] = [joker, _card(9, "clubs"), _card(9, "spades")]
	if Rules.is_valid_meld(as_wild):
		printerr("lock test: locked joker must no longer act as a wildcard")
		ok = false
	var broken: Array[Card] = [joker, _card(2, "clubs")]
	Rules.assign_jokers(broken)
	if joker.joker_rank != 7 or joker.joker_suit != "hearts":
		printerr("lock test: locked joker lost its face in a broken meld")
		ok = false
	if not Rules.joker_alternatives(gm.board.melds[0].cards).is_empty():
		printerr("lock test: locked joker should offer no alternatives")
		ok = false
	# The swap unlocks it; undoing the swap locks it again.
	var p1 := gm.current_player()
	p1.has_opened = true
	var seven := _card(7, "hearts")
	p1.hand.append(seven)
	gm._hand_snapshot.append(seven)
	Rules.assign_jokers(gm.board.melds[0].cards)
	if gm.swap_joker(seven, joker, gm.board.melds[0]) != "":
		printerr("lock test: swapping the real card for the locked joker failed")
		ok = false
	elif joker.joker_lock_rank != 0:
		printerr("lock test: swap should unlock the joker")
		ok = false
	elif not gm.undo_action():
		printerr("lock test: swap was not undoable")
		ok = false
	elif joker.joker_lock_rank != 7 or joker.joker_lock_suit != "hearts":
		printerr("lock test: undo should restore the joker's lock")
		ok = false
	gm.free()
	if ok:
		print("joker lock test OK")
	return ok

## A board joker standing for a specific card can be swapped for the real
## card from the hand; the swap counts as playing one card (so a swap alone
## can end the turn) and is undoable.
func _test_joker_swap() -> bool:
	var gm := GameManager.new()
	var ok := true
	gm.setup(["P0", "P1"], 13, 7)
	var p := gm.current_player()
	p.has_opened = true
	var joker := _joker()
	var meld := CardSet.new()
	meld.cards.assign([_card(5, "hearts"), _card(6, "hearts"), joker])
	gm.board.melds.append(meld)
	Rules.assign_jokers(meld.cards)
	var seven := _card(7, "hearts")
	var wrong := _card(8, "hearts")
	p.hand.append(seven)
	p.hand.append(wrong)
	gm._hand_snapshot.append(seven)
	gm._hand_snapshot.append(wrong)
	if joker.joker_rank != 7 or joker.joker_suit != "hearts":
		printerr("swap test: joker should stand for 7 of hearts")
		ok = false
	elif gm.swap_joker(wrong, joker, meld) == "":
		printerr("swap test: swapping the wrong card was allowed")
		ok = false
	elif gm.swap_joker(seven, joker, meld) != "":
		printerr("swap test: legal swap was rejected")
		ok = false
	elif not meld.cards.has(seven) or meld.cards.has(joker):
		printerr("swap test: meld does not hold the real card after the swap")
		ok = false
	elif not p.hand.has(joker) or joker.joker_rank != 0:
		printerr("swap test: joker not back in hand as a free wildcard")
		ok = false
	elif gm.cards_played_this_turn() != 1:
		printerr("swap test: swap should count as playing one card (got %d)"
			% gm.cards_played_this_turn())
		ok = false
	elif not gm.undo_action():
		printerr("swap test: swap was not undoable")
		ok = false
	elif not gm.board.melds[0].cards.has(joker) or not p.hand.has(seven):
		printerr("swap test: undo did not restore the joker to the table")
		ok = false
	elif gm.cards_played_this_turn() != 0:
		printerr("swap test: undo left the played-cards count off")
		ok = false
	elif not _reassign_and_swap(gm, seven, joker):
		printerr("swap test: swap after undo was rejected")
		ok = false
	elif gm.commit_turn() != "":
		printerr("swap test: a swap-only turn should be committable")
		ok = false
	elif gm.current_player() == p:
		printerr("swap test: committing the swap-only turn did not end the turn")
		ok = false
	gm.free()
	if ok:
		print("joker swap test OK")
	return ok

## After an undo the joker's representation is stale; the UI recomputes it on
## every refresh, so mirror that here before swapping again.
func _reassign_and_swap(gm: GameManager, hand_card: Card, joker: Card) -> bool:
	Rules.assign_jokers(gm.board.melds[0].cards)
	return gm.swap_joker(hand_card, joker, gm.board.melds[0]) == ""

func _play_game(seed_value: int, label: String, include_jokers := false,
		profile: AIProfile = null, draw_per_turn := 1, max_hand_size := 0) -> bool:
	var gm := GameManager.new()
	gm.setup(["P0", "P1", "P2"], 13, seed_value, include_jokers)
	gm.draw_per_turn = draw_per_turn
	gm.max_hand_size = max_hand_size
	var total_cards := 108 if include_jokers else 104
	var turns := 0
	while not gm.is_game_over and turns < MAX_TURNS:
		GreedyAI.take_turn(gm, profile)
		turns += 1
		if not gm.board.all_valid():
			printerr("%s %d: invalid meld on table after turn %d" % [label, seed_value, turns])
			return false
		var count := gm.deck.size() + gm.board.all_cards().size()
		for p in gm.players:
			count += p.hand.size()
		if count != total_cards:
			printerr("%s %d: card conservation broken (%d) after turn %d"
				% [label, seed_value, count, turns])
			return false
	if not gm.is_game_over:
		printerr("%s %d: did not finish within %d turns" % [label, seed_value, MAX_TURNS])
		return false
	var melds := gm.board.melds.size()
	print("%s %d: finished in %d turns, table melds: %d" % [label, seed_value, turns, melds])
	gm.free()
	return true
