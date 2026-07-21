class_name SadisticBillionaire
extends Enemy

## The second designed enemy. He plays at full strength, conservative and fully
## attentive. His passive mechanic is glass; his ultimate is the Riichi.
##
## PASSIVE — glass. At combat start he turns every card in his own deck — all 52
## naturals and both his jokers, wherever the deal put them — to glass (the Clear
## effect). Of the two copies of any card exactly one is see-through, and only
## two of the four jokers (his). A glass card is visible from the back in any
## player's hand and on top of the stock. The information cuts both ways: the
## player reads his glass cards, and the smart AI counts every glass card too.
##
## ULTIMATE — Riichi (from mahjong). Once his meter is full and his hand is
## "tenpai" — one card away from laying his WHOLE HAND down as its own valid melds
## (Tiling.can_partition over his hand alone) — he may declare Riichi. The wait is
## self-contained in his hand, not the table: the winning card completes his own
## melds, so no one rearranging the felt can disturb it. He weighs it first (see
## _should_declare): using his glass vision he counts how many live, winnable
## copies of his waits remain, and he refuses to declare into a dead wait — one
## whose only remaining copies are visibly locked in opponents' hands (the
## Washizu-mahjong reading of his own Clear passive). On declaring, his hand
## freezes and his meter drains. From then on every turn he simply draws one card:
## if it completes his hand he wins by "tsumo"; otherwise he discards it face up
## (out of play until the stock recycles). And if any opponent plays one of his
## wait cards onto the table, he claims it and wins on the spot — his "ron".
##
## STRATEGY — playing for tenpai. To reach that hand he does not just dump cards
## like the baseline AI: he holds his developing melds and partials together and
## only sheds complete combinations and useless floaters, shaping his hand toward
## a good tenpai (avoids_play, consulted by GreedyAI's smart brain). See
## on_opponent_commit,
## wired through GameManager.play_interceptor).
##
## Glass is pure information — it never restricts how a card moves — so a card
## can be both glass and slimed without conflict.

## True once he has declared Riichi: his hand is frozen and he only draws.
var riichi := false
## His seat's player id, cached at combat start so the interceptor can find his
## PlayerState from any GameManager callback.
var my_player_id := -1

func _init() -> void:
	display_name = "The Sadistic Billionaire"
	strength = 1.0     # strongest difficulty (for now every enemy is)
	style = 1.0        # conservative
	attention = 1.0    # attentive

func mechanic_intro() -> String:
	return "[b]%s[/b] turns every card in his own deck to glass (transparent) " \
		% display_name \
		+ "— one copy of each, so only his half is see-through, visible in any " \
		+ "hand and on the stock. He plays for [b]tenpai[/b] — holding his " \
		+ "developing melds together and shedding only complete groups and junk. " \
		+ "His ultimate is [b]Riichi[/b]: with a full " \
		+ "meter and a hand one card from going out, he freezes his hand and only " \
		+ "draws — winning by [i]tsumo[/i] if he draws his card, or claiming it " \
		+ "([i]ron[/i]) the instant an opponent plays it. He won't declare into a " \
		+ "wait his glass vision shows dead in your hand."

## Turn every card from his own deck to glass, and register himself as the play
## interceptor (for the Riichi ron). Deterministic (no RNG), so a seeded game
## glasses the same cards every replay.
func on_combat_start(gm: GameManager) -> void:
	my_player_id = own_deck_id(gm)
	gm.play_interceptor = self
	var own := own_deck_id(gm)
	for c in all_dealt_cards(gm):
		if c.deck_owner == own:
			_glass(c)

func _glass(card: Card) -> void:
	if not card.has_effect(Card.Effect.CLEAR):
		card.effects.append(Card.Effect.CLEAR)

# --- Riichi: turn control -----------------------------------------------------

## He takes over his own turn once he is in Riichi, or the moment he decides to
## declare it. Otherwise GreedyAI plays him normally.
func wants_control(gm: GameManager) -> bool:
	if _my_state(gm) != gm.current_player():
		return false
	if riichi:
		return true
	return _should_declare(gm)

## Drive one Riichi turn: declare if he hasn't yet, then draw one card and either
## win by tsumo, discard it face up, or pass when nothing can be drawn.
func run_controlled_turn(gm: GameManager) -> Dictionary:
	var me := _my_state(gm)
	var lead := ""
	if not riichi:
		riichi = true
		me.declared_riichi = true
		gm.spend_meter()  # the ultimate fires — the meter drains
		lead = "declares [b]Riichi![/b] "
	var card := gm.draw_from_stock()
	if card == null:
		gm.pass_turn()
		return {"text": lead + "can't draw — stock and discards are empty, so he passes"}
	if _can_go_out(gm, card):
		me.hand.append(card)  # the winning tile joins the hand he lays down
		gm.win_now([me])
		return {"text": lead + "draws %s and goes out — [b]tsumo![/b]" % card.label()}
	gm.send_to_discard(me, card)
	gm.advance_after_action()
	return {"text": lead + "draws and discards %s face up" % card.label()}

