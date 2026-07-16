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
	for seed_value in GAMES:
		if not _play_game(seed_value):
			failures += 1
	if failures == 0:
		print("SMOKE TEST OK: %d/%d games completed cleanly" % [GAMES, GAMES])
		quit(0)
	else:
		printerr("SMOKE TEST FAILED: %d/%d games had problems" % [failures, GAMES])
		quit(1)

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
