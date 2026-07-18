class_name GreedyAI
extends RefCounted

## Baseline opponent AI. With no profile it plays at full strength and quick
## style, greedy and deterministic given the same game state, so seeded games
## replay exactly. Pass an AIProfile to tune it: strength (weak → strong)
## decides how much of the move space it sees and how often it blunders,
## style (quick → conservative) decides how eagerly it commits cards.
##
## Moves are produced one at a time via plan_move() so the UI can show each
## play as it happens; take_turn() drives a whole turn at once for headless
## play and tests. In priority order the AI will:
##  1. lay down any complete meld it holds (largest first; jokers fill in
##     when no natural meld exists),
##  2. lay off single hand cards onto existing table melds,
##  3. lay off pairs of hand cards onto one meld (strong AI only — plays the
##     single-card scan can't see, like both ends of a run at once),
##  4. rearrange the table: borrow one card from a meld (only when the meld
##     left behind is still valid) to complete a new meld with 2+ hand cards
##     (not for weak AI).
## Steps 2-4 respect the opening rule: until the AI has laid down a valid
## meld purely from its own hand, it will not touch other melds on the table.
## Every move also respects the play cap (GameManager.max_plays_per_turn):
## moves that would play more hand cards than the turn has left are skipped.
##
## Style hooks: a conservative AI sits on its opening meld until the meld is
## big enough (or the game forces its hand) and won't lay off cards that
## still look useful with the rest of its hand (pairs, near-runs, jokers).
## An oblivious AI rolls AIProfile.misses_move() before every table-reading
## play (lay-offs and rearrangements, not laying a group from hand) and may
## simply overlook it, cutting its streak short for the turn.
##
## Slime awareness: a card slimed into a cluster with its neighbours can't be
## borrowed on its own (lifting it drags the whole cluster), so the AI's
## rearrangement search skips such cards — it plans only moves it can actually
## make on a slimed table.
##
## Joker smarts: a capable AI (AIProfile.picks_safe_joker_reps) points every
## joker it plays at the safest card it can stand for — the choice with the
## fewest copies still unseen — so opponents rarely hold the exact card
## needed to swap the joker away from it.

# Smart-brain (top skill tier) scoring weights; see the "Smart brain" section
# below for how each is used.
const W_PROGRESS := 10.0     # per own hand card the move commits
const GO_OUT_BONUS := 100.0  # emptying the hand this move
const JOKER_STEAL_BONUS := 30.0  # pulling a joker off another meld into ours
const W_FEED := 2.0          # per unseen copy an open end hands to opponents
const W_BLOCK := 6.0         # holding a card still useful in hand beats dumping it

static func take_turn(gm: GameManager, profile: AIProfile = null,
		enemy: Enemy = null) -> void:
	while true:
		var move := plan_move(gm, profile, enemy)
		if move.is_empty():
			break
		apply_move(gm, move, profile)
	if gm.cards_played_this_turn() > 0:
		var err := gm.commit_turn()
		if err != "":
			# Should be unreachable: every planned move leaves the table valid.
			# Fail safe by drawing rather than wedging the game.
			push_warning("GreedyAI staged an illegal turn (%s); drawing instead." % err)
			gm.draw_and_end_turn()
		return
	# No card left the hand. If a designed enemy reworked the table (the slime
	# herding her slime together, say), draw_and_end_turn keeps that valid
	# rearrangement; with nothing staged it is just a plain draw.
	gm.draw_and_end_turn()

## Plan the next single move for the current player. Returns {} when no move
## exists (or the AI chooses not to see/make one), otherwise a Dictionary with:
##   cards: Array[Card]   every card that moves (from hand and/or table)
##   dest:  CardSet|null  existing meld to extend, or null for a new group
##   text:  String        human-readable description ("<name> " + text)
## Ordinary play comes first; only once the AI is out of ordinary moves does a
## designed enemy get to act on its strategy. A strategy move is a table-only
## rearrangement, so it works whether or not the AI has played a card this turn:
## if it never lays one from hand, take_turn draws and GameManager keeps the
## rearrangement on the felt (see draw_and_end_turn) rather than rolling it back.
static func plan_move(gm: GameManager, profile: AIProfile = null,
		enemy: Enemy = null) -> Dictionary:
	var move := _plan_normal_move(gm, profile)
	if not move.is_empty():
		return move
	if enemy != null and gm.current_player_is_open():
		return enemy.plan_strategy_move(gm)
	return {}

