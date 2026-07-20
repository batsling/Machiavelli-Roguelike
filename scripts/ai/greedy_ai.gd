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
##
## Glass awareness: a glass (Clear) card is visible from the back — in any
## player's hand and on top of the stock — so that information is public, not
## a peek. The AI folds it into its deck counting: copies visibly locked in
## opponents' hands are not obtainable (_obtainable_copies), so pairs whose
## completions all sit in glass opponent hands are dead ends it stops holding;
## a lay-off an opponent visibly holds counts as a certain feed
## (_layoff_threat); a joker stand-in an opponent visibly holds the swap card
## for is avoided (_choose_joker_reps); and a glass top of the stock is a
## known upcoming draw worth holding a partner for (_worth_holding).

# Smart-brain (top skill tier) scoring weights; see the "Smart brain" section
# below for how each is used.
const W_PROGRESS := 10.0     # per own hand card the move commits
const GO_OUT_BONUS := 100.0  # emptying the hand this move
const JOKER_STEAL_BONUS := 30.0  # pulling a joker off another meld into ours
const W_FEED := 2.0          # per unseen copy an open end hands to opponents
const W_BLOCK := 6.0         # holding a card still useful in hand beats dumping it

# Deep-rearrangement planner (the planning dial) safety caps. The search is
# bounded by the profile's plan_budget (board movements it may chain), and on
# top of that by these so even an "unlimited" expert planner stays fast: it
# never recurses deeper than MAX_PLAN_DEPTH relocations or explores more than
# MAX_PLAN_NODES repair states per candidate target.
const MAX_PLAN_DEPTH := 12
const MAX_PLAN_NODES := 600

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
	# 5. Deep rearrangement (the planning dial): chain board relocations to open
	# up a hand play the borrow families above can't reach. Only a profiled AI
	# with a planning budget attempts it; the no-profile default keeps its old,
	# fully reproducible behavior.
	if profile != null and profile.can_rearrange() and gm.current_player_is_open():
		var deep := _plan_rearrange_move(gm, profile)
		if not deep.is_empty():
			return deep
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
		# 6. Deep rearrangement (the planning dial): chain board relocations to
		# lay down a hand play no single/double borrow can reach, up to the
		# profile's planning budget.
		var deep := _plan_rearrange_move(gm, profile)
		if not deep.is_empty():
			candidates.append(deep)
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
	# A deep-rearrangement composite is valued purely on the hand progress it
	# lets through (and going out): it already pays its way in board movements,
	# so it isn't taxed for open ends the way a plain lay-off is.
	if move.has("rearrange"):
		var played: Array = move["hand_played"]
		var deep_score := played.size() * W_PROGRESS
		if hand.size() - played.size() == 0:
			deep_score += GO_OUT_BONUS
		return deep_score
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

# --- Deep rearrangement planner (the planning dial) ------------------------
# Beyond the borrow-1/borrow-2 families, an AI with a planning budget can chain
# board-card relocations to open up a hand play: pull the table cards a new meld
# needs into it alongside its hand cards, then repair every meld left broken by
# relocating the offending cards to a valid home — recursively, spending at most
# `budget` board movements in total. The result is one composite move (a
# "rearrange" entry) that apply_move realizes as a single staged turn. The
# short-sighted tier gets budget 1, the middle tier PLAN_BUDGET_MID, the expert
# planner effectively unlimited (bounded only by MAX_PLAN_DEPTH/MAX_PLAN_NODES).

