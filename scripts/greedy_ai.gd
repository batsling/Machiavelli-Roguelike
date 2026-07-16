class_name GreedyAI
extends RefCounted

## Baseline opponent AI. Greedy and deterministic given the same game state,
## so seeded games replay exactly.
##
## Moves are produced one at a time via plan_move() so the UI can show each
## play as it happens; take_turn() drives a whole turn at once for headless
## play and tests. In priority order the AI will:
##  1. lay down any complete meld it holds (largest first),
##  2. lay off single hand cards onto existing table melds,
##  3. rearrange the table: borrow one card from a meld (only when the meld
##     left behind is still valid) to complete a new meld with 2+ hand cards.

static func take_turn(gm: GameManager) -> void:
	var played_any := false
	while true:
		var move := plan_move(gm)
		if move.is_empty():
			break
		apply_move(gm, move)
		played_any = true
	if not played_any:
		gm.draw_and_end_turn()
		return
	var err := gm.commit_turn()
	if err != "":
		# Should be unreachable: every planned move leaves the table valid.
		# Fail safe by drawing rather than wedging the game.
		push_warning("GreedyAI staged an illegal turn (%s); drawing instead." % err)
		gm.draw_and_end_turn()

## Plan the next single move for the current player. Returns {} when no move
## exists, otherwise a Dictionary with:
##   cards: Array[Card]   every card that moves (from hand and/or table)
##   dest:  CardSet|null  existing meld to extend, or null for a new group
##   text:  String        human-readable description ("<name> " + text)
static func plan_move(gm: GameManager) -> Dictionary:
	var hand := gm.current_player().hand
	# 1. Complete meld straight from hand.
	var meld := _find_meld(hand)
	if not meld.is_empty():
		return {"cards": meld, "dest": null,
			"text": "lays down %s" % _cards_text(meld)}
	# 2. Single-card lay-off onto an existing meld.
	for c in hand:
		for m in gm.board.melds:
			var candidate: Array[Card] = m.cards.duplicate()
			candidate.append(c)
			if Rules.is_valid_meld(candidate):
				var single: Array[Card] = [c]
				return {"cards": single, "dest": m,
					"text": "adds %s to %s" % [c.label(), _cards_text(m.cards)]}
	# 3. Rearrange the table: borrow one card from a meld to finish a new meld
	# together with hand cards. Only cards whose removal leaves a valid meld
	# behind are candidates.
	for m in gm.board.melds:
		for t in m.cards:
			var rest: Array[Card] = m.cards.duplicate()
			rest.erase(t)
			if not Rules.is_valid_meld(rest):
				continue
			var pool: Array[Card] = hand.duplicate()
			pool.append(t)
			var combo := _find_meld(pool)
			if combo.is_empty():
				continue
			# Step 1 found no hand-only meld, so combo necessarily uses t and
			# therefore plays at least two hand cards.
			return {"cards": combo, "dest": null,
				"text": "takes %s from the table to build %s" % [t.label(), _cards_text(combo)]}
	return {}

## Apply a move produced by plan_move() to the (staged) game state.
static func apply_move(gm: GameManager, move: Dictionary) -> void:
	var cards: Array[Card] = move["cards"]
	var dest: CardSet = move["dest"]
	if dest == null:
		gm.move_cards_to_new_meld(cards)
	else:
		gm.add_cards_to_meld(cards, dest)

## Largest complete meld (set or run) that can be formed from the given cards.
## Returns an empty array if none exists.
static func _find_meld(pool: Array[Card]) -> Array[Card]:
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

static func _cards_text(cards: Array[Card]) -> String:
	var parts := PackedStringArray()
	for c in Rules.display_order(cards):
		parts.append(c.label())
	return " ".join(parts)
