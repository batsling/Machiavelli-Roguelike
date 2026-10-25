extends SceneTree

## Headless smoke test for the vanilla engine. Run with:
##   godot --headless --path . --import        (first time, builds the class cache)
##   godot --headless --path . --script res://tests/smoke_test.gd
## Plays full AI-vs-AI games from fixed seeds (plain, with jokers, with AI
## profiles, with multi-card draws, with energy) and asserts core invariants
## after every single turn, plus unit tests for joker rules and the joker swap,
## per-player decks, energy and the run map.

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
	if not _test_play_cap():
		failures += 1
	if not _test_meter_charge():
		failures += 1
	if not _test_sticky_cluster():
		failures += 1
	if not _test_sticky_move():
		failures += 1
	if not _test_slime_free_move():
		failures += 1
	if not _test_glass_counting():
		failures += 1
	if not _test_glass_worth_holding():
		failures += 1
	if not _test_glass_exposure():
		failures += 1
	if not _test_glass_joker_reps():
		failures += 1
	if not _test_starting_melds():
		failures += 1
	if not _test_deep_planner():
		failures += 1
	if not _test_own_decks():
		failures += 1
	if not _test_energy():
		failures += 1
	if not _test_energy_ai():
		failures += 1
	if not _test_run_state():
		failures += 1
	if not _test_events():
		failures += 1
	if not _test_locations_sheet():
		failures += 1
	for seed_value in GAMES:
		if not _play_game(seed_value, "game"):
			failures += 1
	for seed_value in 10:
		if not _play_game(seed_value, "joker game", true):
			failures += 1
	# Top-skill AIs run the deck-counting smart brain and pick safe joker
	# stand-ins; make sure their games stay clean.
	for seed_value in 5:
		var strong := AIProfile.new(1.0, 0.0, 1.0, seed_value)
		if not _play_game(seed_value, "smart joker game", true, strong):
			failures += 1
	# Every corner of the three sliders (skill × style × attention), seeded so
	# replays are exact. Covers the smart brain (skill 1), the greedy tiers
	# (skill 0), and the blunder roll (attention 0).
	for strength: float in [0.0, 1.0]:
		for style: float in [0.0, 1.0]:
			for attention: float in [0.0, 1.0]:
				for seed_value in 3:
					var profile := AIProfile.new(strength, style, attention, seed_value)
					var label := "profile(%.0f,%.0f,%.0f) game" % [strength, style, attention]
					if not _play_game(seed_value, label, false, profile):
						failures += 1
	for seed_value in 5:
		if not _play_game(seed_value, "draw-3 game", false, null, 3):
			failures += 1
	for seed_value in 5:
		if not _play_game(seed_value, "capped game", false, null, 1, 15):
			failures += 1
	for seed_value in 5:
		if not _play_game(seed_value, "play-cap game", false, null, 1, 0, 10):
			failures += 1
	# Starting combos: every player begins opened with a random three-card meld
	# on the table, and the game must still play out cleanly from there.
	for seed_value in 5:
		if not _play_game(seed_value, "starting-combo game", true, null, 1, 0, 0, true):
			failures += 1
	# Energy games: the roguelike's rule — every card costs 1, energy starts at
	# 3 and grows by 1 a turn — must still play out cleanly, at every AI tier.
	for seed_value in 6:
		var profile: AIProfile = null if seed_value < 2 \
			else AIProfile.new(0.5 * (seed_value % 3), 0.0, 1.0, seed_value, 1.0)
		if not _play_energy_game(seed_value, profile):
			failures += 1
	# Event games: three random events per match on top of the run's energy
	# rule, with every pending choice resolved by the AI.
	for seed_value in 10:
		if not _play_event_game(seed_value):
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

## With a play cap, staging more hand cards than the cap is rejected, table
## rearranging stays free, returning a played card gives the play back, and
## a cap lowered mid-turn is caught at commit.
func _test_play_cap() -> bool:
	var gm := GameManager.new()
	var ok := true
	gm.setup(["P0", "P1"], 13, 9)
	gm.max_plays_per_turn = 3
	var p := gm.current_player()
	p.has_opened = true
	var three: Array[Card] = [p.hand[0], p.hand[1], p.hand[2]]
	var fourth: Array[Card] = [p.hand[3]]
	if gm.move_cards_to_new_meld(three) != "":
		printerr("play cap: staging up to the cap was rejected")
		ok = false
	elif gm.add_cards_to_meld(fourth, gm.board.melds[0]) == "":
		printerr("play cap: staging past the cap was allowed")
		ok = false
	# Rearranging cards already on the table costs nothing against the cap.
	var borrow: Array[Card] = [three[0]]
	if gm.move_cards_to_new_meld(borrow) != "":
		printerr("play cap: moving table cards should not count against the cap")
		ok = false
	# Returning a played card frees room for another.
	elif gm.return_cards_to_hand(borrow) != "":
		printerr("play cap: returning a played card was rejected")
		ok = false
	elif gm.move_cards_to_new_meld(fourth) != "":
		printerr("play cap: a play freed by a return was rejected")
		ok = false
	# 3 cards are played now; lowering the cap mid-turn must block the commit.
	gm.max_plays_per_turn = 2
	if ok and gm.commit_turn().find("only play") == -1:
		printerr("play cap: committing more plays than the cap was allowed")
		ok = false
	gm.free()
	if ok:
		print("play cap test OK")
	return ok

