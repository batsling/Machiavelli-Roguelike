extends SceneTree

## Headless checks for the Sadistic Billionaire's Riichi ultimate and the
## discard-pile plumbing it rides on. Run:
##   godot --headless --path . --script res://tests/riichi_check.gd

const MAX_TURNS := 3000

var ok := true

func _card(rank: int, suit: String) -> Card:
	var c := Card.new()
	c.suit = suit
	c.rank = rank
	return c

func _glass(c: Card) -> Card:
	c.effects.append(Card.Effect.CLEAR)
	return c

func _fail(msg: String) -> void:
	printerr(msg)
	ok = false

## Put the game into `idx`'s turn cleanly, without emitting signals.
func _begin_turn_for(gm: GameManager, idx: int) -> void:
	gm.turn_index = idx
	gm._hand_snapshot = gm.players[idx].hand.duplicate()
	gm._undo_stack.clear()
	gm._meter_spent_this_turn = false
	gm._shaped_this_turn.clear()

## A fresh 1v1 game with an empty board and a Billionaire wired as interceptor.
func _fixture() -> Dictionary:
	var gm := GameManager.new()
	gm.setup(["You", "The Sadistic Billionaire"], 5, 1, false)
	gm.board.melds.clear()
	gm.meter_max = 10
	var b := SadisticBillionaire.new()
	b.my_player_id = 1
	gm.play_interceptor = b
	return {"gm": gm, "b": b}

func _init() -> void:
	_test_discard_reshuffle()
	_test_declaration_gate()
	_test_dead_wait_declined()
	_test_tsumo()
	_test_draw_and_discard()
	_test_ron_via_commit()
	_test_defender_folds()
	_test_full_game_invariants()
	if ok:
		print("riichi_check: PASS")
		quit(0)
	else:
		printerr("riichi_check: FAIL")
		quit(1)

## The stock recycles the face-up discard pile once it runs dry.
func _test_discard_reshuffle() -> void:
	var d := Deck.new(1)
	d.cards.clear()
	d.discard(_card(5, "hearts"))
	d.discard(_card(6, "hearts"))
	d.discard(_card(7, "hearts"))
	if d.is_empty():
		_fail("reshuffle: deck with discards should not read empty to draw()")
	var drew := d.draw()
	if drew == null:
		_fail("reshuffle: draw() should recycle the discards, got null")
	if not d.discards.is_empty():
		_fail("reshuffle: discards should be folded into the stock on recycle")
	if d.cards.size() != 2:
		_fail("reshuffle: expected 2 cards left in stock, got %d" % d.cards.size())

## A full meter plus a genuine one-card wait makes him want to declare.
func _test_declaration_gate() -> void:
	var f := _fixture()
	var gm: GameManager = f["gm"]
	var b: SadisticBillionaire = f["b"]
	# Tenpai: {5h,5d,5c} set is done, {7s,8s} waits on 6s/9s.
	gm.players[1].hand = [_card(5, "hearts"), _card(5, "diamonds"), _card(5, "clubs"),
		_card(7, "spades"), _card(8, "spades")]
	gm.players[1].has_opened = true
	gm.players[1].meter = gm.meter_max
	_begin_turn_for(gm, 1)
	if not b.wants_control(gm):
		_fail("declaration: a full meter on a live wait should want to declare")
	# Not tenpai: a random junk hand that no single card completes.
	gm.players[1].hand = [_card(2, "hearts"), _card(9, "diamonds"), _card(4, "clubs")]
	_begin_turn_for(gm, 1)
	if b.wants_control(gm):
		_fail("declaration: a hand that is not tenpai should not declare")
	# Full hand already able to go out is a normal win, not a Riichi.
	gm.players[1].hand = [_card(5, "hearts"), _card(5, "diamonds"), _card(5, "clubs")]
	_begin_turn_for(gm, 1)
	if b.wants_control(gm):
		_fail("declaration: an already-complete hand should just win, not Riichi")

## He refuses to declare into a wait whose only live copies are visibly (glass)
## locked in the opponent's hand — the Washizu dead-wait rule.
func _test_dead_wait_declined() -> void:
	var f := _fixture()
	var gm: GameManager = f["gm"]
	var b: SadisticBillionaire = f["b"]
	# Wait is only 6s/9s to finish {7s,8s}. Put BOTH copies of each on the
	# opponent's glass hand, so nothing is drawable and no smart rival will feed.
	gm.players[1].hand = [_card(5, "hearts"), _card(5, "diamonds"), _card(5, "clubs"),
		_card(7, "spades"), _card(8, "spades")]
	gm.players[1].meter = gm.meter_max
	gm.players[1].has_opened = true
	gm.players[0].hand = [_glass(_card(6, "spades")), _glass(_card(6, "spades")),
		_glass(_card(9, "spades")), _glass(_card(9, "spades"))]
	_begin_turn_for(gm, 1)
	if b.wants_control(gm):
		_fail("dead wait: should decline when every wait copy is visible in the opponent's hand")

## In Riichi, drawing a winning card goes out by tsumo.
func _test_tsumo() -> void:
	var f := _fixture()
	var gm: GameManager = f["gm"]
	var b: SadisticBillionaire = f["b"]
	b.riichi = true
	gm.players[1].declared_riichi = true
	gm.players[1].hand = [_card(5, "hearts"), _card(5, "diamonds"), _card(5, "clubs"),
		_card(7, "spades"), _card(8, "spades")]
	_begin_turn_for(gm, 1)
	gm.deck.cards = [_card(6, "spades")]  # the winning draw sits on top
	var winners: Array = []
	gm.game_over.connect(func(w: Array) -> void: winners.assign(w))
	b.run_controlled_turn(gm)
	if not gm.is_game_over:
		_fail("tsumo: drawing the wait card should end the game")
	elif winners.size() != 1 or winners[0] != gm.players[1]:
		_fail("tsumo: the Billionaire should be the sole winner")

