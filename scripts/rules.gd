class_name Rules
extends RefCounted

## Vanilla Machiavelli meld rules (no roguelike effects), plus optional jokers.
## A meld on the table is valid iff it is:
##  - a set:  3 or 4 cards of the same rank, all suits different, or
##  - a run:  3+ cards of one suit with consecutive ranks; the ace may sit
##    low (A-2-3) or high (Q-K-A) but runs never wrap around (K-A-2 is illegal).
## Jokers stand in for any card, with two restrictions: a meld needs at least
## one anchoring card that isn't a free wildcard, and a joker may only
## represent a card that actually fits (no fifth suit in a set, no rank past
## the ace).
##
## Locking: the moment a joker sits in a valid meld on the table it locks to
## the card it stands for (Card.joker_lock_rank / joker_lock_suit, set by
## GameManager after every staged move). A locked joker is "fixed": every
## rule here treats it as exactly that card — it can be rearranged like any
## card but is no longer a wildcard — until it returns to a hand (the joker
## swap, an undo, or taking a just-played joker back). The player who placed
## it may still re-point it among the valid alternatives until their turn
## ends (GameManager.set_joker_stand_in).

const MIN_MELD_SIZE := 3
const MAX_SET_SIZE := 4

static func is_valid_meld(cards: Array[Card]) -> bool:
	return is_valid_set(cards) or is_valid_run(cards)

static func is_valid_set(cards: Array[Card]) -> bool:
	if cards.size() < MIN_MELD_SIZE or cards.size() > MAX_SET_SIZE:
		return false
	var fixed := _fixed(cards)
	if fixed.is_empty():
		return false
	var rank := _eff_rank(fixed[0])
	var seen_suits := {}
	for c in fixed:
		if _eff_rank(c) != rank:
			return false
		if seen_suits.has(_eff_suit(c)):
			return false
		seen_suits[_eff_suit(c)] = true
	# At most 4 cards and 4 suits, so free jokers always find a free suit.
	return true

static func is_valid_run(cards: Array[Card]) -> bool:
	return not _run_plan(cards).is_empty()

## Write onto every joker in the meld the card it currently stands for
## (Card.joker_rank / joker_suit). A locked joker always shows its locked
## card; free jokers are recomputed, or cleared when the meld isn't valid.
## When the meld leaves a free joker a choice, its preferred stand-in
## (joker_pref_rank / joker_pref_suit) is honored if it still fits; otherwise
## runs fill inner gaps first, then extend past the high end, then below the
## low end, and sets hand out the missing suits in a fixed order. Call
## whenever a meld changes, before displaying it or swapping with a joker.
static func assign_jokers(cards: Array[Card]) -> void:
	var free_jokers: Array[Card] = []
	for c in cards:
		if not c.is_joker:
			continue
		if c.joker_lock_rank > 0:
			c.joker_rank = c.joker_lock_rank
			c.joker_suit = c.joker_lock_suit
		else:
			free_jokers.append(c)
			c.joker_rank = 0
			c.joker_suit = ""
	if free_jokers.is_empty():
		return
	if is_valid_set(cards):
		var fixed := _fixed(cards)
		var rank := _eff_rank(fixed[0])
		var used := {}
		for c in fixed:
			used[_eff_suit(c)] = true
		var free: Array[String] = []
		for s in Deck.SUITS:
			if not used.has(s):
				free.append(s)
		# Jokers whose holder picked a still-free suit take it first; the rest
		# share out the remaining suits in a fixed order.
		var rest: Array[Card] = []
		for j in free_jokers:
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
	var suit := _eff_suit(_fixed(cards)[0])
	var joker_ranks: Array = plan["joker_ranks"]
	joker_ranks.sort()
	for i in free_jokers.size():
		var r: int = joker_ranks[i]
		free_jokers[i].joker_rank = 1 if r == 14 else r
		free_jokers[i].joker_suit = suit

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
			if c.is_joker and c.joker_lock_rank == 0:
				pos[c] = joker_ranks[next_joker]
				next_joker += 1
			else:
				var r := _eff_rank(c)
				pos[c] = 14 if plan["ace_high"] and r == 1 else r
		out.sort_custom(func(a: Card, b: Card) -> bool:
			return pos[a] < pos[b])
	else:
		out.sort_custom(func(a: Card, b: Card) -> bool:
			if _is_fixed(a) != _is_fixed(b):
				return _is_fixed(a)
			if _eff_suit(a) == _eff_suit(b):
				return _eff_rank(a) < _eff_rank(b)
			return _eff_suit(a) < _eff_suit(b))
	return out

## Partition a hand into the melds hiding in it, for the UI's Sort/Randomize.
## Greedily pulls out the largest valid combo at a time (ties favour runs, which
## are harder to complete), so each natural card lands in at most one combo.
## Returns {"combos": Array of Array[Card] (each in display order), "leftovers":
## Array[Card] in no combo, "jokers": Array[Card]}. Jokers are always set aside
## — a free wildcard reads better on its own than glued into someone's guess of
## its meld. Duplicate cards (two decks) and the low/high ace are handled as
## everywhere else here.
static func partition_hand(cards: Array[Card]) -> Dictionary:
	var remaining: Array[Card] = []
	var jokers: Array[Card] = []
	for c in cards:
		if c.is_joker:
			jokers.append(c)
		else:
			remaining.append(c)
	var combos: Array = []
	while true:
		var meld := _best_natural_meld(remaining)
		if meld.size() < MIN_MELD_SIZE:
			break
		for c in meld:
			remaining.erase(c)
		combos.append(display_order(meld))
	return {"combos": combos, "leftovers": remaining, "jokers": jokers}

