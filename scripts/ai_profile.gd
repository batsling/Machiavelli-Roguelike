class_name AIProfile
extends RefCounted

## Tunable opponent brain, set from the settings menu's three sliders. The axes
## are independent, so any combination is a valid personality.
##
## strength 0..1 (weak → strong): overall skill — how much of the move space
## the AI searches. It ramps through single lay-offs, two-card lay-offs, safe
## joker placement and table rearrangement, and at the top tier switches from
## the greedy first-legal-move search to a deck-counting brain that scores
## every legal move and plays the smartest one: it steals exposed jokers off
## the table, avoids feeding opponents easy lay-offs, holds cards worth keeping,
## and drops all of that to race for the finish once the endgame is close.
##
## style 0..1 (quick → conservative): how eagerly it commits cards. A quick AI
## dumps everything as soon as possible; a conservative one sits on its opening
## meld until the meld is big enough (or the game forces its hand) and refuses
## to lay off cards that still look useful with the rest of its hand (pairs,
## near-runs, jokers).
##
## attention 0..1 (oblivious → attentive): how reliably it notices a play in
## front of it. This is purely the blunder roll — an oblivious AI regularly
## overlooks its next play (cutting its streak short, or missing a turn), an
## attentive one never forgets. It is independent of strength: a strong but
## oblivious AI sees the clever plays yet keeps fumbling the obvious ones.
##
## GreedyAI with no profile behaves like strength 1 / style 0 / attention 1 and
## uses no randomness, so seeded headless games stay reproducible. Pass a seed
## here to make a profiled game reproducible too.

const MISS_CHANCE_AT_MOST_OBLIVIOUS := 0.3
## At or above this skill the AI drops the greedy first-legal-move search for
## the deck-counting, opponent-aware brain (GreedyAI._plan_smart_move).
const SMART_BRAIN_SKILL := 0.85

var strength := 1.0
var style := 0.0
var attention := 1.0
var rng := RandomNumberGenerator.new()

func _init(strength_value := 1.0, style_value := 0.0,
		attention_value := 1.0, seed_value := -1) -> void:
	strength = clampf(strength_value, 0.0, 1.0)
	style = clampf(style_value, 0.0, 1.0)
	attention = clampf(attention_value, 0.0, 1.0)
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()

## The blunder roll, capped at MISS_CHANCE_AT_MOST_OBLIVIOUS (30%) when fully
## oblivious. GreedyAI only consults it for plays that read the table — laying
## off onto an existing group or rearranging the table — never for laying a
## group straight from hand. So an oblivious AI still empties its hand into
## fresh groups reliably but keeps overlooking the plays that need it to notice
## what is already on the felt, cutting its streak short (or missing the turn).
func misses_move() -> bool:
	return rng.randf() < (1.0 - attention) * MISS_CHANCE_AT_MOST_OBLIVIOUS

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

## The top skill tier: instead of grabbing the first legal move, the AI counts
## the deck, enumerates every legal move and plays the highest-scoring one —
## stealing jokers, refusing to feed opponents, and holding key cards until the
## endgame forces its hand. See GreedyAI._plan_smart_move.
func uses_smart_brain() -> bool:
	return strength >= SMART_BRAIN_SKILL