## The best deep-rearrangement play within the profile's planning budget, or {}
## for none. Enumerates target melds (a set or run built from >=1 hand card plus
## table cards it must pull free), and for each searches for a way to keep every
## donor meld valid within the leftover budget. Returns the candidate that plays
## the most hand cards (fewest board movements breaking ties). Every candidate
## pulls at least one table card, so it is a genuine rearrangement, never a plain
## hand meld the ordinary search already covers.
static func _plan_rearrange_move(gm: GameManager, profile: AIProfile) -> Dictionary:
	if profile == null:
		return {}
	var budget := mini(profile.plan_budget(), MAX_PLAN_DEPTH)
	if budget < 1:
		return {}
	var play_cap := -1
	if gm.max_plays_per_turn > 0:
		play_cap = gm.max_plays_per_turn - gm.cards_played_this_turn()
		if play_cap <= 0:
			return {}
	var hand := gm.current_player().hand
	var immovable := _immovable_cards(gm)
	var best: Dictionary = {}
	for target: Array in _rearrange_targets(gm, hand, immovable):
		var t_cards: Array[Card] = target
		var played := _hand_subset(hand, t_cards)
		var pulls: Array[Card] = []
		for c in t_cards:
			if not hand.has(c):
				pulls.append(c)
		if played.is_empty() or pulls.is_empty():
			continue  # need a hand card and a genuine table pull
		if play_cap >= 0 and played.size() > play_cap:
			continue
		if pulls.size() > budget:
			continue
		# Board model minus the pulled cards; the target itself is valid, so only
		# the donor melds it thinned might need repairing. Shape (picture)
		# groups stay out of the model entirely: they are valid by shape rules
		# (a line-rule repair would read them as broken), their cards are
		# immovable, and _apply_rearrange only ever moves modelled cards.
		var melds: Array = []
		for m in gm.board.melds:
			if m.is_shape():
				continue
			var arr: Array[Card] = m.cards.duplicate()
			for p in pulls:
				arr.erase(p)
			if not arr.is_empty():
				melds.append(arr)
		var nodes := [0]
		var repairs: Variant = _repair_board(melds, budget - pulls.size(), immovable, nodes)
		if repairs == null:
			continue
		var final_melds: Array = []
		for arr: Array in melds:
			if not arr.is_empty():
				final_melds.append(arr)
		final_melds.append(t_cards.duplicate())
		var moved: Array[Card] = []
		for c in t_cards:
			if not hand.has(c):
				moved.append(c)  # pulled table card
		for op: Dictionary in repairs:
			if not moved.has(op["card"]):
				moved.append(op["card"])
		for c in played:
			moved.append(c)  # hand cards fly in too
		var cost: int = pulls.size() + (repairs as Array).size()
		if best.is_empty() or played.size() > best["hand_played"].size() \
				or (played.size() == best["hand_played"].size() and cost < best["cost"]):
			best = {
				"cards": moved,
				"dest": null,
				"rearrange": final_melds,
				"hand_played": played,
				"cost": cost,
				"text": "reworks the table to lay down %s" % _cards_text(t_cards),
			}
	return best

## Table cards the current player must not lift on their own: those slimed into
## a cluster with a neighbour (lifting one drags the whole cluster). A player
## that ignores_sticky (the Cute Slime) has none. Cards sealed inside a shape
## (picture) group are immovable for EVERYONE — even the slime's own planner
## never unpicks her ultimate. The deep planner simply leaves these where they
## are, planning only moves it can actually make.
static func _immovable_cards(gm: GameManager) -> Dictionary:
	var out := {}
	var slides_freely := gm.current_player().ignores_sticky
	for m in gm.board.melds:
		for c in m.cards:
			if m.is_shape() or (not slides_freely and m.sticky_cluster(c).size() > 1):
				out[c] = true
	return out

## Every target meld the deep planner might build: a set (one rank) or a run
## (one suit) made of at least one hand card plus table cards it pulls free.
## Jokers are left out — they are better kept, and the ordinary search already
## handles joker melds.
static func _rearrange_targets(gm: GameManager, hand: Array[Card],
		immovable: Dictionary) -> Array:
	var table: Array[Card] = []
	for m in gm.board.melds:
		for c in m.cards:
			if not c.is_joker and not immovable.has(c):
				table.append(c)
	var out: Array = []
	# Set targets, one per rank the hand holds: all the hand's cards of that rank
	# (distinct suits) plus table cards of the missing suits, up to a valid set.
	var hand_ranks := {}
	for h in hand:
		if not h.is_joker:
			hand_ranks[h.rank] = true
	for rank: int in hand_ranks:
		var chosen: Array[Card] = []
		var suits := {}
		for h in hand:
			if not h.is_joker and h.rank == rank and not suits.has(h.suit):
				chosen.append(h)
				suits[h.suit] = true
		for t in table:
			if chosen.size() >= Rules.MIN_MELD_SIZE:
				break
			if t.rank == rank and not suits.has(t.suit):
				chosen.append(t)
				suits[t.suit] = true
		if chosen.size() >= Rules.MIN_MELD_SIZE and Rules.is_valid_meld(chosen):
			out.append(chosen)
	# Run targets: every maximal consecutive chain in a suit that includes a hand
	# card, ace low and ace high considered separately.
	for suit in Deck.SUITS:
		out.append_array(_run_targets(hand, table, suit))
	return out

