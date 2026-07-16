class_name GreedyAI
extends RefCounted

## Baseline opponent AI. Greedy and table-blind on purpose:
##  - lays down any complete meld it holds (largest first),
##  - lays off single cards onto existing table melds,
##  - never rearranges the table (that is the human's edge for now),
##  - draws when it cannot play.
## Deterministic given the same game state, so seeded games replay exactly.

static func take_turn(gm: GameManager) -> void:
	var played_any := false
	while _play_one(gm):
		played_any = true
	if not played_any:
		gm.draw_and_end_turn()
		return
	var err := gm.commit_turn()
	if err != "":
		# Should be unreachable: the AI only stages hand-only, pre-validated
		# melds. Fail safe by drawing rather than wedging the game.
		push_warning("GreedyAI staged an illegal turn (%s); drawing instead." % err)
		gm.draw_and_end_turn()

## Stage a single play if one exists. Returns true if something was played.
static func _play_one(gm: GameManager) -> bool:
	var hand := gm.current_player().hand
	var meld := _find_meld_in_hand(hand)
	if not meld.is_empty():
		gm.move_cards_to_new_meld(meld)
		return true
	# Single-card lay-off onto an existing meld.
	for c in hand:
		for m in gm.board.melds:
			var candidate: Array[Card] = m.cards.duplicate()
			candidate.append(c)
			if Rules.is_valid_meld(candidate):
				var single: Array[Card] = [c]
				gm.add_cards_to_meld(single, m)
				return true
	return false

## Largest complete meld (set or run) that can be formed from hand cards alone.
## Returns an empty array if none exists.
static func _find_meld_in_hand(hand: Array[Card]) -> Array[Card]:
	var best: Array[Card] = []
	# Sets: same rank, distinct suits (two decks mean duplicate suits exist).
	var by_rank := {}
	for c in hand:
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
	for c in hand:
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