## The ultimate meter charges when a hand is committed: once per hand by
## default, meter_gain per card played when meter_per_card is on, capped at
## meter_max (where it holds), and off entirely at meter_max 0. meter_charged
## reports how much it rose and fires now_full only on the filling charge.
func _test_meter_charge() -> bool:
	var gm := GameManager.new()
	var ok := true
	gm.setup(["P0", "P1"], 13, 5)
	gm.meter_max = 5
	gm.meter_gain = 1
	# Emitted charges, [amount, now_full] each. An Array is a reference type, so
	# the lambda (which captures outer locals by value) can still record into it.
	var events: Array = []
	gm.meter_charged.connect(func(_pl: PlayerState, amount: int, full: bool) -> void:
		events.append([amount, full]))
	var p := gm.players[0]
	# Per hand: one charge, whatever the card count.
	gm._charge_meter(p, 4)
	if p.meter != 1 or events != [[1, false]]:
		printerr("meter: a per-hand charge should add gain once, got %d (events %s)"
			% [p.meter, events])
		ok = false
	# Per card: gain × cards played; +4 here fills the meter (1 -> 5).
	gm.meter_per_card = true
	gm.meter_gain = 2
	gm._charge_meter(p, 2)
	if p.meter != 5:
		printerr("meter: a per-card charge should add gain×cards, got %d" % p.meter)
		ok = false
	elif events.size() != 2 or events[1] != [4, true]:
		var got: Variant = events[1] if events.size() > 1 else events
		printerr("meter: filling should emit [4, true], got %s" % [got])
		ok = false
	# Holds at max: a further charge adds nothing and emits nothing.
	gm._charge_meter(p, 3)
	if p.meter != 5:
		printerr("meter: a full meter should hold at max, got %d" % p.meter)
		ok = false
	elif events.size() != 2:
		printerr("meter: a no-op charge should not re-emit, got %d events" % events.size())
		ok = false
	# A disabled meter (max 0) never charges.
	gm.meter_max = 0
	p.meter = 0
	gm._charge_meter(p, 3)
	if p.meter != 0:
		printerr("meter: a disabled meter should not charge, got %d" % p.meter)
		ok = false
	gm.free()
	# End to end: committing a hand charges the committing player via commit_turn.
	var gm2 := GameManager.new()
	gm2.setup(["P0", "P1"], 13, 5)
	gm2.meter_max = 10
	var q := gm2.current_player()
	q.has_opened = true
	q.hand.assign([_card(7, "hearts"), _card(7, "spades"), _card(7, "clubs")])
	gm2._hand_snapshot = q.hand.duplicate()
	var play: Array[Card] = [q.hand[0], q.hand[1], q.hand[2]]
	if gm2.move_cards_to_new_meld(play) != "":
		printerr("meter: staging the commit play was rejected")
		ok = false
	elif gm2.commit_turn() != "":
		printerr("meter: committing the hand failed")
		ok = false
	elif q.meter != 1:
		printerr("meter: commit_turn should charge the meter, got %d" % q.meter)
		ok = false
	gm2.free()
	if ok:
		print("meter charge test OK")
	return ok

func _sticky(card: Card) -> Card:
	card.effects.append(Card.Effect.STICKY)
	return card

func _glass(card: Card) -> Card:
	card.effects.append(Card.Effect.CLEAR)
	return card

## Same cards in the same order (by identity)?
func _same(got: Array, want: Array) -> bool:
	if got.size() != want.size():
		return false
	for i in got.size():
		if got[i] != want[i]:
			return false
	return true

## Slimed cards only stick to each other: the cluster is the run of consecutive
## slimed cards, read in display order. A plain card, or a slimed card with no
## slimed neighbour, is its own singleton.
func _test_sticky_cluster() -> bool:
	var ok := true
	# A run of hearts with the two middle cards slimed: they bind each other, the
	# plain ends stay free.
	var meld := CardSet.new()
	var c2 := _card(2, "hearts")
	var c3 := _sticky(_card(3, "hearts"))
	var c4 := _sticky(_card(4, "hearts"))
	var c5 := _card(5, "hearts")
	meld.cards.assign([c2, c3, c4, c5])
	if not _same(meld.sticky_cluster(c3), [c3, c4]):
		printerr("sticky cluster: 3♥+4♥ slime should bind just {3,4}, got %s"
			% _labels(meld.sticky_cluster(c3)))
		ok = false
	if not _same(meld.sticky_cluster(c4), [c3, c4]):
		printerr("sticky cluster: 4♥ should report the same {3,4} cluster")
		ok = false
	if not _same(meld.sticky_cluster(c2), [c2]):
		printerr("sticky cluster: plain 2♥ should be a singleton, got %s"
			% _labels(meld.sticky_cluster(c2)))
		ok = false
	# A lone slimed card among plain cards has no slimed neighbour: singleton.
	var lonely := CardSet.new()
	var s8 := _sticky(_card(8, "spades"))
	lonely.cards.assign([_card(7, "spades"), s8, _card(9, "spades")])
	if not _same(lonely.sticky_cluster(s8), [s8]):
		printerr("sticky cluster: a lone slimed card should be a singleton, got %s"
			% _labels(lonely.sticky_cluster(s8)))
		ok = false
	if ok:
		print("sticky cluster test OK")
	return ok

## Moving one card of a slime cluster drags the whole cluster with it; a slimed
## card with no slimed neighbour, and a plain card, move on their own.
func _test_sticky_move() -> bool:
	var gm := GameManager.new()
	var ok := true
	gm.setup(["P0", "P1"], 13, 4)
	gm.current_player().has_opened = true
	var c4 := _card(4, "hearts")
	var c5 := _sticky(_card(5, "hearts"))
	var c6 := _sticky(_card(6, "hearts"))
	var c7 := _card(7, "hearts")
	var meld := CardSet.new()
	meld.cards.assign([c4, c5, c6, c7])
	gm.board.melds.append(meld)
	# Grabbing just the 5♥ pulls its {5,6} slime cluster onto the new group; the
	# plain 4♥ and 7♥ stay behind.
	var grab: Array[Card] = [c5]
	if gm.move_cards_to_new_meld(grab) != "":
		printerr("sticky move: staging the cluster move was rejected")
		ok = false
	elif gm.board.melds.size() != 2:
		printerr("sticky move: expected 2 groups after the move, got %d"
			% gm.board.melds.size())
		ok = false
	else:
		if not _same(gm.board.melds[1].cards, [c5, c6]):
			printerr("sticky move: new group should hold {5,6} in order, got %s"
				% _labels(gm.board.melds[1].cards))
			ok = false
		elif not _same(gm.board.melds[0].cards, [c4, c7]):
			printerr("sticky move: 4♥ and 7♥ should have stayed behind, got %s"
				% _labels(gm.board.melds[0].cards))
			ok = false
	gm.free()
	if ok:
		print("sticky move test OK")
	return ok

## A player that ignores_sticky (the Cute Slime) moves a slimed card on its own,
## leaving its cluster-mates behind.
func _test_slime_free_move() -> bool:
	var gm := GameManager.new()
	var ok := true
	gm.setup(["P0", "P1"], 13, 4)
	var p := gm.current_player()
	p.has_opened = true
	p.ignores_sticky = true
	var c4 := _card(4, "hearts")
	var c5 := _sticky(_card(5, "hearts"))
	var c6 := _sticky(_card(6, "hearts"))
	var c7 := _card(7, "hearts")
	var meld := CardSet.new()
	meld.cards.assign([c4, c5, c6, c7])
	gm.board.melds.append(meld)
	# The slime lifts 5♥ alone onto a new group even though 6♥ is stuck to it.
	var grab: Array[Card] = [c5]
	if gm.move_cards_to_new_meld(grab) != "":
		printerr("slime free move: staging the free move was rejected")
		ok = false
	elif not _same(gm.board.melds[-1].cards, [c5]):
		printerr("slime free move: only 5♥ should have moved, got %s"
			% _labels(gm.board.melds[-1].cards))
		ok = false
	elif not _same(gm.board.melds[0].cards, [c4, c6, c7]):
		printerr("slime free move: 6♥ should have stayed behind, got %s"
			% _labels(gm.board.melds[0].cards))
		ok = false
	gm.free()
	if ok:
		print("slime free move test OK")
	return ok