## Maximal run targets in one suit: for the ace-low and ace-high readings, chain
## consecutive ranks (hand cards preferred as the source for a rank) and emit
## every maximal chain of 3+ that contains at least one hand card.
static func _run_targets(hand: Array[Card], table: Array[Card], suit: String) -> Array:
	var out: Array = []
	for ace_high: bool in [false, true]:
		var src := {}
		for c in hand:
			if not c.is_joker and c.suit == suit:
				_add_run_src(src, 14 if ace_high and c.rank == 1 else c.rank, c, true)
		for c in table:
			if c.suit == suit:
				_add_run_src(src, 14 if ace_high and c.rank == 1 else c.rank, c, false)
		var ranks := src.keys()
		ranks.sort()
		var chain: Array = []
		var prev := -99
		for r: int in ranks:
			if r != prev + 1:
				_emit_run(out, src, chain)
				chain = []
			chain.append(r)
			prev = r
		_emit_run(out, src, chain)
	return out

static func _add_run_src(src: Dictionary, rank: int, card: Card, from_hand: bool) -> void:
	# Prefer a hand card as a rank's source, so the target plays as many hand
	# cards as it can.
	if not src.has(rank) or (from_hand and not src[rank]["from_hand"]):
		src[rank] = {"card": card, "from_hand": from_hand}

static func _emit_run(out: Array, src: Dictionary, chain: Array) -> void:
	if chain.size() < Rules.MIN_MELD_SIZE:
		return
	var cards: Array[Card] = []
	var has_hand := false
	for r: int in chain:
		cards.append(src[r]["card"])
		if src[r]["from_hand"]:
			has_hand = true
	if has_hand and Rules.is_valid_meld(cards):
		out.append(cards)

## Depth-first repair of a board model (an Array of Array[Card] melds, jokers
## and pulled cards already removed): relocate one card at a time — out of a
## broken meld to a group it fits, or into a broken meld from a donor that stays
## valid — until every meld is valid, spending at most `budget` moves. Returns
## the list of relocation ops ([{card}], most-recent last) with the model left in
## the solved state, or null if no repair fits the budget. `nodes` caps total
## work so an expert planner never stalls the turn.
static func _repair_board(melds: Array, budget: int, immovable: Dictionary,
		nodes: Array) -> Variant:
	nodes[0] += 1
	if nodes[0] > MAX_PLAN_NODES:
		return null
	var bad := -1
	for i in melds.size():
		if not melds[i].is_empty() and not Rules.is_valid_meld(melds[i]):
			bad = i
			break
	if bad == -1:
		return []  # every meld valid
	if budget <= 0:
		return null
	var m: Array = melds[bad]
	# Option A: relocate a card out of the broken meld to a group it completes.
	for c: Card in m.duplicate():
		if immovable.has(c):
			continue
		for j in melds.size():
			if j == bad or melds[j].is_empty():
				continue
			var grown: Array[Card] = melds[j].duplicate()
			grown.append(c)
			if not Rules.is_valid_meld(grown):
				continue
			m.erase(c)
			melds[j].append(c)
			var sub: Variant = _repair_board(melds, budget - 1, immovable, nodes)
			if sub != null:
				(sub as Array).insert(0, {"card": c})
				return sub
			melds[j].erase(c)
			m.append(c)
	# Option B: pull a card into the broken meld from a donor that stays valid.
	for j in melds.size():
		if j == bad or melds[j].is_empty():
			continue
		for c: Card in melds[j].duplicate():
			if immovable.has(c):
				continue
			var leftover: Array[Card] = melds[j].duplicate()
			leftover.erase(c)
			if not (leftover.is_empty() or Rules.is_valid_meld(leftover)):
				continue
			var grown: Array[Card] = m.duplicate()
			grown.append(c)
			if not Rules.is_valid_meld(grown):
				continue
			melds[j].erase(c)
			m.append(c)
			var sub: Variant = _repair_board(melds, budget - 1, immovable, nodes)
			if sub != null:
				(sub as Array).insert(0, {"card": c})
				return sub
			m.erase(c)
			melds[j].append(c)
	return null

static func _hand_subset(hand: Array[Card], cards: Array[Card]) -> Array[Card]:
	var out: Array[Card] = []
	for c in cards:
		if hand.has(c):
			out.append(c)
	return out

