class_name AIProfile
extends RefCounted

## Tunable opponent brain, set from the settings menu's skill/style graph.
##
## strength 0..1 (weak → strong): how much of the move space the AI searches
## and how often it simply misses a play it could have made. At full strength
## it sees everything GreedyAI can enumerate; at zero it regularly blanks.
##
## style 0..1 (quick → conservative): how eagerly it commits cards. A quick
## AI dumps everything as soon as possible; a conservative one sits on its
## opening meld until the meld is big enough (or the game forces its hand)
## and refuses to lay off cards that still look useful with the rest of its
## hand (pairs, near-runs, jokers).
##
## GreedyAI with no profile behaves like strength 1 / style 0 and uses no
## randomness, so seeded headless games stay reproducible. Pass a seed here
## to make a profiled game reproducible too.

const MISS_CHANCE_AT_WEAKEST := 0.6

var strength := 1.0
var style := 0.0
var rng := RandomNumberGenerator.new()

func _init(strength_value := 1.0, style_value := 0.0, seed_value := -1) -> void:
	strength = clampf(strength_value, 0.0, 1.0)
	style = clampf(style_value, 0.0, 1.0)
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()

## Rolled once per planned move; a weak AI regularly overlooks its next play,
## cutting its streak short for the turn (or missing the turn entirely).
func misses_move() -> bool:
	return rng.randf() < (1.0 - strength) * MISS_CHANCE_AT_WEAKEST

## Whether the AI searches table rearrangements (borrowing cards from melds).
func can_rearrange() -> bool:
	return strength >= 0.35

## Whether the AI tries two-card lay-offs — the "sees every possibility" tier.
func sees_pair_layoffs() -> bool:
	return strength >= 0.7

## Whether the AI points the jokers it plays at safe stand-ins: cards whose
## copies are mostly already visible on the table (or in its own hand), so
## opponents are unlikely to hold the exact card needed to swap-claim the
## joker. See GreedyAI._choose_joker_reps.
func picks_safe_joker_reps() -> bool:
	return strength >= 0.5

## Conservative AIs won't lay off cards that pair up with the rest of their
## hand, preferring to keep them for a bigger play later.
func holds_key_cards() -> bool:
	return style >= 0.5

## Minimum size of the first meld a conservative AI is willing to open with.
func opening_threshold() -> int:
	return Rules.MIN_MELD_SIZE + int(round(style * 2.0))
