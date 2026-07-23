class_name PlayAdvisor
extends RefCounted

## Advises the table on what a hand card can do *right now* with no rearranging:
## which board groups it lays off onto, whether it completes a fresh group from
## the hand, and — for double-click auto-play — the concrete cards of that play.
## Pure game-rule reasoning over a GameManager: no widgets and no turn/AI state
## (the controller adds the "is it my turn" gate). Split out of MainUI so the
## hover hints, the always-on green playable-now cap and the double-click all
## read the board through one place. Mirrors the collaborator pattern of
## TableView / CardRenderer — a focused helper the controller owns.

var gm: GameManager

func _init(game_manager: GameManager) -> void:
	gm = game_manager

## True when hand card `c` drops straight onto `meld` as-is (no rearranging):
## the group is a plain valid set/run this card extends, and — before you have
## opened (`open` is false) — only your own just-laid groups qualify. Pictures
## and extension lines play by grid rules, so the plain lay-off skips them
## (their ghost cells are the guide instead). Shared by the hover hints, the
## always-on playable marker and auto-play so they all read the board the same.
func lays_off_onto(c: Card, meld: CardSet, open: bool) -> bool:
	if meld.is_shape() or meld.is_attached():
		return false
	if not meld.is_valid():
		return false
	if not open and not gm.is_own_staged_meld(meld):
		return false
	var candidate: Array[Card] = meld.cards.duplicate()
	candidate.append(c)
	return Rules.is_valid_meld(candidate)

## The play hints for hovering `c`: which existing groups it lays off onto and
## whether it completes a brand-new group with other cards already in the hand.
## Returns {"meld_targets": {CardSet: true}, "new_group": bool}.
func play_hints(c: Card, open: bool) -> Dictionary:
	var targets := {}
	for meld in gm.board.melds:
		if lays_off_onto(c, meld, open):
			targets[meld] = true
	return {"meld_targets": targets, "new_group": forms_new_group(c)}

## True when `c` can be played this instant with no rearranging — a lay-off onto
## some existing group, or a fresh group from naturals in hand. Carries no
## turn gate: the caller combines it with "is it my turn" (it drives the green
## cap, which only ever shows on your own turn).
func playable_now(c: Card, open: bool) -> bool:
	if forms_new_group(c):
		return true
	for meld in gm.board.melds:
		if lays_off_onto(c, meld, open):
			return true
	return false

## The play a double-click should make on `c`: {"meld": CardSet} to lay it off,
## {"new_group": Array[Card]} to lay a fresh group, or {} for neither. Lay-off
## wins when both are possible (the smallest move — just this one card).
## Decides only; the caller stages the move.
func auto_play_target(c: Card, open: bool) -> Dictionary:
	for meld in gm.board.melds:
		if lays_off_onto(c, meld, open):
			return {"meld": meld}
	var group := new_group_cards_for(c)
	if not group.is_empty():
		return {"new_group": group}
	return {}

## True when `c` plus other naturals already in the hand make a valid new group —
## a set of its rank across distinct suits, or a run of its suit. Plays that
## would need a joker to complete are disregarded, so the cue only lights for
## groups you can form without spending a wildcard. A joker can't anchor a group
## on its own, so it never counts.
func forms_new_group(c: Card) -> bool:
	if c.is_joker:
		return false
	var hand := gm.players[0].hand
	# Set: c plus other naturals of the same rank in distinct suits (no jokers).
	var suits := {c.suit: true}
	for h in hand:
		if h != c and not h.is_joker and h.rank == c.rank:
			suits[h.suit] = true
	if suits.size() >= Rules.MIN_MELD_SIZE:
		return true
	# Run: c plus other naturals of the same suit, with no jokers to bridge gaps.
	var ranks := {c.rank: true}
	for h in hand:
		if h != c and not h.is_joker and h.suit == c.suit:
			ranks[h.rank] = true
	return _run_reachable(c.rank, ranks, 0)

## The concrete cards of the brand-new group `c` completes with other naturals
## in the hand — a set of its rank across distinct suits, or the longest run of
## its suit through it — or an empty array when none forms (jokers never count,
## mirroring forms_new_group). Verified against the rules before returning, so
## the caller can stage it straight away.
func new_group_cards_for(c: Card) -> Array[Card]:
	if c.is_joker:
		return []
	var hand := gm.players[0].hand
	# Set: c plus one natural per other suit of the same rank (capped at a full
	# set by is_valid_meld's MAX_SET_SIZE guard).
	var set_cards: Array[Card] = [c]
	var suits := {c.suit: true}
	for h in hand:
		if h != c and not h.is_joker and h.rank == c.rank and not suits.has(h.suit):
			set_cards.append(h)
			suits[h.suit] = true
	if set_cards.size() >= Rules.MIN_MELD_SIZE and Rules.is_valid_meld(set_cards):
		return set_cards
	# Run: the maximal contiguous block of naturals in c's suit that spans c.
	var run := _natural_run_for(c, hand)
	if run.size() >= Rules.MIN_MELD_SIZE and Rules.is_valid_meld(run):
		return run
	return []

## Whether a run of at least MIN_MELD_SIZE cards covering `target` fits within one
## suit given the natural ranks present and `jokers` wildcards to fill gaps or
## extend the ends. Tries the ace both low and high, never wrapping.
func _run_reachable(target: int, ranks: Dictionary, jokers: int) -> bool:
	for ace_high in [false, true]:
		var present := {}
		for r: int in ranks:
			present[14 if ace_high and r == 1 else r] = true
		var t := 14 if ace_high and target == 1 else target
		var low := 2 if ace_high else 1
		var high := 14 if ace_high else 13
		for s in range(low, t + 1):
			for e in range(t, high + 1):
				if e - s + 1 < Rules.MIN_MELD_SIZE:
					continue
				var nat := 0
				for r in range(s, e + 1):
					if present.has(r):
						nat += 1
				if (e - s + 1) - nat <= jokers:
					return true
	return false

## The longest unbroken run of naturals in `c`'s suit that includes `c`, trying
## the ace both low and high (never wrapping) and keeping whichever reaches
## further. Jokers are excluded — this only gathers cards the run needs no
## wildcard to bridge.
func _natural_run_for(c: Card, hand: Array[Card]) -> Array[Card]:
	var by_rank := {}
	for h in hand:
		if not h.is_joker and h.suit == c.suit and not by_rank.has(h.rank):
			by_rank[h.rank] = h
	var best: Array[Card] = []
	for ace_high in [false, true]:
		var eff := {}
		for r: int in by_rank:
			eff[14 if ace_high and r == 1 else r] = by_rank[r]
		var cr := 14 if ace_high and c.rank == 1 else c.rank
		var lo := cr
		while eff.has(lo - 1):
			lo -= 1
		var hi := cr
		while eff.has(hi + 1):
			hi += 1
		var block: Array[Card] = []
		for r in range(lo, hi + 1):
			block.append(eff[r])
		if block.size() > best.size():
			best = block
	return best