## Realize a deep-rearrangement composite on the (staged) game. Each final meld
## either keeps a stationary card (one that never moves) and so maps onto that
## card's live group — into which its other cards are gathered — or is entirely
## new (the target meld) and is built last, once every donor has taken its share.
## Only cards that actually change group are moved, so untouched melds (and any
## slimed clusters within them) are left exactly where they sit.
static func _apply_rearrange(gm: GameManager, move: Dictionary) -> void:
	var final_melds: Array = move["rearrange"]
	var moved: Array = move["cards"]
	var new_melds: Array = []
	for meld: Array in final_melds:
		var anchor: Card = null
		for c: Card in meld:
			if not moved.has(c):
				anchor = c  # a stationary card pins this meld to its live group
				break
		if anchor == null:
			new_melds.append(meld)
			continue
		var dest := gm.board.meld_of(anchor)
		if dest == null:
			new_melds.append(meld)
			continue
		for c: Card in meld:
			if gm.board.meld_of(c) != dest:
				var one: Array[Card] = [c]
				gm.add_cards_to_meld(one, dest)
	for meld: Array in new_melds:
		var cards: Array[Card] = []
		for c: Card in meld:
			cards.append(c)
		gm.move_cards_to_new_meld(cards)

## Threat of the cards that would extend this meld's open ends landing in an
## opponent's play — what an opponent could hold to lay off onto it next turn.
## A set counts its one missing suit; a run counts the ranks just past each
## end, each weighted by _layoff_threat (a copy visibly held in a glass
## opponent hand is a certain feed and counts double the unseen estimate).
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
				worst = maxi(worst, _layoff_threat(gm, rank, s))
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
		exposure += _layoff_threat(gm, lo - 1, suit)
	if hi + 1 <= 13:
		exposure += _layoff_threat(gm, hi + 1, suit)
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
## whose third suit is still obtainable, or a run whose next rank is). A pair
## whose only completions are already all on the table, in hand, or visibly
## locked in glass opponent hands is a dead end — not worth holding — so the AI
## stops hoarding and goes out. A glass top of the stock is a known upcoming
## draw, so it counts as a pairing partner too: the AI holds a card that
## combines with the draw everyone can see coming.
static func _worth_holding(gm: GameManager, c: Card, rest: Array[Card]) -> bool:
	if c.is_joker:
		return true
	var partners: Array[Card] = rest.duplicate()
	var top := gm.deck.peek()
	if top != null and top.is_glass() and not top.is_joker:
		partners.append(top)
	for o in partners:
		if o == c or o.is_joker:
			continue
		# Toward a set: same rank, another suit — needs an obtainable third suit.
		if o.rank == c.rank and o.suit != c.suit:
			for s in Deck.SUITS:
				if s != c.suit and s != o.suit and _obtainable_copies(gm, c.rank, s) > 0:
					return true
		# Toward a run: same suit, adjacent rank — needs an obtainable end card.
		if o.suit == c.suit and absi(o.rank - c.rank) == 1:
			var lo := mini(c.rank, o.rank)
			var hi := maxi(c.rank, o.rank)
			if lo - 1 >= 1 and _obtainable_copies(gm, lo - 1, c.suit) > 0:
				return true
			if hi + 1 <= 13 and _obtainable_copies(gm, hi + 1, c.suit) > 0:
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
	# A deep-rearrangement composite reshuffles several groups at once; realize it
	# through the same staging calls, then point any jokers in the new meld safely.
	if move.has("rearrange"):
		_apply_rearrange(gm, move)
		if profile != null and profile.picks_safe_joker_reps() and not gm.board.melds.is_empty():
			_choose_joker_reps(gm, gm.board.melds[-1])
		return
	# An ultimate-style shape move builds a picture group on its grid cells
	# (the Cute Slime's ult). Pulling the picture's cards out may have broken
	# donor groups; the move carries the repair (planned by the same engine as
	# deep rearrangements) that mends the leftover table. Spending the
	# ultimate drains the meter.
	if move.has("shape_cells"):
		var shape_err := gm.move_cards_to_new_shape(move["cards"], move["shape_cells"])
		if shape_err != "":
			push_warning("GreedyAI staged an illegal shape move (%s)" % shape_err)
			return
		if move.has("shape_repair"):
			_apply_rearrange(gm, {"rearrange": move["shape_repair"],
				"cards": move["shape_repair_moved"]})
		if move.get("ult", false):
			gm.current_player().meter = 0
		return
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
## can stand for: never one whose swap card is visibly held by an opponent (a
## glass card in their hand is a guaranteed claim), then the alternative with
## the fewest copies still unseen (not on the table and not in this AI's own
## hand). An opponent can only swap-claim a joker by holding the exact card it
## stands for, so fewer possible holders means less chance anyone ever takes
## the wildcard. A joker locks the moment it lands in a valid meld, so one
## the AI placed this turn is re-pointed through the engine
## (GameManager.set_joker_stand_in); a still-free joker just gets its
## preference set for the assignment to honor.
static func _choose_joker_reps(gm: GameManager, meld: CardSet) -> void:
	for c in meld.cards:
		if not c.is_joker:
			continue
		if c.joker_lock_rank > 0 and not gm.placed_this_turn(c):
			continue  # locked on an earlier turn: no longer choosable
		var alts := Rules.rechoice_alternatives(meld.cards, c)
		if alts.is_empty():
			continue
		var best: Dictionary = {}
		for alt in alts:
			var cand := {"rank": alt["rank"], "suit": alt["suit"],
				"unseen": _unseen_copies(gm, alt["rank"], alt["suit"]),
				"held": _glass_copies_in_other_hands(gm, alt["rank"], alt["suit"])}
			if best.is_empty() or _safer_rep(cand, best):
				best = cand
		if c.joker_lock_rank > 0:
			if best["rank"] != c.joker_lock_rank or best["suit"] != c.joker_lock_suit:
				gm.set_joker_stand_in(c, meld, best["rank"], best["suit"])
		else:
			c.joker_pref_rank = best["rank"]
			c.joker_pref_suit = best["suit"]