## The slime legally combines slimed cards to guard her most valuable ones,
## The deep-rearrangement planner (the planning dial): an expert planner chains
## board relocations to lay down a hand play no borrow reaches, while the
## short-sighted and middle tiers, whose budgets are too small, don't. Rebuilds
## the winning line the Sadistic Billionaire missed before the planner existed:
## shift A♠ onto the high spades, slide 5♣ onto the low clubs, then pull the
## freed 2♠ and 2♣ in with the hand's 2♥ to make a set of twos and go out — four
## board movements, so only the expert budget can afford it.
func _test_deep_planner() -> bool:
	var ok := true
	for tier: Array in [[0.0, false], [0.5, false], [1.0, true]]:
		var gm := GameManager.new()
		gm.setup(["AI"], 13, 7, false)
		var p := gm.current_player()
		p.has_opened = true
		gm.board.melds.clear()
		_append_meld(gm, [_card(1, "spades"), _card(2, "spades"), _card(3, "spades"),
			_card(4, "spades"), _card(5, "spades")])
		_append_meld(gm, [_card(11, "spades"), _card(12, "spades"), _card(13, "spades")])
		_append_meld(gm, [_card(2, "clubs"), _card(3, "clubs"), _card(4, "clubs")])
		_append_meld(gm, [_card(5, "clubs"), _card(5, "diamonds"), _card(5, "hearts"),
			_card(5, "spades")])
		p.hand.assign([_card(2, "hearts")])
		gm._hand_snapshot = p.hand.duplicate()
		var prof := AIProfile.new(1.0, 0.0, 1.0, 1, tier[0])
		var move := GreedyAI.plan_move(gm, prof, null)
		var found: bool = move.has("rearrange")
		if found != tier[1]:
			printerr("deep planner: budget %d expected rearrange=%s, got %s"
				% [prof.plan_budget(), tier[1], found])
			ok = false
			continue
		if not found:
			continue
		GreedyAI.apply_move(gm, move, prof)
		if not p.hand.is_empty():
			printerr("deep planner: the expert plan should empty the hand, %d left"
				% p.hand.size())
			ok = false
		for m in gm.board.melds:
			if not m.is_valid():
				printerr("deep planner: left an invalid group: %s" % _labels(m.cards))
				ok = false
		if gm.commit_turn() != "":
			printerr("deep planner: the winning turn should commit cleanly")
			ok = false
	return ok

func _append_meld(gm: GameManager, cards: Array) -> void:
	var cs := CardSet.new()
	for c: Card in cards:
		cs.add_card(c)
	gm.board.melds.append(cs)

## The AI's glass counting reads only public information: glass cards in other
## players' hands and a glass top of the stock — never a face-down card.
func _test_glass_counting() -> bool:
	var gm := GameManager.new()
	var ok := true
	gm.setup(["P0", "P1"], 13, 3)
	gm.players[0].hand.clear()
	gm.players[1].hand.clear()
	gm.players[1].hand.append(_glass(_card(8, "hearts")))
	gm.players[1].hand.append(_card(8, "spades"))
	if GreedyAI._glass_copies_in_other_hands(gm, 8, "hearts") != 1:
		printerr("glass counting: the glass 8♥ in P1's hand should be visible")
		ok = false
	if GreedyAI._glass_copies_in_other_hands(gm, 8, "spades") != 0:
		printerr("glass counting: a non-glass hand card must stay hidden")
		ok = false
	# The top of the stock is public only when the card there is glass.
	gm.players[0].deck.cards.append(_card(12, "spades"))
	if GreedyAI._glass_top_matches(gm, 12, "spades"):
		printerr("glass counting: a face-down stock top must not be readable")
		ok = false
	gm.players[0].deck.cards.append(_glass(_card(11, "clubs")))
	if not GreedyAI._glass_top_matches(gm, 11, "clubs"):
		printerr("glass counting: a glass stock top should be readable")
		ok = false
	# Obtainable copies: one 8♥ on the table plus one visibly locked in P1's
	# glass hand leaves nothing for P0 to chase; the hidden 8♠ stays a maybe.
	var meld := CardSet.new()
	meld.cards.assign([_card(8, "hearts"), _card(9, "hearts"), _card(10, "hearts")])
	gm.board.melds.append(meld)
	if GreedyAI._obtainable_copies(gm, 8, "hearts") != 0:
		printerr("glass counting: both 8♥ are accounted for — none obtainable")
		ok = false
	if GreedyAI._obtainable_copies(gm, 8, "spades") != 2:
		printerr("glass counting: the face-down 8♠ must still count as obtainable")
		ok = false
	gm.free()
	if ok:
		print("glass counting test OK")
	return ok

## Glass steers what the smart AI holds back: a lone card pairing with the
## glass top of the stock is worth keeping (the next draw is public), and a
## pair whose completions all sit visibly in glass opponent hands is a dead
## end it stops holding.
func _test_glass_worth_holding() -> bool:
	var gm := GameManager.new()
	var ok := true
	gm.setup(["P0", "P1"], 13, 3)
	gm.players[0].hand.clear()
	gm.players[1].hand.clear()
	var none: Array[Card] = []
	var five := _card(5, "hearts")
	if GreedyAI._worth_holding(gm, five, none):
		printerr("glass hold: a lone 5♥ with no partner is not worth holding")
		ok = false
	gm.players[0].deck.cards.append(_glass(_card(6, "hearts")))
	if not GreedyAI._worth_holding(gm, five, none):
		printerr("glass hold: the glass 6♥ atop the stock should make 5♥ worth holding")
		ok = false
	# A 9♥/9♠ pair: one copy each of 9♦ and 9♣ is on the table. While the
	# remaining copies could be anywhere the pair is worth holding; once they
	# show glass in P1's hand the set can never be completed by P0.
	var nine := _card(9, "hearts")
	var partner: Array[Card] = [_card(9, "spades")]
	var run_d := CardSet.new()
	run_d.cards.assign([_card(9, "diamonds"), _card(10, "diamonds"), _card(11, "diamonds")])
	var run_c := CardSet.new()
	run_c.cards.assign([_card(9, "clubs"), _card(10, "clubs"), _card(11, "clubs")])
	gm.board.melds.append(run_d)
	gm.board.melds.append(run_c)
	if not GreedyAI._worth_holding(gm, nine, partner):
		printerr("glass hold: with a 9♦/9♣ still unaccounted the pair is worth holding")
		ok = false
	gm.players[1].hand.append(_glass(_card(9, "diamonds")))
	gm.players[1].hand.append(_glass(_card(9, "clubs")))
	if GreedyAI._worth_holding(gm, nine, partner):
		printerr("glass hold: every completion visibly locked in P1's hand is a dead end")
		ok = false
	gm.free()
	if ok:
		print("glass worth-holding test OK")
	return ok

