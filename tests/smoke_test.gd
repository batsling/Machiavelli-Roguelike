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
	if not _test_slime_setup():
		failures += 1
	if not _test_slime_strategy():
		failures += 1
	if not _test_slime_guards_on_draw():
		failures += 1
	if not _test_glass_setup():
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
	# Slimed tables: the Cute Slime coats hearts and jokers, so the AI must
	# handle sticky clusters (never borrowing a card that drags its cluster) and
	# still finish with a valid table.
	for seed_value in 8:
		if not _play_slime_game(seed_value):
			failures += 1
	# Glass tables: the Sadistic Billionaire turns his whole deck (half the cards
	# in play) to glass, so the smart brain runs its glass counting every turn.
	for seed_value in 8:
		if not _play_glass_game(seed_value):
			failures += 1
	# Glass and slime together on one table (and on the same cards).
	for seed_value in 4:
		if not _play_glass_slime_game(seed_value):
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

## The Cute Slime coats every card in HER OWN deck at combat start — one copy of
## each, since the combined stock holds one copy per player. So every card she
## owns is slimed (all four suits, and her 2 of the 4 jokers), and nothing from
## the player's deck is.
func _test_slime_setup() -> bool:
	var gm := GameManager.new()
	var ok := true
	gm.setup(["You", "The Cute Slime"], 13, 6, true)
	CuteSlime.new().on_combat_start(gm)
	var own := gm.players[1].player_id
	var all_cards: Array[Card] = gm.deck.cards.duplicate()
	for p in gm.players:
		all_cards.append_array(p.hand)
	var slimed_hers := 0     # her own cards that carry slime (should be all of them)
	var her_cards := 0       # every card from her deck
	var stray := 0           # slimed cards from someone else's deck (should be none)
	for c in all_cards:
		if c.deck_owner == own:
			her_cards += 1
			if c.is_sticky():
				slimed_hers += 1
		elif c.is_sticky():
			stray += 1
	if slimed_hers != her_cards:
		printerr("slime setup: expected all %d of her cards slimed, got %d"
			% [her_cards, slimed_hers])
		ok = false
	# One full deck per player: 52 naturals + her half of the jokers.
	var expected := 52 + Deck.JOKER_COUNT / 2
	if her_cards != expected:
		printerr("slime setup: expected %d cards from her deck, got %d"
			% [expected, her_cards])
		ok = false
	if stray != 0:
		printerr("slime setup: %d cards were slimed that shouldn't be (not from her deck)"
			% stray)
		ok = false
	# She marks her own seat immune so she moves slimed cards freely.
	if not gm.players[1].ignores_sticky:
		printerr("slime setup: the slime's seat should ignore sticky")
		ok = false
	gm.free()
	if ok:
		print("slime setup test OK")
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

