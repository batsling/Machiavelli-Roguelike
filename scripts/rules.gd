class_name Rules
extends RefCounted

## Vanilla Machiavelli meld rules (no roguelike effects), plus optional jokers.
## A meld on the table is valid iff it is:
##  - a set:  3 or 4 cards of the same rank, all suits different, or
##  - a run:  3+ cards of one suit with consecutive ranks; the ace may sit
##    low (A-2-3) or high (Q-K-A) but runs never wrap around (K-A-2 is illegal).
## Jokers stand in for any card, with two restrictions: a meld needs at least
## one natural card to anchor what the jokers represent, and a joker may only
## represent a card that actually fits (no fifth suit in a set, no rank past
## the ace).

const MIN_MELD_SIZE := 3
const MAX_SET_SIZE := 4

static func is_valid_meld(cards: Array[Card]) -> bool:
	return is_valid_set(cards) or is_valid_run(cards)

static func is_valid_set(cards: Array[Card]) -> bool:
	if cards.size() < MIN_MELD_SIZE or cards.size() > MAX_SET_SIZE:
		return false
	var naturals := _naturals(cards)
	if naturals.is_empty():
		return false
	var rank := naturals[0].rank
	var seen_suits := {}
	for c in naturals:
		if c.rank != rank:
			return false
		if seen_suits.has(c.suit):
			return false
		seen_suits[c.suit] = true
	# At most 4 cards and 4 suits, so the jokers always find a free suit.
	return true

static func is_valid_run(cards: Array[Card]) -> bool:
	return not _run_plan(cards).is_empty()

## Write onto every joker in the meld the card it currently stands for
## (Card.joker_rank / joker_suit), or clear the fields when the meld isn't
## valid. When the meld leaves a choice, a joker's preferred stand-in
## (joker_pref_rank / joker_pref_suit) is honored if it still fits; otherwise
## runs fill inner gaps first, then extend past the high end, then below the
## low end, and sets hand out the missing suits in a fixed order. Call
## whenever a meld changes, before displaying it or swapping with a joker.
static func assign_jokers(cards: Array[Card]) -> void:
	var jokers: Array[Card] = []
	for c in cards:
		if c.is_joker:
			jokers.append(c)
			c.joker_rank = 0
			c.joker_suit = ""
	if jokers.is_empty():
		return
	if is_valid_set(cards):
		var naturals := _naturals(cards)
		var rank: int = naturals[0].rank
		var used := {}
		for c in naturals:
			used[c.suit] = true
		var free: Array[String] = []
		for s in Deck.SUITS:
			if not used.has(s):
				free.append(s)
		# Jokers whose holder picked a still-free suit take it first; the rest
		# share out the remaining suits in a fixed order.
		var rest: Array[Card] = []
		for j in jokers:
			if j.joker_pref_rank == rank and free.has(j.joker_pref_suit):
				j.joker_rank = rank
				j.joker_suit = j.joker_pref_suit
				free.erase(j.joker_pref_suit)
			else:
				rest.append(j)
		for i in rest.size():
			rest[i].joker_rank = rank
			rest[i].joker_suit = free[i]
		return
	var plan := _run_plan(cards)
	if plan.is_empty():
		return
	var suit: String = _naturals(cards)[0].suit
	var joker_ranks: Array = plan["joker_ranks"]
	joker_ranks.sort()
	for i in jokers.size():
		var r: int = joker_ranks[i]
		jokers[i].joker_rank = 1 if r == 14 else r
		jokers[i].joker_suit = suit

## Sorted copy of a meld for display: runs in sequence order (jokers slotted
## where they stand, the ace where it is actually used), anything else by
## suit then rank with jokers last. Never mutates the cards.
static func display_order(cards: Array[Card]) -> Array[Card]:
	var out: Array[Card] = cards.duplicate()
	var plan := _run_plan(out)
	if not plan.is_empty():
		var joker_ranks: Array = plan["joker_ranks"]
		joker_ranks.sort()
		var pos := {}
		var next_joker := 0
		for c in out:
			if c.is_joker:
				pos[c] = joker_ranks[next_joker]
				next_joker += 1
			else:
				pos[c] = 14 if plan["ace_high"] and c.rank == 1 else c.rank
		out.sort_custom(func(a: Card, b: Card) -> bool:
			return pos[a] < pos[b])
	else:
		out.sort_custom(func(a: Card, b: Card) -> bool:
			if a.is_joker != b.is_joker:
				return b.is_joker
			if a.suit == b.suit:
				return a.rank < b.rank
			return a.suit < b.suit)
	return out

static func _naturals(cards: Array[Card]) -> Array[Card]:
	var out: Array[Card] = []
	for c in cards:
		if not c.is_joker:
			out.append(c)
	return out