## Feed avoidance weighs certain threats: a run's open end an opponent visibly
## holds (glass) counts double an unseen one, and a matching glass top of the
## stock adds the draw threat on top.
func _test_glass_exposure() -> bool:
	var gm := GameManager.new()
	var ok := true
	gm.setup(["P0", "P1"], 13, 3)
	gm.players[0].hand.clear()
	gm.players[1].hand.clear()
	var run: Array[Card] = [_card(5, "hearts"), _card(6, "hearts"), _card(7, "hearts")]
	var base := GreedyAI._open_end_exposure(gm, run)
	if base != 4:
		printerr("glass exposure: baseline 4♥+8♥ exposure should be 4, got %d" % base)
		ok = false
	gm.players[1].hand.append(_glass(_card(8, "hearts")))
	var held := GreedyAI._open_end_exposure(gm, run)
	if held != 5:
		printerr("glass exposure: the glass 8♥ in P1's hand should add 1, got %d" % held)
		ok = false
	gm.players[0].deck.cards.append(_glass(_card(4, "hearts")))
	var topped := GreedyAI._open_end_exposure(gm, run)
	if topped != 6:
		printerr("glass exposure: the glass 4♥ atop the stock should add 1, got %d" % topped)
		ok = false
	gm.free()
	if ok:
		print("glass exposure test OK")
	return ok

## A joker is never pointed at a stand-in whose swap card an opponent visibly
## holds: with the glass 9♣ in P1's hand, clubs is a guaranteed claim, so the
## joker stands for the 9♦ instead (without glass the tie-break picks clubs).
func _test_glass_joker_reps() -> bool:
	var gm := GameManager.new()
	var ok := true
	gm.setup(["P0", "P1"], 13, 11, true)
	gm.players[0].hand.clear()
	gm.players[1].hand.clear()
	gm.players[1].hand.append(_glass(_card(9, "clubs")))
	var joker := _joker()
	var meld := CardSet.new()
	meld.cards.assign([_card(9, "hearts"), _card(9, "spades"), joker])
	gm.board.melds.append(meld)
	GreedyAI._choose_joker_reps(gm, meld)
	Rules.assign_jokers(meld.cards)
	if joker.joker_suit != "diamonds":
		printerr("glass joker reps: joker should avoid the visibly-held 9♣, got %s"
			% joker.rep_label())
		ok = false
	gm.free()
	if ok:
		print("glass joker reps test OK")
	return ok

func _labels(cards: Array[Card]) -> String:
	var parts := PackedStringArray()
	for c in cards:
		parts.append(c.label())
	return " ".join(parts)

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

## A joker locks to the card it stands for the moment it lands in a valid
## meld on the table: it is then treated as exactly that card (not a
## wildcard) when rearranged, keeps its face even in a broken meld, and only
## unlocks when it returns to a hand (swap, undo or return). While the
## placing turn is still open the placer may re-point it among the valid
## alternatives (set_joker_stand_in); every step is undoable and the choice
## is final once the turn ends.
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
	var take_back: Array[Card] = [joker]
	if gm.move_cards_to_new_meld(played) != "":
		printerr("lock test: staging the joker run was rejected")
		ok = false
	elif joker.joker_lock_rank != 7 or joker.joker_lock_suit != "hearts":
		printerr("lock test: joker should lock as 7 of hearts on placement, got %s"
			% joker.rep_label())
		ok = false
	# Taking the played joker back into the hand frees it; undoing the return
	# locks it again.
	elif gm.return_cards_to_hand(take_back) != "":
		printerr("lock test: returning the played joker was rejected")
		ok = false
	elif joker.joker_lock_rank != 0 or joker.joker_rank != 0:
		printerr("lock test: a joker back in the hand should be a free wildcard")
		ok = false
	elif not gm.undo_action():
		printerr("lock test: the return was not undoable")
		ok = false
	elif joker.joker_lock_rank != 7 or joker.joker_lock_suit != "hearts":
		printerr("lock test: undoing the return should restore the lock")
		ok = false
	if not ok:
		gm.free()
		return false
	# The placer may re-point the joker among the valid alternatives this
	# turn — an undoable move — but never at a card that doesn't fit.
	var meld: CardSet = gm.board.melds[0]
	if gm.set_joker_stand_in(joker, meld, 4, "hearts") != "":
		printerr("lock test: re-pointing the just-placed joker was rejected")
		ok = false
	elif joker.joker_lock_rank != 4 or joker.joker_lock_suit != "hearts":
		printerr("lock test: joker should re-lock as 4 of hearts, got %s"
			% joker.rep_label())
		ok = false
	elif gm.set_joker_stand_in(joker, meld, 9, "hearts") == "":
		printerr("lock test: an impossible stand-in was accepted")
		ok = false
	elif not gm.undo_action():
		printerr("lock test: the re-choice was not undoable")
		ok = false
	elif joker.joker_lock_rank != 7:
		printerr("lock test: undo should restore the 7 of hearts lock")
		ok = false
	elif gm.commit_turn() != "":
		printerr("lock test: committing the joker run failed")
		ok = false
	elif joker.joker_lock_rank != 7 or joker.joker_lock_suit != "hearts":
		printerr("lock test: joker should stay locked as 7 of hearts after commit, got %s"
			% joker.rep_label())
		ok = false
	# The placing turn is over: the choice is final.
	elif gm.set_joker_stand_in(joker, gm.board.melds[0], 4, "hearts") == "":
		printerr("lock test: re-pointing after the placing turn was allowed")
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

