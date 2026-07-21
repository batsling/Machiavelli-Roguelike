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

## Safety cap on search nodes per can_partition call. Real boards resolve in far
## fewer; hitting the cap returns false (conservative — the billionaire simply
## doesn't win off that check and gets another chance next draw).
const NODE_BUDGET := 400000

## Can every card in `cards` be placed into valid melds with none left over?
## Free jokers (unlocked) are wildcards; locked jokers and naturals act as their
## fixed card. An empty pile is trivially tiled; a pile of only jokers cannot be
## (a meld needs a non-wild anchor).
static func can_partition(cards: Array[Card]) -> bool:
	var built := _counts(cards)
	return _solve(built["cnt"], built["jokers"], {}, [NODE_BUDGET])

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
			if _solve(_copy(cnt), jokers, {}, [NODE_BUDGET]):
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

static func _zero_ranks() -> PackedInt32Array:
	var a := PackedInt32Array()
	a.resize(14)  # index 0 unused, 1..13 the ranks
	return a

static func _copy(cnt: Array) -> Array:
	var out: Array = []
	for row: PackedInt32Array in cnt:
		out.append(row.duplicate())
	return out

## True when (cnt, jokers) can be fully partitioned into valid melds.
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
	var key := "%d|%s" % [jokers, str(cnt)]
	if memo.has(key):
		return memo[key]
	var ok := false
	for cand: Dictionary in _melds_with(cnt, jokers, asi, ar):
		if _solve(cand["cnt"], cand["jokers"], memo, budget):
			ok = true
			break
	memo[key] = ok
	return ok

## Every meld that could consume one card at (anchor_suit, anchor_rank), each as
## {"cnt": reduced counts, "jokers": remaining jokers}. Covers sets of the rank
## and runs of the suit (low and ace-high), jokers filling gaps.
static func _melds_with(cnt: Array, jokers: int, asi: int, ar: int) -> Array:
	var out: Array = []
	_sets_with(out, cnt, jokers, asi, ar)
	_runs_with(out, cnt, jokers, asi, ar)
	return out

## Set melds (same rank, distinct suits, size 3-4) containing the anchor.
static func _sets_with(out: Array, cnt: Array, jokers: int, asi: int, ar: int) -> void:
	var others: Array[int] = []
	for si in cnt.size():
		if si != asi and cnt[si][ar] > 0:
			others.append(si)
	# Choose any subset of the other-suit naturals; fill the rest of the set with
	# jokers up to size 3 or 4 (each joker takes one of the still-missing suits).
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
			if jf > jokers:
				continue
			if natural_size + jf > MAX_SET:
				continue  # never more than four suits in a set
			var nc := _copy(cnt)
			nc[asi][ar] -= 1
			for si in chosen:
				nc[si][ar] -= 1
			out.append({"cnt": nc, "jokers": jokers - jf})

## Run melds (one suit, consecutive ranks, length 3+) containing the anchor:
## normal runs inside 1..13, plus ace-high runs that cap a lo..13 block with an
## ace playing above the king. Gaps fill with a joker only where no natural sits.
static func _runs_with(out: Array, cnt: Array, jokers: int, asi: int, ar: int) -> void:
	var suit: PackedInt32Array = cnt[asi]
	# Normal runs [lo, hi], anchor somewhere inside.
	for lo in range(1, ar + 1):
		for hi in range(maxi(ar, lo + MIN_MELD - 1), 14):
			var need_jokers := 0
			var feasible := true
			for k in range(lo, hi + 1):
				if suit[k] == 0:
					need_jokers += 1
			if need_jokers > jokers:
				continue
			var nc := _copy(cnt)
			for k in range(lo, hi + 1):
				if nc[asi][k] > 0:
					nc[asi][k] -= 1
			out.append({"cnt": nc, "jokers": jokers - need_jokers})
	# Ace-high runs: ranks lo..13 (each once) plus one ace on top. Length is
	# (13 - lo + 1) + 1 >= 3, so lo <= 12. The anchor is either a rank in lo..13
	# or the capping ace itself (anchor rank 1).
	if ar == 1 or ar >= 2:
		for lo in range(1, 13):  # lo = 1..12
			if not (ar == 1 or (ar >= lo and ar <= 13)):
				continue
			# The block lo..13, then the ace cap.
			var body_jokers := 0
			for k in range(lo, 14):
				if suit[k] == 0:
					body_jokers += 1
			# The cap: prefer a natural ace, else a joker.
			var cap_natural := suit[1] > (1 if lo == 1 else 0)
			# When lo == 1 the ace at rank 1 is already counted in the body; the
			# cap then needs a *second* ace natural, hence the >1 test above.
			var cap_jokers := 0 if cap_natural else 1
			var total_jokers := body_jokers + cap_jokers
			# Body joker count already assumes the ace slot at rank 1 (if lo==1)
			# is filled; avoid double-charging when lo==1 and it was empty.
			if total_jokers > jokers:
				continue
			# Anchor must actually be consumed by this meld.
			var anchor_in_body := ar >= lo and ar <= 13 and suit[ar] > 0
			var anchor_is_cap := ar == 1 and cap_natural
			if not (anchor_in_body or anchor_is_cap):
				continue
			var nc := _copy(cnt)
			for k in range(lo, 14):
				if nc[asi][k] > 0:
					nc[asi][k] -= 1
			if cap_natural:
				nc[asi][1] -= 1  # spend an ace for the high cap
			out.append({"cnt": nc, "jokers": jokers - total_jokers})