## The AI's ordinary move search (complete melds, lay-offs, rearrangements),
## independent of any enemy strategy. See plan_move for the return shape.
static func _plan_normal_move(gm: GameManager, profile: AIProfile = null) -> Dictionary:
	if profile != null and profile.uses_smart_brain():
		return _plan_smart_move(gm, profile)
	# Cards still playable under the play cap this turn (-1 = unlimited).
	# Every planned move stays within it, or staging would reject the move.
	var budget := -1
	if gm.max_plays_per_turn > 0:
		budget = gm.max_plays_per_turn - gm.cards_played_this_turn()
		if budget <= 0:
			return {}
	var hand := gm.current_player().hand
	# 1. Complete meld straight from hand. An oblivious AI never fumbles this —
	# the blunder roll only covers the table-reading plays below.
	var meld := _find_meld(hand)
	if not meld.is_empty() and (budget < 0 or meld.size() <= budget) \
			and _will_lay_meld(gm, meld, profile):
		return {"cards": meld, "dest": null,
			"text": "lays down %s" % _cards_text(meld)}
	# Not yet opened (no valid own meld on the table): the rules forbid
	# touching other melds, so there is nothing more to plan.
	if not gm.current_player_is_open():
		return {}
	# Every play from here reads the table; an oblivious AI may overlook it,
	# cutting its streak short (see AIProfile.misses_move).
	if profile != null and profile.misses_move():
		return {}
	var hold_keys := profile != null and profile.holds_key_cards()
	# 2. Single-card lay-off onto an existing meld.
	for c in hand:
		if hold_keys and _seems_important(c, hand):
			continue
		for m in gm.board.melds:
			var candidate: Array[Card] = m.cards.duplicate()
			candidate.append(c)
			if Rules.is_valid_meld(candidate):
				var single: Array[Card] = [c]
				return {"cards": single, "dest": m,
					"text": "adds %s to %s" % [c.label(), _cards_text(m.cards)]}
	# 3. Two-card lay-off (strong AI): both cards land on the same meld.
	if (profile == null or profile.sees_pair_layoffs()) and (budget < 0 or budget >= 2):
		for i in hand.size():
			for j in range(i + 1, hand.size()):
				var a := hand[i]
				var b := hand[j]
				if hold_keys and _pair_seems_important(a, b, hand):
					continue
				for m in gm.board.melds:
					var candidate: Array[Card] = m.cards.duplicate()
					candidate.append(a)
					candidate.append(b)
					if Rules.is_valid_meld(candidate):
						var pair: Array[Card] = [a, b]
						return {"cards": pair, "dest": m,
							"text": "adds %s to %s" % [_cards_text(pair), _cards_text(m.cards)]}
	# 4. Rearrange the table: borrow one card from a meld to finish a new meld
	# together with hand cards. Only cards whose removal leaves a valid meld
	# behind are candidates.
	if profile == null or profile.can_rearrange():
		for m in gm.board.melds:
			for t in m.cards:
				if _borrow_drags_cluster(gm, m, t):
					continue  # lifting it alone is impossible: it drags its cluster
				var rest: Array[Card] = m.cards.duplicate()
				rest.erase(t)
				if not Rules.is_valid_meld(rest):
					continue
				var pool: Array[Card] = hand.duplicate()
				pool.append(t)
				var combo := _find_meld(pool)
				if combo.is_empty():
					continue
				if budget >= 0 and combo.size() - 1 > budget:
					continue
				# Step 1 found no hand-only meld, so combo necessarily uses t and
				# therefore plays at least two hand cards.
				return {"cards": combo, "dest": null,
					"text": "takes %s from the table to build %s" % [t.label(), _cards_text(combo)]}
	return {}

# --- Smart brain (top skill tier) ------------------------------------------
# Below the smart-brain threshold the AI grabs the first legal move it finds
# (plan_move above). At the top it instead enumerates every legal move for the
# turn and plays the highest-scoring one, using the same deck-count math that
# picks safe joker stand-ins to reason about what opponents can do next.
# Its scoring weights (W_PROGRESS etc.) live at the top of the file.

