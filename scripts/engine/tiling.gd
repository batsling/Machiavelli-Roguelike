class_name Tiling
extends RefCounted

## Exact "can this whole pile be laid down?" solver for Machiavelli melds.
##
## can_partition(cards) answers: can this multiset of cards be split, using EVERY
## card, into valid melds (Rules sets and runs, joker-aware)? This is the
## full-rearrangement going-out test — the same question a player faces when
## deciding whether their hand plus the whole table can be re-melded to leave
## nothing over. The Sadistic Billionaire's Riichi ultimate reads it three ways:
##   - tenpai / wait set: which single extra card makes the pile go out,
##   - tsumo: does the card he just drew complete it,
##   - ron: has an opponent's play made his hand + the table go out.
##
## Method: a memoized depth-first search. Each step picks a concrete natural
## card that still has to be placed (the "anchor") and tries every valid meld
## that could contain it — a set of its rank, or a run of its suit (ace low or
## ace high), with free jokers filling gaps. Removing a meld strictly shrinks
## the pile, so the recursion terminates; a node budget caps pathological boards
## and makes the solver fail *closed* (returns false — never a phantom win).
##
## Correctness note on jokers: within one candidate meld a gap is filled with a
## natural when one is present and a joker only when it isn't. Jokers are
## fungible wildcards, so which specific slot a joker lands in never changes how
## many jokers the whole partition needs — only the choice of *which melds* to
## form matters, and that is fully branched. See the run/set enumerators below.

## Ranks run 1 (ace) .. 13 (king). An ace also plays high (above the king) in a
## run; that is handled as a special "cap" slot on Q-K-A style runs, not a 14th
## rank in the count table.
const MIN_MELD := 3
const MAX_SET := 4

## Safety cap on search nodes per can_partition call. A tileable pile is found
## fast (the anchored search builds melds greedily); the budget only bounds the
## exhaustive failure case. Hitting it returns false — conservative: the
## billionaire simply doesn't win off that check and gets another chance.
const NODE_BUDGET := 60000

## Can every card in `cards` be placed into valid melds with none left over?
## Free jokers (unlocked) are wildcards; locked jokers and naturals act as their
## fixed card. An empty pile is trivially tiled; a pile of only jokers cannot be
## (a meld needs a non-wild anchor).
static func can_partition(cards: Array[Card]) -> bool:
	var built := _counts(cards)
	return _solve(built["cnt"], built["jokers"], {}, [NODE_BUDGET])

## Cheap "tenpai" gate: can the pile go out with one wildcard added? True iff the
## pile is at most one card from tiling (already tiled, or one draw away). A
## single solve, so callers can skip the 52-card wait enumeration when he is not
## even close. Equivalent to can_partition(cards + one free joker).
static func can_partition_with_wild(cards: Array[Card]) -> bool:
	var built := _counts(cards)
	return _solve(built["cnt"], built["jokers"] + 1, {}, [NODE_BUDGET])

## How many extra cards the pile is from going out — its "shanten"-like distance:
## the fewest wildcards that, added in, let it tile. 0 means it already tiles, 1
## is tenpai (one card away), and so on. Capped at `cap`; a pile further than that
## returns cap + 1. Lets a strategy compare how a play changes its distance to a
## win without caring about the exact large value.
static func min_extra_to_tile(cards: Array[Card], cap: int = 4) -> int:
	var built := _counts(cards)
	for k in range(cap + 1):
		if _solve(built["cnt"], built["jokers"] + k, {}, [NODE_BUDGET]):
			return k
	return cap + 1

## Every natural card (rank+suit) that, added to `cards` as one more copy, makes
## the whole pile go out — the wait set. Returned as {"rank": int, "suit": String}
## entries (ace reported as rank 1). Does not judge whether a live copy of the
## card still exists to be drawn or claimed; the caller weighs that.
static func wait_cards(cards: Array[Card]) -> Array[Dictionary]:
	var built := _counts(cards)
	var cnt: Array = built["cnt"]
	var jokers: int = built["jokers"]
	var out: Array[Dictionary] = []
	for si in Deck.SUITS.size():
		for r in range(1, 14):
			cnt[si][r] += 1
			# _solve restores cnt before returning, so it can be reused in place.
			if _solve(cnt, jokers, {}, [NODE_BUDGET]):
				out.append({"rank": r, "suit": Deck.SUITS[si]})
			cnt[si][r] -= 1
	return out

# --- Core search --------------------------------------------------------------

## Build the count table (4 suits x ranks 1..13) plus the free-joker tally from
## a card list. Locked jokers fold into their locked card; naturals into theirs.
static func _counts(cards: Array[Card]) -> Dictionary:
	var cnt: Array = []
	for _si in Deck.SUITS.size():
		cnt.append(_zero_ranks())
	var jokers := 0
	for c in cards:
		if c.is_joker and c.joker_lock_rank == 0:
			jokers += 1
			continue
		var r := c.joker_lock_rank if c.is_joker else c.rank
		var s := c.joker_lock_suit if c.is_joker else c.suit
		var si := Deck.SUITS.find(s)
		if si == -1 or r < 1 or r > 13:
			continue  # a card the meld rules could never place; ignore it
		cnt[si][r] += 1
	return {"cnt": cnt, "jokers": jokers}