## Ordering for joker stand-in safety: fewest visibly-held swap cards, then
## fewest unseen copies, then lowest rank/suit as a stable tie-break.
static func _safer_rep(a: Dictionary, b: Dictionary) -> bool:
	if a["held"] != b["held"]:
		return a["held"] < b["held"]
	if a["unseen"] != b["unseen"]:
		return a["unseen"] < b["unseen"]
	if a["rank"] != b["rank"]:
		return a["rank"] < b["rank"]
	return a["suit"] < b["suit"]

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

# --- Glass (Clear) awareness -------------------------------------------------
# A glass card is visible from the back: everyone can see it in any player's
# hand and on top of the stock. These helpers read only that public
# information — never a face-down card — so the AI reasons with exactly what a
# human player at the table could count.

## Copies of the exact card visibly held by other players: glass cards in
## their hands. Certain knowledge, unlike the _unseen_copies estimate.
static func _glass_copies_in_other_hands(gm: GameManager, rank: int, suit: String) -> int:
	var held := 0
	for p in gm.players:
		if p == gm.current_player():
			continue
		for c in p.hand:
			if c.is_glass() and not c.is_joker and c.rank == rank and c.suit == suit:
				held += 1
	return held

## Whether the top of the stock is a glass card of exactly this rank and suit —
## public knowledge of the next card anyone draws.
static func _glass_top_matches(gm: GameManager, rank: int, suit: String) -> bool:
	var top := gm.deck.peek()
	return top != null and top.is_glass() and not top.is_joker \
		and top.rank == rank and top.suit == suit

## Copies the current player could still realistically obtain: the unseen
## estimate minus the copies visibly locked in glass opponent hands. A needed
## card sitting glass on top of the stock stays counted — it is still in the
## unseen pool and demonstrably live.
static func _obtainable_copies(gm: GameManager, rank: int, suit: String) -> int:
	return maxi(_unseen_copies(gm, rank, suit)
		- _glass_copies_in_other_hands(gm, rank, suit), 0)

## How hard this exact card threatens to land in an opponent's play: the
## unseen estimate, plus one extra for every copy visibly held in a glass
## opponent hand (a certain threat counts double the uncertain one), plus one
## when the card sits glass on top of the stock (the next drawer simply picks
## it up).
static func _layoff_threat(gm: GameManager, rank: int, suit: String) -> int:
	var threat := _unseen_copies(gm, rank, suit) \
		+ _glass_copies_in_other_hands(gm, rank, suit)
	if _glass_top_matches(gm, rank, suit):
		threat += 1
	return threat

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