## Enumerate every legal move for the current player, score each, and return
## the best (or {} to hold and draw when nothing scores positive). Mirrors
## plan_move's move families and rules (opening gate, play cap) but compares
## candidates instead of taking the first.
static func _plan_smart_move(gm: GameManager, profile: AIProfile) -> Dictionary:
	var budget := -1
	if gm.max_plays_per_turn > 0:
		budget = gm.max_plays_per_turn - gm.cards_played_this_turn()
		if budget <= 0:
			return {}
	var hand := gm.current_player().hand
	# The blunder roll covers only the table-reading plays (steps 2-5 below); an
	# oblivious AI still lays a group straight from hand every time. On a miss it
	# considers nothing but that hand meld this move, cutting its streak short.
	var oblivious := profile != null and profile.misses_move()
	# Race mode: stop denying/blocking and simply push to empty the hand. Two
	# triggers — the endgame is close, or (accounting for how many cards the play
	# cap still lets it play) the whole hand can actually go out this turn. When
	# a finish is in reach the AI commits to it instead of sandbagging.
	var race := _under_pressure_smart(gm) or _can_go_out_this_turn(gm, hand, budget)
	var candidates: Array[Dictionary] = []
	# 1. Complete meld straight from hand. Conservative AIs sit on a small
	# opening meld — unless a finish is in reach, in which case they lay it.
	var meld := _find_meld(hand)
	if not meld.is_empty() and (budget < 0 or meld.size() <= budget) \
			and (race or _will_lay_meld(gm, meld, profile)):
		candidates.append({"cards": meld, "dest": null,
			"text": "lays down %s" % _cards_text(meld)})
	if gm.current_player_is_open() and not oblivious:
		# 2. Single-card lay-offs.
		for c in hand:
			for m in gm.board.melds:
				var cand: Array[Card] = m.cards.duplicate()
				cand.append(c)
				if Rules.is_valid_meld(cand):
					var single: Array[Card] = [c]
					candidates.append({"cards": single, "dest": m,
						"text": "adds %s to %s" % [c.label(), _cards_text(m.cards)]})
		# 3. Two-card lay-offs onto one meld.
		if budget < 0 or budget >= 2:
			for i in hand.size():
				for j in range(i + 1, hand.size()):
					var a := hand[i]
					var b := hand[j]
					for m in gm.board.melds:
						var cand: Array[Card] = m.cards.duplicate()
						cand.append(a)
						cand.append(b)
						if Rules.is_valid_meld(cand):
							var pair: Array[Card] = [a, b]
							candidates.append({"cards": pair, "dest": m,
								"text": "adds %s to %s" % [_cards_text(pair), _cards_text(m.cards)]})
		# 4. Rearrange: borrow one card (a joker counts as a steal) to finish a
		# new meld together with hand cards.
		for m in gm.board.melds:
			for t in m.cards:
				if _borrow_drags_cluster(gm, m, t):
					continue  # slimed: it can't be lifted alone, it drags its cluster
				if not _leftover_valid(m, [t]):
					continue
				var pool: Array[Card] = hand.duplicate()
				pool.append(t)
				var combo := _find_meld(pool)
				if combo.is_empty() or not combo.has(t):
					continue
				if budget >= 0 and combo.size() - 1 > budget:
					continue
				candidates.append({"cards": combo, "dest": null, "borrowed": [t],
					"text": "takes %s from the table to build %s" % [t.label(), _cards_text(combo)]})
		# 5. Deeper manipulation: borrow TWO table cards at once — from one meld
		# or across two — to reach a meld a single borrow can't. Each source meld
		# must stay valid once its card(s) leave, and the built meld must use both
		# borrowed cards (a joker among them still counts as a steal).
		if budget < 0 or budget >= 1:
			var table: Array = []  # [Card, CardSet] for every card on the table
			for m in gm.board.melds:
				for c in m.cards:
					table.append([c, m])
			for i in table.size():
				for j in range(i + 1, table.size()):
					var t1: Card = table[i][0]
					var m1: CardSet = table[i][1]
					var t2: Card = table[j][0]
					var m2: CardSet = table[j][1]
					if _borrow_drags_cluster(gm, m1, t1) or _borrow_drags_cluster(gm, m2, t2):
						continue  # slimed cards can't be lifted alone, they drag a cluster
					if m1 == m2:
						if not _leftover_valid(m1, [t1, t2]):
							continue
					elif not _leftover_valid(m1, [t1]) or not _leftover_valid(m2, [t2]):
						continue
					var pool: Array[Card] = hand.duplicate()
					pool.append(t1)
					pool.append(t2)
					var combo := _find_meld(pool)
					if combo.is_empty() or not combo.has(t1) or not combo.has(t2):
						continue
					if budget >= 0 and combo.size() - 2 > budget:
						continue
					candidates.append({"cards": combo, "dest": null, "borrowed": [t1, t2],
						"text": "reworks the table, taking %s and %s to build %s"
							% [t1.label(), t2.label(), _cards_text(combo)]})
	var best: Dictionary = {}
	var best_score := 0.0  # hold and draw rather than play a net-negative move
	for cand in candidates:
		var score := _score_move(gm, cand, hand, race)
		if score > best_score:
			best_score = score
			best = cand
	return best