## keeping every group valid with no leftover cards, and does nothing when no
## legal combine helps.
func _test_slime_strategy() -> bool:
	var gm := GameManager.new()
	var ok := true
	gm.setup(["You", "The Cute Slime"], 13, 6, true)
	gm.current_player().has_opened = true
	# A run whose joker sits (by default high extension) at the 8♥ slot with a
	# plain 7♥ neighbour — exposed.
	var joker := _sticky(_joker())
	var meld_a := CardSet.new()
	meld_a.cards.assign([_card(6, "hearts"), _card(7, "hearts"), joker])
	Rules.assign_jokers(meld_a.cards)
	# A slimed 9♥ parked in a set of nines, free to leave (three nines remain).
	var nine_h := _sticky(_card(9, "hearts"))
	var meld_b := CardSet.new()
	meld_b.cards.assign([nine_h, _card(9, "spades"), _card(9, "clubs"), _card(9, "diamonds")])
	gm.board.melds.append(meld_a)
	gm.board.melds.append(meld_b)
	var slime := CuteSlime.new()
	var move := slime.plan_strategy_move(gm)
	if move.is_empty():
		printerr("slime strategy: expected a guarding move, got none")
		ok = false
	elif not _same(move["cards"], [nine_h]):
		printerr("slime strategy: should relocate the slimed 9♥, moved %s"
			% _labels(move["cards"]))
		ok = false
	elif move["dest"] != meld_a:
		printerr("slime strategy: should ooze the 9♥ onto the joker's group to seal it")
		ok = false
	else:
		# The combine is legal and leaves no unmatched card: the group she oozes
		# onto stays a valid meld, and the one she takes from stays valid.
		var grown: Array[Card] = meld_a.cards.duplicate()
		grown.append(nine_h)
		var rest: Array[Card] = meld_b.cards.duplicate()
		rest.erase(nine_h)
		if not Rules.is_valid_meld(grown):
			printerr("slime strategy: the guarded group should stay a valid meld")
			ok = false
		elif not Rules.is_valid_meld(rest):
			printerr("slime strategy: the source group should stay valid, no orphans")
			ok = false
	# Versatility ranking: joker over the middle ranks 4-8, and those over the
	# edge ranks (aces and faces rate no higher than any other plain card).
	if slime._importance(_joker()) <= slime._importance(_card(6, "hearts")) \
			or slime._importance(_card(6, "hearts")) <= slime._importance(_card(1, "hearts")) \
			or slime._importance(_card(1, "hearts")) != slime._importance(_card(13, "hearts")):
		printerr("slime strategy: importance should rank joker > 4-8 > edge ranks")
		ok = false
	# A lone group offers no second group to bring a bodyguard from: no move.
	if ok:
		var gm2 := GameManager.new()
		gm2.setup(["You", "The Cute Slime"], 13, 6, true)
		gm2.current_player().has_opened = true
		var solo := CardSet.new()
		solo.cards.assign([_card(6, "hearts"), _card(7, "hearts"), _sticky(_joker())])
		gm2.board.melds.append(solo)
		Rules.assign_jokers(solo.cards)
		if not slime.plan_strategy_move(gm2).is_empty():
			printerr("slime strategy: a lone group offers no bodyguard to move")
			ok = false
		gm2.free()
	gm.free()
	if ok:
		print("slime strategy test OK")
	return ok

## The reported bug: with no ordinary play in hand, the slime used to just draw
## and skip her guard. Now a turn that only reworks the table (relocating a
## slimed card to seal it next to another) still happens — she draws AND keeps
## the rearrangement. Here a slimed 8♦ sitting in a set of four 8s can slide
## next to a slimed 9♦ in a diamond run, sealing both; her hand can't play.
func _test_slime_guards_on_draw() -> bool:
	var gm := GameManager.new()
	var ok := true
	gm.setup(["The Cute Slime", "P1"], 13, 12)
	var p := gm.current_player()
	p.has_opened = true
	p.ignores_sticky = true
	# A junk hand: no meld, no lay-off, no borrow against the board below.
	p.hand.assign([_card(2, "spades"), _card(5, "clubs"), _card(7, "spades"),
		_card(13, "hearts")])
	gm._hand_snapshot = p.hand.duplicate()
	# A set of four 8s holding the slimed 8♦ (free to leave — three 8s remain).
	var eight_d := _sticky(_card(8, "diamonds"))
	var set_meld := CardSet.new()
	set_meld.cards.assign([eight_d, _card(8, "spades"), _card(8, "clubs"),
		_card(8, "hearts")])
	# A diamond run holding a slimed 9♦; adding the 8♦ seals the two together.
	var nine_d := _sticky(_card(9, "diamonds"))
	var run_meld := CardSet.new()
	run_meld.cards.assign([nine_d, _card(10, "diamonds"), _card(11, "diamonds")])
	gm.board.melds.append(set_meld)
	gm.board.melds.append(run_meld)
	var slime := CuteSlime.new()
	var stock_before := gm.deck.size()
	GreedyAI.take_turn(gm, null, slime)
	# She reworked the felt: the 8♦ now rides in the run, the set is down to
	# three, and both groups are still valid.
	if not run_meld.cards.has(eight_d):
		printerr("slime guards on draw: the 8♦ should have oozed into the run, run = %s"
			% _labels(run_meld.cards))
		ok = false
	elif set_meld.cards.size() != 3 or set_meld.cards.has(eight_d):
		printerr("slime guards on draw: the set should be down to three 8s, got %s"
			% _labels(set_meld.cards))
		ok = false
	elif not gm.board.all_valid():
		printerr("slime guards on draw: the kept rearrangement left an invalid group")
		ok = false
	# And she still drew (the turn ended in a draw, not a commit) and passed play on.
	elif gm.deck.size() != stock_before - 1:
		printerr("slime guards on draw: she should have drawn one card, stock %d -> %d"
			% [stock_before, gm.deck.size()])
		ok = false
	elif gm.current_player() == p:
		printerr("slime guards on draw: the turn should have ended")
		ok = false
	gm.free()
	if ok:
		print("slime guards on draw test OK")
	return ok