## Try to lay the cards out as a run. Returns {} when impossible, otherwise
## {"joker_ranks": Array[int] with one display rank per joker (ace-high runs
##  use 14), "ace_high": bool}.
static func _run_plan(cards: Array[Card]) -> Dictionary:
	if cards.size() < MIN_MELD_SIZE:
		return {}
	var naturals := _naturals(cards)
	if naturals.is_empty():
		return {}
	var joker_count := cards.size() - naturals.size()
	var suit := naturals[0].suit
	var seen_ranks := {}
	for c in naturals:
		if c.suit != suit:
			return {}
		if seen_ranks.has(c.rank):
			return {}
		seen_ranks[c.rank] = true
	for ace_high: bool in [false, true]:
		var ranks: Array[int] = []
		for c in naturals:
			ranks.append(14 if ace_high and c.rank == 1 else c.rank)
		var low_bound := 2 if ace_high else 1
		var high_bound := 14 if ace_high else 13
		var options := _run_fill_options(ranks, joker_count, low_bound, high_bound)
		if options.is_empty():
			continue
		# Honor the jokers' preferred stand-ins: pick the layout that covers
		# the most of them, highest-extension-first on ties (the default).
		var prefs: Array[int] = []
		for c in cards:
			if c.is_joker and c.joker_pref_suit == suit and c.joker_pref_rank > 0:
				prefs.append(14 if ace_high and c.joker_pref_rank == 1 else c.joker_pref_rank)
		var best: Array[int] = options[0]
		var best_score := _pref_coverage(best, prefs)
		for i in range(1, options.size()):
			var score := _pref_coverage(options[i], prefs)
			if score > best_score:
				best = options[i]
				best_score = score
		return {"joker_ranks": best, "ace_high": ace_high}
	return {}

## All the ways `joker_count` wildcards can complete the natural `ranks` into
## one consecutive run inside [low_bound, high_bound]: inner gaps are always
## forced, spare jokers may split between the two ends any way that fits.
## Returns an Array of fill-rank Arrays, most-high-extension first (the
## default layout), or [] when no layout exists.
static func _run_fill_options(ranks: Array[int], joker_count: int,
		low_bound: int, high_bound: int) -> Array:
	var ordered: Array[int] = ranks.duplicate()
	ordered.sort()
	if ordered[0] < low_bound or ordered[-1] > high_bound:
		return []
	var forced: Array[int] = []
	for i in range(1, ordered.size()):
		for r in range(ordered[i - 1] + 1, ordered[i]):
			forced.append(r)
	if forced.size() > joker_count:
		return []
	var extra := joker_count - forced.size()
	var lo := ordered[0]
	var hi := ordered[-1]
	var options: Array = []
	for high_n in range(mini(extra, high_bound - hi), -1, -1):
		var low_n := extra - high_n
		if low_n > lo - low_bound:
			continue
		var fill: Array[int] = forced.duplicate()
		for i in high_n:
			fill.append(hi + 1 + i)
		for i in low_n:
			fill.append(lo - 1 - i)
		options.append(fill)
	return options

## How many of the preferred ranks this fill satisfies (each fill rank can
## satisfy at most one preference).
static func _pref_coverage(fill: Array[int], prefs: Array[int]) -> int:
	var remaining: Array[int] = fill.duplicate()
	var score := 0
	for r in prefs:
		var idx := remaining.find(r)
		if idx != -1:
			remaining.remove_at(idx)
			score += 1
	return score

## Every card a joker in this meld could be made to stand for, as
## {"rank": int, "suit": String} entries (aces reported as rank 1). Empty when
## the meld is invalid, has no jokers, or leaves them no actual choice (inner
## run gaps are forced, and a set whose jokers cover every missing suit offers
## nothing to pick). Feeds the UI's right-click joker menu and the AI's safe
## stand-in selection.
static func joker_alternatives(cards: Array[Card]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var naturals := _naturals(cards)
	var joker_count := cards.size() - naturals.size()
	if joker_count == 0 or naturals.is_empty():
		return out
	if is_valid_set(cards):
		var used := {}
		for c in naturals:
			used[c.suit] = true
		var free: Array[String] = []
		for s in Deck.SUITS:
			if not used.has(s):
				free.append(s)
		if free.size() <= joker_count:
			return out
		for s in free:
			out.append({"rank": naturals[0].rank, "suit": s})
		return out
	if not is_valid_run(cards):
		return out
	# Runs: mirror _run_plan's layout family; the choices are the ranks that
	# appear in some layouts but not all.
	var suit: String = naturals[0].suit
	for ace_high: bool in [false, true]:
		var ranks: Array[int] = []
		for c in naturals:
			ranks.append(14 if ace_high and c.rank == 1 else c.rank)
		var low_bound := 2 if ace_high else 1
		var high_bound := 14 if ace_high else 13
		var options := _run_fill_options(ranks, joker_count, low_bound, high_bound)
		if options.is_empty():
			continue
		var seen_in := {}
		for opt: Array in options:
			for r: int in opt:
				seen_in[r] = int(seen_in.get(r, 0)) + 1
		var choice_ranks: Array[int] = []
		for r: int in seen_in:
			if seen_in[r] < options.size():
				choice_ranks.append(r)
		choice_ranks.sort()
		for r in choice_ranks:
			out.append({"rank": 1 if r == 14 else r, "suit": suit})
		break
	return out