## Value of a candidate move. Own progress dominates (and going out trumps
## everything); when NOT racing (see _plan_smart_move) the AI also rewards
## stealing jokers, penalizes handing opponents an open end, and prefers to keep
## cards still useful in hand rather than dump them. In race mode it drops all
## of that and simply maximizes cards played toward the finish.
static func _score_move(gm: GameManager, move: Dictionary, hand: Array[Card],
		race: bool) -> float:
	var cards: Array[Card] = move["cards"]
	var dest: CardSet = move["dest"]
	var borrowed: Array = move.get("borrowed", [])
	var from_hand := cards.size() - borrowed.size()
	var score := from_hand * W_PROGRESS
	if hand.size() - from_hand == 0:
		score += GO_OUT_BONUS
	for b: Card in borrowed:
		if b.is_joker:
			score += JOKER_STEAL_BONUS
	if race:
		return score
	# The meld this move leaves on the table, whose open ends opponents inherit.
	var result: Array[Card] = cards.duplicate()
	if dest != null:
		result = dest.cards + cards
	score -= W_FEED * _open_end_exposure(gm, result)
	# Blocking: dumping a lone/paired card still worth keeping (a joker, or one
	# that pairs toward a meld the deck can still complete) is worth less than
	# holding it for a bigger play. Cards whose completions are all dead cost
	# nothing to shed, so this never sandbags the AI onto a hopeless hold.
	if dest != null:
		var rest: Array[Card] = hand.duplicate()
		for c in cards:
			rest.erase(c)
		for c in cards:
			if _worth_holding(gm, c, rest):
				score -= W_BLOCK
	return score

## Copies of the cards that would extend this meld's open ends and are still
## unseen — i.e. what an opponent could hold to lay off onto it next turn. A
## set counts its one missing suit; a run counts the ranks just past each end.
## Uses natural/locked-joker identities only, so it is an estimate for tie-
## breaking, not an exact reading of a joker-filled meld.
static func _open_end_exposure(gm: GameManager, cards: Array[Card]) -> int:
	if Rules.is_valid_set(cards):
		if cards.size() >= Rules.MAX_SET_SIZE:
			return 0
		var rank := _meld_fixed_rank(cards)
		if rank <= 0:
			return 0
		var present := {}
		for c in cards:
			var s := _fixed_suit(c)
			if s != "":
				present[s] = true
		var worst := 0
		for s in Deck.SUITS:
			if not present.has(s):
				worst = maxi(worst, _unseen_copies(gm, rank, s))
		return worst
	if not Rules.is_valid_run(cards):
		return 0
	var suit := ""
	var lo := 99
	var hi := -99
	for c in cards:
		var s := _fixed_suit(c)
		if s == "":
			continue  # free joker: its slot shifts the ends, skip for the estimate
		suit = s
		var r := _fixed_rank(c)
		lo = mini(lo, r)
		hi = maxi(hi, r)
	if suit == "" or lo > hi:
		return 0
	var exposure := 0
	if lo - 1 >= 1:
		exposure += _unseen_copies(gm, lo - 1, suit)
	if hi + 1 <= 13:
		exposure += _unseen_copies(gm, hi + 1, suit)
	return exposure