## The Sadistic Billionaire turns every card in HIS OWN deck — all 52 naturals
## and both his jokers — to glass at combat start. The combined stock holds one
## copy of each card per player, so exactly his half (54 of 108) goes glass, only
## his 2 of the 4 jokers, and nothing from the player's deck. Glass is pure
## information, so it stacks with slime on the same card; and the rogue roster
## now offers both designed enemies.
func _test_glass_setup() -> bool:
	var gm := GameManager.new()
	var ok := true
	gm.setup(["You", "The Sadistic Billionaire"], 13, 6, true)
	SadisticBillionaire.new().on_combat_start(gm)
	var own := gm.players[1].player_id
	var all_cards: Array[Card] = gm.deck.cards.duplicate()
	for p in gm.players:
		all_cards.append_array(p.hand)
	var glass := 0
	var glass_jokers := 0
	var total_jokers := 0
	var stray := 0        # glass cards from the wrong (player's) deck
	for c in all_cards:
		if c.is_glass():
			glass += 1
			if c.deck_owner != own:
				stray += 1
		if c.is_joker:
			total_jokers += 1
			if c.is_glass():
				glass_jokers += 1
	# All 52 naturals + 2 jokers of his own deck: 54 of the 108 cards.
	if all_cards.size() != 108 or glass != 54:
		printerr("glass setup: expected 54 of 108 cards glass, got %d of %d"
			% [glass, all_cards.size()])
		ok = false
	if stray != 0:
		printerr("glass setup: %d glass cards came from the player's deck" % stray)
		ok = false
	if glass_jokers != 2 or total_jokers != Deck.JOKER_COUNT:
		printerr("glass setup: expected only his 2 of %d jokers glass, got %d"
			% [Deck.JOKER_COUNT, glass_jokers])
		ok = false
	var both := _glass(_sticky(_card(5, "hearts")))
	if not (both.is_glass() and both.is_sticky()):
		printerr("glass setup: a card should be able to be both glass and slimed")
		ok = false
	if Enemy.roster().size() != 2:
		printerr("glass setup: roster should hold the slime and the billionaire, got %d"
			% Enemy.roster().size())
		ok = false
	gm.free()
	if ok:
		print("glass setup test OK")
	return ok

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
	gm.deck.cards.append(_card(12, "spades"))
	if GreedyAI._glass_top_matches(gm, 12, "spades"):
		printerr("glass counting: a face-down stock top must not be readable")
		ok = false
	gm.deck.cards.append(_glass(_card(11, "clubs")))
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
	gm.deck.cards.append(_glass(_card(6, "hearts")))
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
	gm.deck.cards.append(_glass(_card(4, "hearts")))
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
## pulled from the stock, marks them opened, and conserves every card. On a
## slimed deck the pulled cards keep their slime.
func _test_starting_melds() -> bool:
	var gm := GameManager.new()
	var ok := true
	gm.setup(["P0", "P1", "P2"], 13, 5, true)
	CuteSlime.new().on_combat_start(gm)
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
	var count := gm.deck.size() + gm.board.all_cards().size()
	for p in gm.players:
		count += p.hand.size()
	if count != 108:
		printerr("starting melds: card conservation broken (%d)" % count)
		ok = false
	gm.free()
	if ok:
		print("starting melds test OK")
	return ok