## Interceptor: right after an opponent commits a hand, if any card they just
## played is one of his wait cards (it completes his frozen hand), he claims it
## and wins — his ron.
func on_opponent_commit(gm: GameManager, committer: PlayerState) -> bool:
	if not riichi:
		return false
	var me := _my_state(gm)
	if me == null or committer == me:
		return false
	for c in gm.cards_placed_this_turn():
		if _can_go_out(gm, c):
			gm.win_now([me])
			return true
	return false

# --- Riichi: shaping the hand toward tenpai -----------------------------------

## The size of hand he shapes toward and keeps — a chunk he could lay down in one
## turn (the play cap), so a completed Riichi hand is one he can actually play out.
func _target_hand(gm: GameManager) -> int:
	return gm.max_plays_per_turn if gm.max_plays_per_turn > 0 else 13

## Hands his whole pre-Riichi turn over to his own shed policy (plan_strategy_move
## below): GreedyAI's smart brain would otherwise dump his hand or, being
## conservative, sit on it — neither of which builds a Riichi tenpai. So he vetoes
## every ordinary play that lays cards from his hand, unless it goes out (a normal
## win is always taken). With the meter off there is no Riichi to build, and
## GreedyAI ignores the veto when racing to finish, so a tight endgame overrides it.
func avoids_play(gm: GameManager, move: Dictionary) -> bool:
	if riichi or gm.meter_max <= 0:
		return false
	# Let him open normally: his shed policy only runs once he has opened (that is
	# when GreedyAI consults plan_strategy_move), so vetoing the opening meld would
	# lock him out of ever playing.
	if not gm.current_player_is_open():
		return false
	var me := _my_state(gm)
	if me == null:
		return false
	var new_hand: Array[Card] = me.hand.duplicate()
	var plays_from_hand := false
	for c: Card in move["cards"]:
		if me.hand.has(c):
			plays_from_hand = true
			new_hand.erase(c)
	if not plays_from_hand:
		return false  # a table-only rearrangement sheds nothing from his hand
	return not new_hand.is_empty()  # veto every hand play except one that goes out

## His shed policy, the heart of playing for tenpai. He keeps a chunk of about a
## hand-cap's worth of cards and only trims the excess: while at or over that size
## he sheds a complete meld (which never breaks the partials he is building his
## wait on) or, failing that, a lone floater whose loss doesn't set his tenpai
## back — each shed also charging his meter. Under his target size he holds and
## draws, growing his structure toward a good tenpai. Returns {} to draw.
func plan_strategy_move(gm: GameManager) -> Dictionary:
	if riichi or gm.meter_max <= 0:
		return {}
	var me := _my_state(gm)
	if me == null or me.hand.size() < _target_hand(gm):
		return {}
	# Stop once this turn's plays would reach the target (also respecting the play
	# cap), so he never loops trying to shed more than a turn allows.
	var budget := _target_hand(gm) - gm.cards_played_this_turn()
	if gm.max_plays_per_turn > 0:
		budget = mini(budget, gm.max_plays_per_turn - gm.cards_played_this_turn())
	if budget <= 0:
		return {}
	# Laying a complete meld from hand needs no open — it IS his opening meld the
	# first time — and never breaks a partial, so it is his preferred shed.
	var meld := GreedyAI._find_meld(me.hand)
	if not meld.is_empty() and meld.size() <= budget:
		return {"cards": meld, "dest": null,
			"text": "sets down %s" % GreedyAI._cards_text(meld)}
	# No complete meld to lay: shed a lone floater onto a table meld (only once he
	# has opened). A floater is a card with no partner in hand — nothing it could
	# grow a set or run with — so parting with it never breaks a wait he is
	# building. A cheap structural read, no solver in this hot path.
	if not gm.current_player_is_open():
		return {}
	for c in me.hand:
		if not _is_floater(c, me.hand):
			continue
		for m in gm.board.melds:
			if not GreedyAI._plain_meld(m):
				continue
			if Rules.is_valid_meld(m.cards + [c]):
				return {"cards": [c], "dest": m, "text": "lays off %s" % c.label()}
	# Well over target with no clean shed (no complete meld, no floater with a
	# home): lay off any card that fits, so his hand can't drown even through a dry
	# stretch — better a broken partial than a bloated hand he can't play out.
	if me.hand.size() >= _target_hand(gm) + 4:
		for c in me.hand:
			for m in gm.board.melds:
				if not GreedyAI._plain_meld(m):
					continue
				if Rules.is_valid_meld(m.cards + [c]):
					return {"cards": [c], "dest": m, "text": "lays off %s" % c.label()}
	return {}

## True when this card has no partner in the hand — no other card it could form
## or extend a group with (same rank, or same suit within two ranks, the ace
## neighbouring both the two and the king). Such a card is dead weight he can
## shed without touching a developing meld. Jokers are never floaters.
func _is_floater(card: Card, hand: Array[Card]) -> bool:
	if card.is_joker:
		return false
	for o in hand:
		if o == card:
			continue
		if o.is_joker:
			return false  # a joker can pair with anything, so keep this card
		if o.rank == card.rank and o.suit != card.suit:
			return false  # a set partner
		if o.suit == card.suit:
			var d := absi(o.rank - card.rank)
			if d <= 2 or d == 11 or d == 12:  # near in rank (or ace-high wrap to K/Q)
				return false  # a run partner
	return true