## Natural rank of a card, or the rank a locked joker stands for (0 for a free
## joker, which has no fixed identity yet).
static func _fixed_rank(c: Card) -> int:
	if not c.is_joker:
		return c.rank
	return c.joker_lock_rank  # 0 when the joker is still a free wildcard

static func _fixed_suit(c: Card) -> String:
	if not c.is_joker:
		return c.suit
	return c.joker_lock_suit  # "" when the joker is still a free wildcard

## Fixed rank shared by a set's fixed cards (the rank a lone extra card must
## match); 0 when the set has no fixed card.
static func _meld_fixed_rank(cards: Array[Card]) -> int:
	for c in cards:
		var r := _fixed_rank(c)
		if r > 0:
			return r
	return 0

## Whether borrowing this card on its own would drag extra cards along: it is
## slimed into a cluster with its neighbours and the current player is bound by
## the slime (a player that ignores_sticky — the Cute Slime herself — lifts it
## freely). The smart brain understands the slime by simply leaving such cards
## where they are, planning only moves it can actually make.
static func _borrow_drags_cluster(gm: GameManager, meld: CardSet, card: Card) -> bool:
	if gm.current_player().ignores_sticky:
		return false
	return meld.sticky_cluster(card).size() > 1

## Whether a meld stays legal after `removed` cards leave it: either nothing is
## left (the whole meld was consumed) or the remainder is still a valid meld.
## Guards every table rearrangement so the committed table never goes invalid.
static func _leftover_valid(meld: CardSet, removed: Array[Card]) -> bool:
	var rest: Array[Card] = meld.cards.duplicate()
	for c in removed:
		rest.erase(c)
	return rest.is_empty() or Rules.is_valid_meld(rest)

## Whether keeping this card in hand is still worth more than playing it now: a
## joker, or a card that pairs toward a meld the deck can still complete (a set
## whose third suit is still unseen, or a run whose next rank is still unseen).
## A pair whose only completions are already all on the table or in hand is a
## dead end — not worth holding — so the AI stops hoarding and goes out.
static func _worth_holding(gm: GameManager, c: Card, rest: Array[Card]) -> bool:
	if c.is_joker:
		return true
	for o in rest:
		if o == c or o.is_joker:
			continue
		# Toward a set: same rank, another suit — needs a still-unseen third suit.
		if o.rank == c.rank and o.suit != c.suit:
			for s in Deck.SUITS:
				if s != c.suit and s != o.suit and _unseen_copies(gm, c.rank, s) > 0:
					return true
		# Toward a run: same suit, adjacent rank — needs a still-unseen end card.
		if o.suit == c.suit and absi(o.rank - c.rank) == 1:
			var lo := mini(c.rank, o.rank)
			var hi := maxi(c.rank, o.rank)
			if lo - 1 >= 1 and _unseen_copies(gm, lo - 1, c.suit) > 0:
				return true
			if hi + 1 <= 13 and _unseen_copies(gm, hi + 1, c.suit) > 0:
				return true
	return false

## Can the current player empty its whole hand THIS turn, given how many cards
## the play cap still lets it play (budget, -1 = unlimited)? A quick, optimistic
## greedy estimate: the play cap alone rules it out when the hand is bigger than
## the budget; otherwise pull complete melds out of the hand and require every
## leftover card to have a lay-off spot on the table. False negatives only cost
## the AI an early race; false positives just mean it pushes and may draw with a
## card or two left — never an illegal or wasted-cap play.
static func _can_go_out_this_turn(gm: GameManager, hand: Array[Card], budget: int) -> bool:
	if hand.is_empty():
		return false
	if budget >= 0 and hand.size() > budget:
		return false  # the play cap alone means the hand can't all come down now
	var remaining: Array[Card] = hand.duplicate()
	# Repeatedly take the largest meld the hand can form (the opener, then more).
	while true:
		var m := _find_meld(remaining)
		if m.is_empty():
			break
		for c in m:
			remaining.erase(c)
		if remaining.is_empty():
			return true
	# Whatever is left must each lay off onto some existing table meld — only
	# possible once open, which a hand meld above (or a prior turn) provides.
	if remaining.size() == hand.size() and not gm.current_player_is_open():
		return false  # no opener and not yet open: can't touch the table
	for c in remaining:
		var laid := false
		for meld in gm.board.melds:
			var cand: Array[Card] = meld.cards.duplicate()
			cand.append(c)
			if Rules.is_valid_meld(cand):
				laid = true
				break
		if not laid:
			return false
	return true