## The single biggest valid meld sitting in `pool` (naturals only), or [] if
## there is none: the longest run per suit and the fullest set per rank, deduping
## copies and trying the ace both low and high. Runs win ties, so they are pulled
## out before sets.
static func _best_natural_meld(pool: Array[Card]) -> Array[Card]:
	var best: Array[Card] = []
	# Runs: per suit, one card per rank (ace counts as 1 and 14), longest chain.
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
				if chain.size() > best.size() and is_valid_meld(chain):
					best = chain.duplicate()
				chain.clear()
			chain.append(ranks[r])
			prev = r
		if chain.size() > best.size() and is_valid_meld(chain):
			best = chain.duplicate()
	# Sets: same rank, distinct suits, up to four. Only a strictly bigger set
	# beats a run of equal length, so runs are preferred on ties.
	var by_rank := {}
	for c in pool:
		if not by_rank.has(c.rank):
			by_rank[c.rank] = {}
		var suits: Dictionary = by_rank[c.rank]
		if not suits.has(c.suit):
			suits[c.suit] = c
	for rank in by_rank:
		var suits: Dictionary = by_rank[rank]
		if suits.size() < MIN_MELD_SIZE:
			continue
		var meld: Array[Card] = []
		for suit in suits:
			meld.append(suits[suit])
			if meld.size() == MAX_SET_SIZE:
				break
		if meld.size() > best.size() and is_valid_meld(meld):
			best = meld
	return best

## Fixed cards act as themselves: naturals, plus locked jokers standing for
## their locked card. Only free (unlocked) jokers are wildcards.
static func _is_fixed(c: Card) -> bool:
	return not c.is_joker or c.joker_lock_rank > 0

static func _eff_rank(c: Card) -> int:
	return c.joker_lock_rank if c.is_joker else c.rank

static func _eff_suit(c: Card) -> String:
	return c.joker_lock_suit if c.is_joker else c.suit

static func _fixed(cards: Array[Card]) -> Array[Card]:
	var out: Array[Card] = []
	for c in cards:
		if _is_fixed(c):
			out.append(c)
	return out

## Try to lay the cards out as a run. Returns {} when impossible, otherwise
## {"joker_ranks": Array[int] with one display rank per free joker (ace-high
##  runs use 14), "ace_high": bool}.
static func _run_plan(cards: Array[Card]) -> Dictionary:
	if cards.size() < MIN_MELD_SIZE:
		return {}
	var fixed := _fixed(cards)
	if fixed.is_empty():
		return {}
	var joker_count := cards.size() - fixed.size()
	var suit := _eff_suit(fixed[0])
	var seen_ranks := {}
	for c in fixed:
		if _eff_suit(c) != suit:
			return {}
		if seen_ranks.has(_eff_rank(c)):
			return {}
		seen_ranks[_eff_rank(c)] = true
	for ace_high: bool in [false, true]:
		var ranks: Array[int] = []
		for c in fixed:
			ranks.append(14 if ace_high and _eff_rank(c) == 1 else _eff_rank(c))
		var low_bound := 2 if ace_high else 1
		var high_bound := 14 if ace_high else 13
		var options := _run_fill_options(ranks, joker_count, low_bound, high_bound)
		if options.is_empty():
			continue
		# Honor the free jokers' preferred stand-ins: pick the layout that
		# covers the most of them, highest-extension-first on ties (the default).
		var prefs: Array[int] = []
		for c in cards:
			if c.is_joker and c.joker_lock_rank == 0 \
					and c.joker_pref_suit == suit and c.joker_pref_rank > 0:
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

## Every card this joker could be made to stand for in its meld if it were
## free, regardless of its current lock — the choices open to the player who
## placed it this turn (see GameManager.set_joker_stand_in). Same entries as
## joker_alternatives; empty when the meld (with the joker wild again) is
## invalid or leaves no actual choice. Restores the lock before returning, so
## the cards are never left mutated.
static func rechoice_alternatives(cards: Array[Card], joker: Card) -> Array[Dictionary]:
	if not joker.is_joker or not cards.has(joker):
		return []
	var lock_rank := joker.joker_lock_rank
	var lock_suit := joker.joker_lock_suit
	joker.joker_lock_rank = 0
	joker.joker_lock_suit = ""
	var out := joker_alternatives(cards)
	joker.joker_lock_rank = lock_rank
	joker.joker_lock_suit = lock_suit
	return out

## Every card a free (unlocked) joker in this meld could be made to stand
## for, as {"rank": int, "suit": String} entries (aces reported as rank 1).
## Empty when the meld is invalid, has no free jokers, or leaves them no
## actual choice (inner run gaps are forced, a set whose free jokers cover
## every missing suit offers nothing to pick, and locked jokers are no longer
## choosable at all). Feeds the UI's right-click joker menu and the AI's safe
## stand-in selection.
static func joker_alternatives(cards: Array[Card]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var fixed := _fixed(cards)
	var joker_count := cards.size() - fixed.size()
	if joker_count == 0 or fixed.is_empty():
		return out
	if is_valid_set(cards):
		var used := {}
		for c in fixed:
			used[_eff_suit(c)] = true
		var free: Array[String] = []
		for s in Deck.SUITS:
			if not used.has(s):
				free.append(s)
		if free.size() <= joker_count:
			return out
		for s in free:
			out.append({"rank": _eff_rank(fixed[0]), "suit": s})
		return out
	if not is_valid_run(cards):
		return out
	# Runs: mirror _run_plan's layout family; the choices are the ranks that
	# appear in some layouts but not all.
	var suit := _eff_suit(fixed[0])
	for ace_high: bool in [false, true]:
		var ranks: Array[int] = []
		for c in fixed:
			ranks.append(14 if ace_high and _eff_rank(c) == 1 else _eff_rank(c))
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