## In Riichi, a non-winning draw is discarded face up and the turn advances.
func _test_draw_and_discard() -> void:
	var f := _fixture()
	var gm: GameManager = f["gm"]
	var b: SadisticBillionaire = f["b"]
	b.riichi = true
	gm.players[1].declared_riichi = true
	gm.players[1].hand = [_card(5, "hearts"), _card(5, "diamonds"), _card(5, "clubs"),
		_card(7, "spades"), _card(8, "spades")]
	_begin_turn_for(gm, 1)
	gm.deck.cards = [_card(2, "diamonds")]  # not a wait
	b.run_controlled_turn(gm)
	if gm.is_game_over:
		_fail("discard: a non-winning draw should not end the game")
	if gm.deck.discards.size() != 1 or gm.deck.discards[0].rank != 2:
		_fail("discard: the drawn non-wait card should be on the discard pile")
	if gm.turn_index != 0:
		_fail("discard: the turn should advance after a discard")

## An opponent's committed play that lets his frozen hand go out is claimed on
## the spot — his ron — through the commit interceptor.
func _test_ron_via_commit() -> void:
	var f := _fixture()
	var gm: GameManager = f["gm"]
	var b: SadisticBillionaire = f["b"]
	b.riichi = true
	gm.players[1].declared_riichi = true
	# His hand 7s,8s waits on 6s/9s; the opponent's play includes 9s, completing
	# his own 7-8-9 run.
	gm.players[1].hand = [_card(7, "spades"), _card(8, "spades")]
	gm.players[0].hand = [_card(9, "spades"), _card(10, "spades"), _card(11, "spades"),
		_card(2, "diamonds")]
	gm.players[0].has_opened = true
	_begin_turn_for(gm, 0)
	var winners: Array = []
	gm.game_over.connect(func(w: Array) -> void: winners.assign(w))
	gm.move_cards_to_new_meld([gm.players[0].hand[0], gm.players[0].hand[1],
		gm.players[0].hand[2]])
	var err := gm.commit_turn()
	if err != "":
		_fail("ron: opponent's own play should be legal, got '%s'" % err)
	if not gm.is_game_over:
		_fail("ron: the Billionaire should claim the play and win")
	elif winners.size() != 1 or winners[0] != gm.players[1]:
		_fail("ron: the Billionaire should be the sole winner")

## A GreedyAI rival won't lay a card it can see completes the Riichi player's
## hand (a wait read off his glass cards), but plays freely otherwise.
func _test_defender_folds() -> void:
	var gm := GameManager.new()
	gm.setup(["You", "The Sadistic Billionaire", "Rival"], 5, 1, false)
	gm.board.melds.clear()
	# Bill (seat 1) has declared, showing glass 7s,8s — so 6s/9s read as waits.
	gm.players[1].declared_riichi = true
	gm.players[1].hand = [_glass(_card(7, "spades")), _glass(_card(8, "spades"))]
	# Rival (seat 2) can lay a 9s-10s-J run — but the 9s is a wait, so laying it
	# feeds the ron. The spare means laying it does not empty the hand (which
	# would win and override caution).
	gm.players[2].hand = [_card(9, "spades"), _card(10, "spades"), _card(11, "spades"),
		_card(2, "diamonds")]
	_begin_turn_for(gm, 2)
	var move := GreedyAI.plan_move(gm, null, null)
	if not move.is_empty():
		_fail("defender: should fold rather than lay the 9s that completes his hand")
	# A run with no wait card in it is safe to play.
	gm.players[2].hand = [_card(2, "clubs"), _card(3, "clubs"), _card(4, "clubs"),
		_card(2, "diamonds")]
	_begin_turn_for(gm, 2)
	var safe := GreedyAI.plan_move(gm, null, null)
	if safe.is_empty():
		_fail("defender: should play its run freely when it does not let Riichi go out")

## Full AI-vs-AI games with the Billionaire wired in: they must finish, keep
## every meld valid, and conserve all 108 cards (stock + discards + table + hands).
func _test_full_game_invariants() -> void:
	var declared_any := false
	for seed_value in range(1, 6):
		var gm := GameManager.new()
		gm.setup(["You", "The Sadistic Billionaire"], 7, seed_value, true)
		gm.draw_per_turn = 2
		gm.max_plays_per_turn = 13
		gm.meter_max = 3
		gm.meter_per_card = true
		var b := SadisticBillionaire.new()
		b.on_combat_start(gm)
		var profile := b.make_profile(seed_value)
		var turns := 0
		while not gm.is_game_over and turns < MAX_TURNS:
			var enemy: Enemy = b if gm.current_player().player_id == 1 else null
			GreedyAI.take_turn(gm, profile, enemy)
			turns += 1
			if gm.players[1].declared_riichi:
				declared_any = true
			if not gm.board.all_valid():
				_fail("full game %d: invalid meld after turn %d" % [seed_value, turns])
				return
			var count := gm.deck.size() + gm.deck.discards.size() + gm.board.all_cards().size()
			for p in gm.players:
				count += p.hand.size()
			if count != 108:
				_fail("full game %d: card conservation broken (%d) after turn %d"
					% [seed_value, count, turns])
				return
		if not gm.is_game_over:
			_fail("full game %d: did not finish within %d turns" % [seed_value, MAX_TURNS])
			return
		gm.free()
	if not declared_any:
		print("riichi_check: note — no Riichi was declared across the sampled games "
			+ "(the targeted tests cover the mechanic directly)")