## A compact, cheap memo key for a search state: one printable byte per
## (suit, rank) count plus the joker count, offset into the ASCII range so the
## bytes never include a NUL. Much faster to build than str()-ing the arrays.
static func _state_key(cnt: Array, jokers: int) -> String:
	var bytes := PackedByteArray()
	bytes.resize(cnt.size() * 13 + 1)
	var idx := 0
	for row: PackedInt32Array in cnt:
		for r in range(1, 14):
			bytes[idx] = 48 + mini(row[r], 60)
			idx += 1
	bytes[idx] = 48 + mini(jokers, 60)
	return bytes.get_string_from_ascii()

static func _zero_ranks() -> PackedInt32Array:
	var a := PackedInt32Array()
	a.resize(14)  # index 0 unused, 1..13 the ranks
	return a

## True when (cnt, jokers) can be fully partitioned into valid melds. Searches by
## mutating `cnt` in place (apply a meld, recurse, undo), so no per-candidate
## array copies are made; `cnt` is always restored to its entry state before this
## returns, which lets callers reuse the same array across probes.
static func _solve(cnt: Array, jokers: int, memo: Dictionary, budget: Array) -> bool:
	budget[0] -= 1
	if budget[0] < 0:
		return false
	# Anchor on the lowest remaining natural (lowest rank, then suit) — a
	# deterministic choice that keeps the memo table dense.
	var asi := -1
	var ar := -1
	for r in range(1, 14):
		for si in cnt.size():
			if cnt[si][r] > 0:
				asi = si
				ar = r
				break
		if ar != -1:
			break
	if ar == -1:
		# No naturals left: solved only if no jokers dangle (they can't stand alone).
		return jokers == 0
	var key := _state_key(cnt, jokers)
	if memo.has(key):
		return memo[key]
	var ok := _try_sets(cnt, jokers, asi, ar, memo, budget) \
		or _try_runs(cnt, jokers, asi, ar, memo, budget)
	memo[key] = ok
	return ok

## Try every set meld (same rank, distinct suits, size 3-4) that consumes the
## anchor, mutating and restoring `cnt`. Returns true as soon as one leads to a
## full partition.
static func _try_sets(cnt: Array, jokers: int, asi: int, ar: int,
		memo: Dictionary, budget: Array) -> bool:
	var others: Array[int] = []
	for si in cnt.size():
		if si != asi and cnt[si][ar] > 0:
			others.append(si)
	for mask in range(1 << others.size()):
		var chosen: Array[int] = []
		for i in others.size():
			if mask & (1 << i):
				chosen.append(others[i])
		var natural_size := 1 + chosen.size()  # anchor + chosen naturals
		for size: int in [MIN_MELD, MAX_SET]:
			if size < natural_size:
				continue
			var jf := size - natural_size
			if jf > jokers or natural_size + jf > MAX_SET:
				continue
			cnt[asi][ar] -= 1
			for si in chosen:
				cnt[si][ar] -= 1
			var res := _solve(cnt, jokers - jf, memo, budget)
			cnt[asi][ar] += 1
			for si in chosen:
				cnt[si][ar] += 1
			if res:
				return true
	return false

## Try every run meld (one suit, consecutive ranks, length 3+) that consumes the
## anchor — normal runs in 1..13 and ace-high runs capping a lo..13 block with an
## ace above the king — mutating and restoring `cnt`.
static func _try_runs(cnt: Array, jokers: int, asi: int, ar: int,
		memo: Dictionary, budget: Array) -> bool:
	var suit: PackedInt32Array = cnt[asi]
	# Normal runs [lo, hi] with the anchor inside.
	for lo in range(1, ar + 1):
		for hi in range(maxi(ar, lo + MIN_MELD - 1), 14):
			var need_jokers := 0
			for k in range(lo, hi + 1):
				if suit[k] == 0:
					need_jokers += 1
			if need_jokers > jokers:
				continue
			var dec: Array[int] = []
			for k in range(lo, hi + 1):
				if suit[k] > 0:
					suit[k] -= 1
					dec.append(k)
			var res := _solve(cnt, jokers - need_jokers, memo, budget)
			for k in dec:
				suit[k] += 1
			if res:
				return true
	# Ace-high runs: block lo..13 (each once) plus one ace above the king.
	for lo in range(1, 13):  # lo = 1..12
		if not (ar == 1 or (ar >= lo and ar <= 13)):
			continue
		var body_jokers := 0
		for k in range(lo, 14):
			if suit[k] == 0:
				body_jokers += 1
		# The cap prefers a natural ace, else a joker. When lo == 1 the body
		# already spends one ace at rank 1, so the cap needs a second one.
		var cap_natural := suit[1] > (1 if lo == 1 else 0)
		var total_jokers := body_jokers + (0 if cap_natural else 1)
		if total_jokers > jokers:
			continue
		var anchor_in_body := ar >= lo and ar <= 13 and suit[ar] > 0
		var anchor_is_cap := ar == 1 and cap_natural
		if not (anchor_in_body or anchor_is_cap):
			continue
		var dec: Array[int] = []
		for k in range(lo, 14):
			if suit[k] > 0:
				suit[k] -= 1
				dec.append(k)
		if cap_natural:
			suit[1] -= 1  # spend an ace for the high cap
		var res := _solve(cnt, jokers - total_jokers, memo, budget)
		for k in dec:
			suit[k] += 1
		if cap_natural:
			suit[1] += 1
		if res:
			return true
	return false
