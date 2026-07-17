extends SceneTree

## Headless smoke test for the vanilla engine. Run with:
##   godot --headless --path . --import        (first time, builds the class cache)
##   godot --headless --path . --script res://tests/smoke_test.gd
## Plays full AI-vs-AI games from fixed seeds and asserts core invariants
## after every single turn.

const GAMES := 25
const MAX_TURNS := 2000
const TOTAL_CARDS := 104

func _init() -> void:
	var failures := 0
	if not _test_return_to_hand():
		failures += 1
	for seed_value in GAMES:
		if not _play_game(seed_value):
			failures += 1
	if failures == 0:
		print("SMOKE TEST OK: %d/%d games completed cleanly" % [GAMES, GAMES])
		quit(0)
	else:
		printerr("SMOKE TEST FAILED: %d/%d games had problems" % [failures, GAMES])
		quit(1)

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

func _play_game(seed_value: int) -> bool:
	var gm := GameManager.new()
	gm.setup(["P0", "P1", "P2"], 13, seed_value)
	var turns := 0
	while not gm.is_game_over and turns < MAX_TURNS:
		GreedyAI.take_turn(gm)
		turns += 1
		if not gm.board.all_valid():
			printerr("game %d: invalid meld on table after turn %d" % [seed_value, turns])
			return false
		var count := gm.deck.size() + gm.board.all_cards().size()
		for p in gm.players:
			count += p.hand.size()
		if count != TOTAL_CARDS:
			printerr("game %d: card conservation broken (%d) after turn %d" % [seed_value, count, turns])
			return false
	if not gm.is_game_over:
		printerr("game %d: did not finish within %d turns" % [seed_value, MAX_TURNS])
		return false
	var melds := gm.board.melds.size()
	print("game %d: finished in %d turns, table melds: %d" % [seed_value, turns, melds])
	gm.free()
	return true