## deal_starting_melds gives every player a valid three-card meld of naturals
## pulled from their own deck, marks them opened, and conserves every card.
func _test_starting_melds() -> bool:
	var gm := GameManager.new()
	var ok := true
	gm.setup(["P0", "P1", "P2"], 13, 5, true)
	gm.deal_starting_melds()
	if gm.board.melds.size() != 3:
		printerr("starting melds: expected 3 melds on the table, got %d"
			% gm.board.melds.size())
		ok = false
	for m in gm.board.melds:
		if m.cards.size() != 3 or not m.is_valid():
			printerr("starting melds: expected a valid 3-card meld, got %s"
				% _labels(m.cards))
			ok = false
		for c in m.cards:
			if c.is_joker:
				printerr("starting melds: a joker was dealt into a starting meld")
				ok = false
	for p in gm.players:
		if not p.has_opened:
			printerr("starting melds: %s should count as opened" % p.display_name)
			ok = false
		if p.hand.size() != 13:
			printerr("starting melds: hands must stay untouched, %s has %d cards"
				% [p.display_name, p.hand.size()])
			ok = false
		if p.deck.size() != 54 - 13 - 3:
			printerr("starting melds: %s's meld should come from their own deck"
				% p.display_name)
			ok = false
	for m in gm.board.melds:
		var owner := m.cards[0].deck_owner
		for c in m.cards:
			if c.deck_owner != owner:
				printerr("starting melds: a meld mixed cards from two decks")
				ok = false
	var count := gm.cards_left_in_decks() + gm.board.all_cards().size()
	for p in gm.players:
		count += p.hand.size()
	if count != 162:
		printerr("starting melds: card conservation broken (%d)" % count)
		ok = false
	gm.free()
	if ok:
		print("starting melds test OK")
	return ok

func _play_game(seed_value: int, label: String, include_jokers := false,
		profile: AIProfile = null, draw_per_turn := 1, max_hand_size := 0,
		max_plays := 0, start_melds := false) -> bool:
	var gm := GameManager.new()
	gm.setup(["P0", "P1", "P2"], 13, seed_value, include_jokers)
	gm.draw_per_turn = draw_per_turn
	gm.max_hand_size = max_hand_size
	gm.max_plays_per_turn = max_plays
	if start_melds:
		gm.deal_starting_melds()
	var total_cards := _cards_in_game(gm)
	var turns := 0
	while not gm.is_game_over and turns < MAX_TURNS:
		GreedyAI.take_turn(gm, profile)
		turns += 1
		if not gm.board.all_valid():
			printerr("%s %d: invalid meld on table after turn %d" % [label, seed_value, turns])
			return false
		var count := _cards_in_game(gm)
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

## Every card in the game right now: what is left in each player's deck (and
## its discards), every hand and the table.
func _cards_in_game(gm: GameManager) -> int:
	var count := gm.board.all_cards().size()
	for p in gm.players:
		count += p.deck.size() + p.deck.discards.size() + p.hand.size()
	return count

## A 1v1 game under the roguelike's energy rule, driven move by move so every
## single staged move can be checked against the mover's energy: no AI move
## may ever spend more than the turn's ceiling. Card conservation and a valid
## table must hold after every turn, and the game must finish.
func _play_energy_game(seed_value: int, profile: AIProfile) -> bool:
	var gm := GameManager.new()
	gm.start_energy = 3
	gm.energy_per_turn = 1
	gm.energy_cap = 10
	gm.setup(["P0", "P1"], 13, seed_value, true)
	gm.draw_per_turn = 2
	gm.deal_starting_melds()
	var label := "energy game"
	var total_cards := _cards_in_game(gm)
	var turns := 0
	while not gm.is_game_over and turns < MAX_TURNS:
		while true:
			var move := GreedyAI.plan_move(gm, profile)
			if move.is_empty():
				break
			GreedyAI.apply_move(gm, move, profile)
			if gm.energy_spent() > gm.current_player().max_energy:
				printerr("%s %d: AI spent %d energy with a ceiling of %d" % [label,
					seed_value, gm.energy_spent(), gm.current_player().max_energy])
				return false
		if gm.cards_played_this_turn() > 0:
			var err := gm.commit_turn()
			if err != "":
				printerr("%s %d: AI staged an illegal turn: %s" % [label, seed_value, err])
				return false
		else:
			gm.draw_and_end_turn()
		turns += 1
		if not gm.board.all_valid():
			printerr("%s %d: invalid meld on table after turn %d" % [label, seed_value, turns])
			return false
		if _cards_in_game(gm) != total_cards:
			printerr("%s %d: card conservation broken after turn %d"
				% [label, seed_value, turns])
			return false
	if not gm.is_game_over:
		printerr("%s %d: did not finish within %d turns" % [label, seed_value, MAX_TURNS])
		return false
	print("%s %d: finished in %d turns" % [label, seed_value, turns])
	gm.free()
	return true

## Every player brings and draws from their own deck: a standard deck is 52
## cards (+2 jokers) all tagged with its owner, hands are dealt from it, a draw
## takes only from the drawer's deck, a custom deck passed to setup is used and
## re-tagged to its seat, and a player whose deck is empty passes.
func _test_own_decks() -> bool:
	var gm := GameManager.new()
	var ok := true
	gm.setup(["P0", "P1"], 13, 21, true)
	for p in gm.players:
		if p.deck.size() != 54 - 13:
			printerr("own decks: %s should have 41 cards left, has %d"
				% [p.display_name, p.deck.size()])
			ok = false
		for c in p.deck.cards + p.hand:
			if c.deck_owner != p.player_id:
				printerr("own decks: %s holds a card from deck %d"
					% [p.display_name, c.deck_owner])
				ok = false
				break
	if gm.copies_in_play(5, "hearts") != 2:
		printerr("own decks: two standard decks hold 2 copies of 5♥, counted %d"
			% gm.copies_in_play(5, "hearts"))
		ok = false
	var before0 := gm.players[0].deck.size()
	var before1 := gm.players[1].deck.size()
	gm.draw_and_end_turn()
	if gm.players[0].deck.size() != before0 - 1 or gm.players[1].deck.size() != before1:
		printerr("own decks: P0's draw must come from P0's deck only")
		ok = false
	gm.free()
	# A custom deck (an enemy's authored deck) replaces the standard one.
	gm = GameManager.new()
	var custom := Deck.new(3)
	for rank in range(1, 14):
		for suit in ["hearts", "spades"]:
			var c := _card(rank, suit)
			custom.cards.append(c)
	gm.setup(["P0", "P1"], 13, 4, false, [null, custom])
	if gm.players[1].deck.size() != 26 - 13:
		printerr("own decks: the custom deck should be dealt from, %d left"
			% gm.players[1].deck.size())
		ok = false
	for c in gm.players[1].hand:
		if c.deck_owner != 1 or (c.suit != "hearts" and c.suit != "spades"):
			printerr("own decks: the custom deck's cards should be dealt and re-tagged")
			ok = false
			break
	# Deck-out: with nothing left to draw, a draw is a pass.
	gm.players[0].deck.cards.clear()
	var passed := [false]
	gm.player_passed.connect(func(_p: PlayerState) -> void: passed[0] = true)
	gm.draw_and_end_turn()
	if not passed[0]:
		printerr("own decks: drawing from an empty deck should pass")
		ok = false
	gm.free()
	if ok:
		print("own decks test OK")
	return ok