## A full AI-vs-AI game on a slimed table: the Cute Slime's mechanic is planted
## at combat start and both seats play under her profile, so the run exercises
## sticky clusters on the board. Core invariants (valid table, card
## conservation) must hold after every turn, exactly as in a plain game.
func _play_slime_game(seed_value: int) -> bool:
	var gm := GameManager.new()
	gm.setup(["You", "The Cute Slime"], 13, seed_value, true)
	gm.draw_per_turn = 2
	gm.max_plays_per_turn = 13
	var slime := CuteSlime.new()
	slime.on_combat_start(gm)
	var profile := slime.make_profile(seed_value)
	var turns := 0
	while not gm.is_game_over and turns < MAX_TURNS:
		# Only the slime's own turns carry her strategy; the other seat plays a
		# plain game against the slimed table.
		var enemy: Enemy = slime if gm.current_player().is_opponent else null
		GreedyAI.take_turn(gm, profile, enemy)
		turns += 1
		if not gm.board.all_valid():
			printerr("slime game %d: invalid meld on table after turn %d" % [seed_value, turns])
			return false
		var count := gm.deck.size() + gm.board.all_cards().size()
		for p in gm.players:
			count += p.hand.size()
		if count != 108:
			printerr("slime game %d: card conservation broken (%d) after turn %d"
				% [seed_value, count, turns])
			return false
	if not gm.is_game_over:
		printerr("slime game %d: did not finish within %d turns" % [seed_value, MAX_TURNS])
		return false
	print("slime game %d: finished in %d turns" % [seed_value, turns])
	gm.free()
	return true

## A full AI-vs-AI game on a glass table: the Sadistic Billionaire's mechanic
## is planted at combat start and both seats play under his (smart,
## conservative, attentive) profile, so every turn exercises the glass-aware
## brain — obtainable counting, glass feed threats, glass joker stand-ins and
## the public stock top. Core invariants must hold after every turn.
func _play_glass_game(seed_value: int) -> bool:
	var gm := GameManager.new()
	gm.setup(["You", "The Sadistic Billionaire"], 13, seed_value, true)
	gm.draw_per_turn = 2
	gm.max_plays_per_turn = 13
	var billionaire := SadisticBillionaire.new()
	billionaire.on_combat_start(gm)
	var profile := billionaire.make_profile(seed_value)
	var turns := 0
	while not gm.is_game_over and turns < MAX_TURNS:
		GreedyAI.take_turn(gm, profile)
		turns += 1
		if not gm.board.all_valid():
			printerr("glass game %d: invalid meld on table after turn %d" % [seed_value, turns])
			return false
		var count := gm.deck.size() + gm.board.all_cards().size()
		for p in gm.players:
			count += p.hand.size()
		if count != 108:
			printerr("glass game %d: card conservation broken (%d) after turn %d"
				% [seed_value, count, turns])
			return false
	if not gm.is_game_over:
		printerr("glass game %d: did not finish within %d turns" % [seed_value, MAX_TURNS])
		return false
	print("glass game %d: finished in %d turns" % [seed_value, turns])
	gm.free()
	return true

## Glass and slime planted on the same table (so plenty of cards carry both
## effects): glass is pure information and must not disturb sticky movement or
## any invariant. The slime's seat still runs her guard strategy.
func _play_glass_slime_game(seed_value: int) -> bool:
	var gm := GameManager.new()
	gm.setup(["You", "The Cute Slime"], 13, seed_value, true)
	gm.draw_per_turn = 2
	gm.max_plays_per_turn = 13
	var slime := CuteSlime.new()
	slime.on_combat_start(gm)
	SadisticBillionaire.new().on_combat_start(gm)
	var profile := slime.make_profile(seed_value)
	var turns := 0
	while not gm.is_game_over and turns < MAX_TURNS:
		var enemy: Enemy = slime if gm.current_player().is_opponent else null
		GreedyAI.take_turn(gm, profile, enemy)
		turns += 1
		if not gm.board.all_valid():
			printerr("glass+slime game %d: invalid meld on table after turn %d"
				% [seed_value, turns])
			return false
		var count := gm.deck.size() + gm.board.all_cards().size()
		for p in gm.players:
			count += p.hand.size()
		if count != 108:
			printerr("glass+slime game %d: card conservation broken (%d) after turn %d"
				% [seed_value, count, turns])
			return false
	if not gm.is_game_over:
		printerr("glass+slime game %d: did not finish within %d turns"
			% [seed_value, MAX_TURNS])
		return false
	print("glass+slime game %d: finished in %d turns" % [seed_value, turns])
	gm.free()
	return true

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
