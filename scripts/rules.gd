class_name Rules
extends RefCounted

## Vanilla Machiavelli meld rules (no roguelike effects).
## A meld on the table is valid iff it is:
##  - a set:  3 or 4 cards of the same rank, all suits different, or
##  - a run:  3+ cards of one suit with consecutive ranks; the ace may sit
##    low (A-2-3) or high (Q-K-A) but runs never wrap around (K-A-2 is illegal).

const MIN_MELD_SIZE := 3
const MAX_SET_SIZE := 4

static func is_valid_meld(cards: Array[Card]) -> bool:
	return is_valid_set(cards) or is_valid_run(cards)

static func is_valid_set(cards: Array[Card]) -> bool:
	if cards.size() < MIN_MELD_SIZE or cards.size() > MAX_SET_SIZE:
		return false
	var rank := cards[0].rank
	var seen_suits := {}
	for c in cards:
		if c.rank != rank:
			return false
		if seen_suits.has(c.suit):
			return false
		seen_suits[c.suit] = true
	return true

static func is_valid_run(cards: Array[Card]) -> bool:
	if cards.size() < MIN_MELD_SIZE:
		return false
	var suit := cards[0].suit
	var ranks: Array[int] = []
	for c in cards:
		if c.suit != suit:
			return false
		ranks.append(c.rank)
	return _is_consecutive(ranks) or _is_consecutive(_aces_high(ranks))

## Sorted copy of a meld for display: runs in sequence order (ace where it is
## actually used), anything else by suit then rank.
static func display_order(cards: Array[Card]) -> Array[Card]:
	var out: Array[Card] = cards.duplicate()
	if is_valid_run(out):
		var plain: Array[int] = []
		for c in out:
			plain.append(c.rank)
		var ace_high := not _is_consecutive(plain)
		out.sort_custom(func(a: Card, b: Card) -> bool:
			return _display_rank(a.rank, ace_high) < _display_rank(b.rank, ace_high))
	else:
		out.sort_custom(func(a: Card, b: Card) -> bool:
			if a.suit == b.suit:
				return a.rank < b.rank
			return a.suit < b.suit)
	return out

static func _aces_high(ranks: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for r in ranks:
		out.append(14 if r == 1 else r)
	return out

static func _is_consecutive(ranks: Array[int]) -> bool:
	var ordered: Array[int] = ranks.duplicate()
	ordered.sort()
	for i in range(1, ordered.size()):
		if ordered[i] != ordered[i - 1] + 1:
			return false
	return true

static func _display_rank(rank: int, ace_high: bool) -> int:
	if ace_high and rank == 1:
		return 14
	return rank