# --- Riichi: the declaration decision -----------------------------------------

## Winnable-copy floor: below this he treats a wait as not worth declaring; a
## wait with zero winnable copies is always dead (never declared into).
const RIICHI_MIN_WINNABLE := 1

## Whether to declare Riichi right now: his meter is full, he is tenpai (some
## draw makes him go out), he can't simply win outright this turn already, and
## his waits carry enough live, winnable copies (discounting those his glass
## vision shows locked away in opponents' hands) to be worth freezing his hand.
func _should_declare(gm: GameManager) -> bool:
	if gm.meter_max <= 0:
		return false
	var me := _my_state(gm)
	if me == null or gm.projected_meter(me) < gm.meter_max:
		return false
	var pool := _go_out_pool(gm)
	# Cheap tenpai gate: one wildcard away from going out? A single solve, so the
	# 52-card wait enumeration below is skipped on the many turns he is not close.
	if not Tiling.can_partition_with_wild(pool):
		return false
	# If he can already lay everything down this turn, that is a normal win —
	# no need to freeze into a wait.
	if Tiling.can_partition(pool):
		return false
	var waits := Tiling.wait_cards(pool)
	if waits.is_empty():
		return false
	# Any live, winnable wait is worth declaring; only a dead wait (every copy he
	# can see locked in an opponent's hand) is refused — the Washizu rule.
	return _wait_winnable(gm, waits) >= RIICHI_MIN_WINNABLE

## The total number of live, winnable copies across all his waits: for each wait
## card, the copies not already in his hand or on the table, minus the ones his
## glass vision shows held in an opponent's hand (those he can neither draw nor
## expect a smart opponent to feed). Plus the live jokers still out there, since
## any drawn joker completes any wait.
func _wait_winnable(gm: GameManager, waits: Array[Dictionary]) -> int:
	var total := 0
	for w in waits:
		var r: int = w["rank"]
		var s: String = w["suit"]
		var remaining := maxi(2 - _naturals_in_play(gm, r, s), 0)
		var denied := _glass_in_opponent_hands(gm, r, s)
		total += maxi(remaining - denied, 0)
	total += _live_jokers(gm)
	return total

## Copies of the exact natural card sitting in his hand or anywhere on the table
## (the ones that are NOT still out there to be drawn or fed).
func _naturals_in_play(gm: GameManager, rank: int, suit: String) -> int:
	var n := 0
	for c in _my_state(gm).hand:
		if not c.is_joker and c.rank == rank and c.suit == suit:
			n += 1
	for c in gm.board.all_cards():
		if not c.is_joker and c.rank == rank and c.suit == suit:
			n += 1
	return n

## Copies of the exact card an opponent visibly holds (a glass card in their
## hand) — certain knowledge that a copy is locked away, not drawable.
func _glass_in_opponent_hands(gm: GameManager, rank: int, suit: String) -> int:
	var n := 0
	for p in gm.players:
		if p.player_id == my_player_id:
			continue
		for c in p.hand:
			if c.is_glass() and not c.is_joker and c.rank == rank and c.suit == suit:
				n += 1
	return n

## Jokers still liable to reach him: the game's jokers minus the ones he holds,
## the ones locked on the table, and the ones an opponent visibly (glass) holds.
func _live_jokers(gm: GameManager) -> int:
	var total := 0
	var mine := 0
	var on_table := 0
	var denied := 0
	for c in all_dealt_cards(gm):
		if c.is_joker:
			total += 1
	for c in _my_state(gm).hand:
		if c.is_joker:
			mine += 1
	for m in gm.board.melds:
		for c in m.cards:
			if c.is_joker:
				on_table += 1
	for p in gm.players:
		if p.player_id == my_player_id:
			continue
		for c in p.hand:
			if c.is_joker and c.is_glass():
				denied += 1
	return maxi(total - mine - on_table - denied, 0)

# --- Riichi: the go-out test --------------------------------------------------

## The pile he lays down when he goes out: his hand alone. The wait is
## self-contained — the winning card completes his own melds — so the table
## (which anyone may rearrange) can never disturb it.
func _go_out_pool(gm: GameManager) -> Array[Card]:
	return _my_state(gm).hand.duplicate()

## True when his hand (optionally with one more card — a draw or an opponent's
## just-played wait) lays down entirely into its own valid melds — he can go out.
func _can_go_out(gm: GameManager, extra: Card = null) -> bool:
	var pool := _go_out_pool(gm)
	if extra != null:
		pool.append(extra)
	return Tiling.can_partition(pool)

func _my_state(gm: GameManager) -> PlayerState:
	for p in gm.players:
		if p.player_id == my_player_id:
			return p
	return null