## The endgame is close enough that a smart AI stops sandbagging and denying and
## races to go out. Notices earlier than the baseline _under_pressure.
static func _under_pressure_smart(gm: GameManager) -> bool:
	if gm.deck.size() <= gm.players.size() * 3:
		return true
	for p in gm.players:
		if p != gm.current_player() and p.hand.size() <= 5:
			return true
	return false

## Apply a move produced by plan_move() to the (staged) game state. A capable
## profile also points any jokers in the touched meld at safe stand-ins.
static func apply_move(gm: GameManager, move: Dictionary, profile: AIProfile = null) -> void:
	var cards: Array[Card] = move["cards"]
	var dest: CardSet = move["dest"]
	var err := ""
	if dest == null:
		err = gm.move_cards_to_new_meld(cards)
	else:
		err = gm.add_cards_to_meld(cards, dest)
	if err != "":
		# Should be unreachable: plan_move only proposes legal moves.
		push_warning("GreedyAI staged an illegal move (%s)" % err)
		return
	# A strategy move deliberately arranges the table (e.g. the slime guarding a
	# joker); leave its jokers pointed where the strategy wants them.
	if profile != null and profile.picks_safe_joker_reps() and not move.get("strategy", false):
		# A new meld is appended last by move_cards_to_new_meld.
		_choose_joker_reps(gm, dest if dest != null else gm.board.melds[-1])

## Point every joker in the meld the AI just touched at the safest card it
## can stand for: the alternative with the fewest copies still unseen (not on
## the table and not in this AI's own hand). An opponent can only swap-claim
## a joker by holding the exact card it stands for, so fewer unseen copies
## means less chance anyone ever takes the wildcard.
static func _choose_joker_reps(gm: GameManager, meld: CardSet) -> void:
	var alts := Rules.joker_alternatives(meld.cards)
	if alts.is_empty():
		return
	var scored: Array[Dictionary] = []
	for alt in alts:
		scored.append({"rank": alt["rank"], "suit": alt["suit"],
			"unseen": _unseen_copies(gm, alt["rank"], alt["suit"])})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["unseen"] != b["unseen"]:
			return a["unseen"] < b["unseen"]
		if a["rank"] != b["rank"]:
			return a["rank"] < b["rank"]
		return a["suit"] < b["suit"])
	var i := 0
	for c in meld.cards:
		if c.is_joker and c.joker_lock_rank == 0:
			var alt: Dictionary = scored[mini(i, scored.size() - 1)]
			c.joker_pref_rank = alt["rank"]
			c.joker_pref_suit = alt["suit"]
			i += 1

## Copies of the exact card that could still sit in an opponent's hand or the
## stock: 2 in the double deck, minus those visible on the table and those
## the current player holds.
static func _unseen_copies(gm: GameManager, rank: int, suit: String) -> int:
	var seen := 0
	for m in gm.board.melds:
		for c in m.cards:
			if not c.is_joker and c.rank == rank and c.suit == suit:
				seen += 1
	for c in gm.current_player().hand:
		if not c.is_joker and c.rank == rank and c.suit == suit:
			seen += 1
	return maxi(2 - seen, 0)

## Whether the AI commits to laying this meld right now. Always yes once
## open; a conservative AI holds its opening meld until it is big enough,
## unless the game is about to end from under it.
static func _will_lay_meld(gm: GameManager, meld: Array[Card], profile: AIProfile) -> bool:
	if profile == null or gm.current_player_is_open():
		return true
	if meld.size() >= profile.opening_threshold():
		return true
	return _under_pressure(gm)

## The endgame is close: the stock is nearly dry or someone is nearly out of
## cards. A conservative AI stops sandbagging at this point.
static func _under_pressure(gm: GameManager) -> bool:
	if gm.deck.size() <= gm.players.size() * 2:
		return true
	for p in gm.players:
		if p != gm.current_player() and p.hand.size() <= 4:
			return true
	return false