## Energy: every card costs 1; a player starts at start_energy, gains
## energy_per_turn each turn up to energy_cap, and never carries energy over.
## Staging past the energy left is refused, rearranging the table is free, and
## undoing or returning a card refunds it. Energy off means no limit at all.
func _test_energy() -> bool:
	var gm := GameManager.new()
	var ok := true
	gm.start_energy = 3
	gm.energy_per_turn = 1
	gm.energy_cap = 5
	gm.setup(["P0", "P1"], 13, 8)
	var p := gm.current_player()
	if p.max_energy != 3 or gm.energy_left() != 3:
		printerr("energy: first turn should start at 3, got %d/%d"
			% [gm.energy_left(), p.max_energy])
		ok = false
	p.has_opened = true
	p.hand.clear()
	var run: Array[Card] = [_card(5, "hearts"), _card(6, "hearts"), _card(7, "hearts")]
	var eight := _card(8, "hearts")
	p.hand.append_array(run)
	p.hand.append(eight)
	p.hand.append(_card(2, "clubs"))
	gm._hand_snapshot = p.hand.duplicate()
	if gm.move_cards_to_new_meld(run) != "":
		printerr("energy: three cards with 3 energy should be playable")
		ok = false
	if gm.energy_left() != 0:
		printerr("energy: 3 cards played should leave 0, got %d" % gm.energy_left())
		ok = false
	var one: Array[Card] = [eight]
	if gm.add_cards_to_meld(one, gm.board.melds[-1]).find("energy") == -1:
		printerr("energy: a fourth card with no energy left must be refused")
		ok = false
	# Rearranging cards already on the table is free.
	var table_card: Array[Card] = [run[2]]
	if gm.move_cards_to_new_meld(table_card) != "":
		printerr("energy: moving a table card must not cost energy")
		ok = false
	gm.undo_action()
	# Returning a played card refunds it; undo refunds too.
	if gm.return_cards_to_hand(table_card) != "" or gm.energy_left() != 1:
		printerr("energy: returning a played card should refund 1, have %d" % gm.energy_left())
		ok = false
	gm.undo_action()
	if gm.energy_left() != 0:
		printerr("energy: undoing the return should spend it again")
		ok = false
	if gm.commit_turn() != "":
		printerr("energy: committing a 3-card meld should work")
		ok = false
	# P1 starts their own first turn at 3; P0's next turn is 4, then the cap.
	if gm.current_player().max_energy != 3:
		printerr("energy: P1's first turn should be 3, got %d" % gm.current_player().max_energy)
		ok = false
	var want := [4, 5, 5]
	for w: int in want:
		gm.draw_and_end_turn()  # P1 draws
		if gm.current_player() != p or p.max_energy != w or gm.energy_left() != w:
			printerr("energy: P0 should refill to %d (no carry-over), got %d/%d"
				% [w, gm.energy_left(), p.max_energy])
			ok = false
		gm.draw_and_end_turn()  # P0 draws
	gm.free()
	# Energy off: no limit, no ceiling.
	gm = GameManager.new()
	gm.setup(["P0", "P1"], 13, 8)
	if gm.energy_on() or gm.play_budget() != -1 or gm.current_player().max_energy != 0:
		printerr("energy: with start_energy 0 energy must be off")
		ok = false
	gm.free()
	if ok:
		print("energy test OK")
	return ok

## The AI plans inside its energy: holding a five-card run with 3 energy it
## lays three of them rather than giving up the turn, and with 0 energy left it
## plans nothing.
func _test_energy_ai() -> bool:
	var gm := GameManager.new()
	var ok := true
	gm.start_energy = 3
	gm.setup(["P0", "P1"], 13, 2)
	var p := gm.current_player()
	p.hand.clear()
	for rank in range(3, 8):
		p.hand.append(_card(rank, "spades"))
	p.hand.append(_card(12, "hearts"))
	gm._hand_snapshot = p.hand.duplicate()
	var move := GreedyAI.plan_move(gm, null)
	if move.is_empty() or (move["cards"] as Array).size() != 3 \
			or not Rules.is_valid_meld(move["cards"]):
		printerr("energy AI: should lay a valid 3-card part of its run, got %s" % str(move))
		ok = false
	else:
		GreedyAI.apply_move(gm, move, null)
		if not GreedyAI.plan_move(gm, null).is_empty():
			printerr("energy AI: with 0 energy left nothing more should be planned")
			ok = false
	gm.free()
	if ok:
		print("energy AI test OK")
	return ok

## The run map: three nodes in a line, 3 lives. Only the next node is open; a
## loss costs a life and leaves the node open to retry; a win clears it and
## opens the next; the run is lost at 0 lives and won when the last node falls.
func _test_run_state() -> bool:
	var ok := true
	var run := RunState.linear(Enemy.roster(), 3)
	if run.rows.size() != 3 or run.lives != 3:
		printerr("run state: expected 3 nodes and 3 lives")
		ok = false
	var n0 := run.node_at(0, 0)
	var n1 := run.node_at(1, 0)
	var n2 := run.node_at(2, 0)
	if run.available_nodes() != [n0] or run.begin(n1):
		printerr("run state: only the first node should be open at the start")
		ok = false
	run.begin(n0)
	run.record_loss()
	if run.lives != 2 or not run.is_available(n0) or n0.cleared:
		printerr("run state: a loss should cost a life and leave the node open")
		ok = false
	run.begin(n0)
	run.record_win()
	if not n0.cleared or run.available_nodes() != [n1] or run.cleared_count() != 1:
		printerr("run state: a win should clear the node and open the next")
		ok = false
	run.begin(n1)
	run.record_win()
	run.begin(n2)
	run.record_loss()
	run.begin(n2)
	run.record_loss()
	if not run.is_lost() or not run.is_over() or not run.available_nodes().is_empty():
		printerr("run state: at 0 lives the run should be over")
		ok = false
	var won := RunState.linear(Enemy.roster(), 3)
	for r in 3:
		won.begin(won.node_at(r, 0))
		won.record_win()
	if not won.is_won() or won.lives != 3:
		printerr("run state: clearing the last node should win the run")
		ok = false
	if ok:
		print("run state test OK")
	return ok

## A 1v1 energy game with these events (MatchEvent ids) in reveal order.
func _event_gm(ids: Array, seed_value := 31) -> GameManager:
	var gm := GameManager.new()
	gm.start_energy = 3
	var deck: Array[MatchEvent] = []
	for id_value: int in ids:
		deck.append(MatchEvent.new(id_value))
	gm.event_deck = deck
	gm.setup(["P0", "P1"], 13, seed_value)
	return gm