## A card worth holding on to: a joker, or one that pairs up with another
## hand card (same rank for a future set, or a same-suit neighbor for a
## future run).
static func _seems_important(c: Card, hand: Array[Card]) -> bool:
	if c.is_joker:
		return true
	for o in hand:
		if o == c or o.is_joker:
			continue
		if o.rank == c.rank and o.suit != c.suit:
			return true
		if o.suit == c.suit and absi(o.rank - c.rank) <= 1:
			return true
	return false

## Importance for a pair lay-off is judged against the hand WITHOUT the pair:
## two cards that only back each other up are fine to play together.
static func _pair_seems_important(a: Card, b: Card, hand: Array[Card]) -> bool:
	var rest: Array[Card] = hand.duplicate()
	rest.erase(a)
	rest.erase(b)
	return _seems_important(a, rest) or _seems_important(b, rest)

## Largest complete meld (set or run) that can be formed from the given cards.
## Prefers all-natural melds; falls back to completing one with jokers.
## Returns an empty array if none exists.
static func _find_meld(pool: Array[Card]) -> Array[Card]:
	var naturals: Array[Card] = []
	var jokers: Array[Card] = []
	for c in pool:
		if c.is_joker:
			jokers.append(c)
		else:
			naturals.append(c)
	var best := _find_natural_meld(naturals)
	if best.is_empty() and not jokers.is_empty():
		best = _find_joker_meld(naturals, jokers)
	return best

static func _find_natural_meld(pool: Array[Card]) -> Array[Card]:
	var best: Array[Card] = []
	# Sets: same rank, distinct suits (two decks mean duplicate suits exist).
	var by_rank := {}
	for c in pool:
		if not by_rank.has(c.rank):
			by_rank[c.rank] = {}
		var suits: Dictionary = by_rank[c.rank]
		if not suits.has(c.suit):
			suits[c.suit] = c
	for rank in by_rank:
		var suits: Dictionary = by_rank[rank]
		if suits.size() < Rules.MIN_MELD_SIZE:
			continue
		var meld: Array[Card] = []
		for suit in suits:
			meld.append(suits[suit])
			if meld.size() == Rules.MAX_SET_SIZE:
				break
		if meld.size() > best.size() and Rules.is_valid_meld(meld):
			best = meld
	# Runs: per suit, dedupe ranks, treat the ace as rank 1 and rank 14, then
	# take the longest chain of consecutive ranks.
	var by_suit := {}
	for c in pool:
		if not by_suit.has(c.suit):
			by_suit[c.suit] = {}
		var ranks: Dictionary = by_suit[c.suit]
		if not ranks.has(c.rank):
			ranks[c.rank] = c
		if c.rank == 1 and not ranks.has(14):
			ranks[14] = c
	for suit in by_suit:
		var ranks: Dictionary = by_suit[suit]
		var order := ranks.keys()
		order.sort()
		var chain: Array[Card] = []
		var prev := -99
		for r in order:
			if r != prev + 1:
				if chain.size() > best.size() and Rules.is_valid_meld(chain):
					best = chain.duplicate()
				chain.clear()
			chain.append(ranks[r])
			prev = r
		if chain.size() > best.size() and Rules.is_valid_meld(chain):
			best = chain.duplicate()
	return best

## Fallback when no natural meld exists: complete one with jokers — two
## naturals plus a joker, or one natural plus two jokers. Rules.is_valid_meld
## does the wildcard reasoning.
static func _find_joker_meld(naturals: Array[Card], jokers: Array[Card]) -> Array[Card]:
	for i in naturals.size():
		for j in range(i + 1, naturals.size()):
			var cand: Array[Card] = [naturals[i], naturals[j], jokers[0]]
			if Rules.is_valid_meld(cand):
				return cand
	if jokers.size() >= 2:
		for c in naturals:
			var cand: Array[Card] = [c, jokers[0], jokers[1]]
			if Rules.is_valid_meld(cand):
				return cand
	return []

static func _cards_text(cards: Array[Card]) -> String:
	var parts := PackedStringArray()
	for c in Rules.display_order(cards):
		parts.append(c.label())
	return " ".join(parts)