## Give the current player an opened, known hand: the given cards plus a filler.
func _known_hand(gm: GameManager, cards: Array[Card]) -> void:
	var p := gm.current_player()
	p.has_opened = true
	p.hand.clear()
	p.hand.append_array(cards)
	p.hand.append(_card(2, "clubs"))
	gm._hand_snapshot = p.hand.duplicate()

## The Locations sheet (data/locations/, from tools/Machiavelli Roguelike.xlsx)
## against the code: every rule has a row, the pool follows the sheet, each card
## has a name and text, the sheet's Type agrees with how the rule is written, and
## the numbers the text promises are the numbers the rules use.
func _test_locations_sheet() -> bool:
	var ok := true
	var pool := MatchEvent.pool()
	if pool.size() != MatchEvent.ID_NAMES.size():
		printerr("locations: pool has %d events, the code has %d rules"
			% [pool.size(), MatchEvent.ID_NAMES.size()])
		ok = false
	for id_value: int in MatchEvent.ID_NAMES:
		var loc := Locations.get_by_id(MatchEvent.ID_NAMES[id_value])
		if loc == null:
			printerr("locations: no sheet row for '%s'" % MatchEvent.ID_NAMES[id_value])
			ok = false
			continue
		var e := MatchEvent.new(id_value)
		if e.title != loc.title or e.text != loc.text or e.text == "":
			printerr("locations: '%s' did not take its name and text from the sheet" % loc.id)
			ok = false
		if loc.kind != ("ongoing" if e.is_ongoing() else "on_reveal"):
			printerr("locations: the sheet makes %s '%s', its rule disagrees" % [loc.title, loc.kind])
			ok = false
	var ev := MatchEvent.Id
	var promises := {
		ev.CYCLE: MatchEvent.CHOICE_COUNT,
		ev.GIFT: MatchEvent.CHOICE_COUNT,
		ev.SURGE: MatchEvent.SURGE_ENERGY,
		ev.OVERCHARGE: MatchEvent.OVERCHARGE_ENERGY,
	}
	for id_value: int in promises:
		var e := MatchEvent.new(id_value)
		if not e.text.contains(str(promises[id_value])):
			printerr("locations: %s's text '%s' does not say %d, the number its rule uses"
				% [e.title, e.text, promises[id_value]])
			ok = false
	if ok:
		print("locations sheet test OK")
	return ok

## The eight events: the reveal schedule (rounds 1, 3, 5), each event's rule,
## the pending choices (blocking play until resolved, for the human-style API
## and the AI alike), and an early reveal.
func _test_events() -> bool:
	var ok := true
	var ev := MatchEvent.Id
	# Schedule: one up at the deal, the rest at the start of rounds 3 and 5.
	var gm := _event_gm([ev.OVERCHARGE, ev.EXTRA_DRAW, ev.OPEN_DECKS])
	if gm.revealed_events.size() != 1 or gm.upcoming_events().size() != 2 \
			or gm.upcoming_events()[0]["round"] != 3 or gm.upcoming_events()[1]["round"] != 5:
		printerr("events: expected 1 revealed and 2 upcoming (rounds 3, 5)")
		ok = false
	var revealed_by_round := {}
	while gm.round_number <= 5:
		revealed_by_round[gm.round_number] = gm.revealed_events.size()
		gm.draw_and_end_turn()
	if revealed_by_round != {1: 1, 2: 1, 3: 2, 4: 2, 5: 3}:
		printerr("events: wrong reveal schedule %s" % str(revealed_by_round))
		ok = false
	# Each reveal put its combo on the table: three valid groups of fresh cards
	# from outside both decks, counted as extra copies.
	if gm.board.melds.size() != 3:
		printerr("events: 3 reveals should put 3 combos on the table, got %d"
			% gm.board.melds.size())
		ok = false
	for e in gm.revealed_events:
		var meld := gm.board.meld_of(e.combo[0])
		if e.combo.size() != 3 or meld == null or not meld.is_valid():
			printerr("events: %s's combo should be a valid 3-card group on the table" % e.title)
			ok = false
		for c in e.combo:
			if c.deck_owner != MatchEvent.NO_OWNER or c.is_joker \
					or gm.players[0].deck.cards.has(c) or gm.players[1].deck.cards.has(c):
				printerr("events: combo cards must be fresh naturals from no one's deck")
				ok = false
	var combo_card := gm.revealed_events[0].combo[0]
	var extra := 0
	for e in gm.revealed_events:
		for c in e.combo:
			if c.rank == combo_card.rank and c.suit == combo_card.suit:
				extra += 1
	if gm.copies_in_play(combo_card.rank, combo_card.suit) != 2 + extra:
		printerr("events: combo cards should count as extra copies in play")
		ok = false
	gm.free()

	# Cycle: a choice of 2 that blocks play until resolved, then discard 2, draw 2.
	gm = _event_gm([ev.CYCLE])
	var p0 := gm.players[0]
	if not gm.has_pending_choice() or gm.pending_choice()["count"] != 2:
		printerr("events: Cycle should ask P0 for 2 cards")
		ok = false
	var three: Array[Card] = [p0.hand[0], p0.hand[1], p0.hand[2]]
	if gm.move_cards_to_new_meld(three).find("Resolve") == -1 \
			or gm.commit_turn().find("Resolve") == -1:
		printerr("events: playing before resolving Cycle should be refused")
		ok = false
	gm.draw_and_end_turn()
	if gm.current_player() != p0:
		printerr("events: drawing must wait for the pending choice")
		ok = false
	if gm.resolve_choice([p0.hand[0]] as Array[Card]) == "":
		printerr("events: Cycle must take exactly 2 cards")
		ok = false
	var gone: Array[Card] = [p0.hand[0], p0.hand[1]]
	if gm.resolve_choice(gone) != "" or p0.hand.size() != 13 \
			or not p0.deck.discards.has(gone[0]) or not p0.deck.discards.has(gone[1]) \
			or gm.has_pending_choice() or gm.cards_played_this_turn() != 0:
		printerr("events: Cycle should discard 2, draw 2 and clear the choice")
		ok = false
	gm.draw_and_end_turn()
	var p1 := gm.players[1]
	if not gm.has_pending_choice() or GreedyAI.resolve_event_choice(gm).size() != 2 \
			or p1.hand.size() != 13 or p1.deck.discards.size() != 2:
		printerr("events: P1 should owe and resolve Cycle on its turn of the round")
		ok = false
	gm.draw_and_end_turn()
	if gm.has_pending_choice():
		printerr("events: Cycle's choice belongs to its reveal round only")
		ok = false
	gm.free()

	# Gift: 2 cards from P0 to P1, then 2 back from P1 on its turn.
	gm = _event_gm([ev.GIFT])
	p0 = gm.players[0]
	p1 = gm.players[1]
	var gift: Array[Card] = [p0.hand[3], p0.hand[4]]
	if gm.resolve_choice(gift) != "" or p0.hand.size() != 11 or p1.hand.size() != 15 \
			or not p1.hand.has(gift[0]):
		printerr("events: Gift should move 2 cards from P0 to P1")
		ok = false
	gm.draw_and_end_turn()
	GreedyAI.resolve_event_choice(gm)
	if p1.hand.size() != 13 or p0.hand.size() != 14:
		printerr("events: P1 should gift 2 back on its turn (P0 %d, P1 %d)"
			% [p0.hand.size(), p1.hand.size()])
		ok = false
	gm.free()

	# Surge: +3 energy on every player's turn of the reveal round only.
	gm = _event_gm([ev.SURGE])
	var surge := [gm.players[0].max_energy]
	gm.draw_and_end_turn()
	surge.append(gm.players[1].max_energy)
	gm.draw_and_end_turn()
	surge.append(gm.players[0].max_energy)
	if surge != [6, 6, 4]:
		printerr("events: Surge energy should read [6, 6, 4], got %s" % str(surge))
		ok = false
	gm.free()

	# Overcharge: on reveal, +2 max energy for good, shown ahead for P1 too.
	gm = _event_gm([ev.OVERCHARGE])
	if gm.players[0].max_energy != 5 or gm.upcoming_energy(gm.players[1]) != 5:
		printerr("events: Overcharge should make the first turn 5 for everyone")
		ok = false
	gm.draw_and_end_turn()
	if gm.players[1].max_energy != 5:
		printerr("events: Overcharge should reach P1 on its turn of the round")
		ok = false
	gm.draw_and_end_turn()
	if gm.players[0].max_energy != 6 or gm.upcoming_energy(gm.players[1]) != 6:
		printerr("events: Overcharge's +2 should last (P0's second turn 6, got %d)"
			% gm.players[0].max_energy)
		ok = false
	gm.free()

	# Extra Draw: one more card per draw.
	gm = _event_gm([ev.EXTRA_DRAW])
	gm.draw_and_end_turn()
	if gm.draw_count() != 2 or gm.players[0].hand.size() != 15:
		printerr("events: Extra Draw should draw 2 instead of 1")
		ok = false
	gm.free()

	# Attrition: a random card discarded at the start of every turn.
	gm = _event_gm([ev.ATTRITION])
	if gm.players[0].hand.size() != 12 or gm.players[0].deck.discards.size() != 1:
		printerr("events: Attrition should discard 1 at the start of P0's turn")
		ok = false
	gm.draw_and_end_turn()
	if gm.players[1].hand.size() != 12:
		printerr("events: Attrition should hit P1's turn too")
		ok = false
	gm.free()

	# Coin Rush: each card played this round gives a coin; next round, none.
	gm = _event_gm([ev.COIN_RUSH])
	var run: Array[Card] = [_card(5, "hearts"), _card(6, "hearts"), _card(7, "hearts")]
	_known_hand(gm, run)
	gm.move_cards_to_new_meld(run)
	if gm.commit_turn() != "" or gm.players[0].coins != 3:
		printerr("events: Coin Rush should pay 3 coins for 3 cards, got %d"
			% gm.players[0].coins)
		ok = false
	gm.draw_and_end_turn()
	var more: Array[Card] = [_card(9, "spades"), _card(9, "clubs"), _card(9, "diamonds")]
	_known_hand(gm, more)
	gm.move_cards_to_new_meld(more)
	gm.commit_turn()
	if gm.players[0].coins != 3:
		printerr("events: Coin Rush pays only in its reveal round")
		ok = false
	gm.free()

	# Open Decks: every deck's top is public.
	gm = _event_gm([ev.OPEN_DECKS])
	var plain := _event_gm([])
	if not gm.top_is_public(gm.players[1].deck.peek()) \
			or plain.top_is_public(plain.players[1].deck.peek()):
		printerr("events: Open Decks should make plain deck tops public")
		ok = false
	gm.free()
	plain.free()

	# An early reveal applies to the current player straight away.
	gm = GameManager.new()
	gm.start_energy = 3
	gm.event_deck = [MatchEvent.new(ev.SURGE)] as Array[MatchEvent]
	gm.event_rounds = [5]
	gm.setup(["P0", "P1"], 13, 3)
	if not gm.revealed_events.is_empty() or not gm.reveal_next_event() \
			or gm.players[0].max_energy != 6 or gm.board.melds.size() != 1:
		printerr("events: an early Surge should give the current player 6 energy")
		ok = false
	gm.free()
	if ok:
		print("events test OK")
	return ok

## A 1v1 energy game with three random events (seeded), driven move by move:
## pending choices resolved by the AI, the energy ceiling never exceeded, card
## conservation across hands, decks, discards and the table, and a finish.
func _play_event_game(seed_value: int) -> bool:
	var gm := GameManager.new()
	gm.start_energy = 3
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	gm.event_deck = MatchEvent.draw(3, rng)
	gm.setup(["P0", "P1"], 13, seed_value, true)
	gm.draw_per_turn = 2
	gm.deal_starting_melds()
	var titles := PackedStringArray()
	for e in gm.revealed_events + gm.event_deck:
		titles.append(e.title)
	# Each reveal adds its 3-card combo to the game.
	var base_cards := _cards_in_game(gm) - 3 * gm.revealed_events.size()
	var turns := 0
	var profile := AIProfile.new(1.0, 0.0, 1.0, seed_value)
	while not gm.is_game_over and turns < MAX_TURNS:
		GreedyAI.resolve_event_choice(gm)
		while true:
			var move := GreedyAI.plan_move(gm, profile)
			if move.is_empty():
				break
			GreedyAI.apply_move(gm, move, profile)
			if gm.energy_spent() > gm.current_player().max_energy:
				printerr("event game %d: overspent energy" % seed_value)
				return false
		if gm.cards_played_this_turn() > 0:
			var err := gm.commit_turn()
			if err != "":
				printerr("event game %d: illegal turn: %s" % [seed_value, err])
				return false
		else:
			gm.draw_and_end_turn()
		turns += 1
		if not gm.board.all_valid() \
				or _cards_in_game(gm) != base_cards + 3 * gm.revealed_events.size():
			printerr("event game %d: invalid table or card count after turn %d"
				% [seed_value, turns])
			return false
	if not gm.is_game_over:
		printerr("event game %d: did not finish" % seed_value)
		return false
	print("event game %d (%s): finished in %d turns" % [seed_value, ", ".join(titles), turns])
	gm.free()
	return true
