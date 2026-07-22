class_name CuteSlime
extends Enemy

## The first designed enemy. She plays at full strength but is oblivious (keeps
## overlooking the plays that read the table) and quick (dumps cards as soon as
## she can). Her mechanic is the slime.
##
## At combat start she coats every card in her own deck in slime, giving them
## the Sticky effect. Because the combined stock holds one copy of each card per
## player, only her copy is slimed — of the two copies of any card in the game,
## exactly one carries slime, and only two of the four jokers (hers) are sticky.
## Slimed cards only stick to each other (see CardSet.sticky_cluster): a run of
## slimed cards on the table is one lump the player can't pick a single card out
## of — dragging one drags them all. The Cute Slime herself is immune
## (ignores_sticky on her PlayerState), so she slides her slime around freely.
##
## Slime strategy: once she has spent her ordinary plays for the turn, she uses
## her free movement to legally combine slimed cards — moving one slimed card
## next to the most valuable slimed card the player could still lift, sealing it
## in slime. Every combine keeps both groups valid and leaves no unmatched card
## behind, and she repeats it as long as it helps (still all within her one
## turn), always taking the move that guards her most versatile cards first —
## jokers, then the flexible 4-8s. She only ever moves on a real improvement, so
## she consolidates her slime, never shuffles in circles. The guard runs even on
## a turn with no ordinary play: she reworks the felt and then draws, keeping the
## rearrangement (GameManager.draw_and_end_turn), so she never wastes the guard.
##
## Ultimate: when her meter fills AND enough slimed cards can be gathered
## legally, she squeezes them into a heart picture on the felt (see the
## template block below) — sealing them away as one immovable lump, and her
## meter resets. She holds a full meter until the picture actually fits.

## Her ultimate: once her meter is full she gathers every slimed card she can
## and squeezes them into a heart picture on the felt. The slime comes from her
## own hand (naturals first; her joker wildcards only as a last resort) and from
## table groups that can legally spare it: the cards left behind in every donor
## group must still be a valid group, or nothing at all. The picture is a shape
## group (CardSet.set_shape) — valid as one connected patch — and its cards are
## sealed out of reach (only a joker can still leave, swapped out by the exact
## card it stands for). Sealing is a mechanic, not a play: the hand cards the
## picture swallows never count as her play for the turn, so she still draws
## (or plays a real card) to end it. Spending the ultimate resets her meter
## to zero. The picture is a hollow outline, not a filled block — every cell
## touches the next at an edge or a corner, so it still reads as one connected
## patch (the shape check counts a diagonal as connected).
## The template is grid cells, row by row:
##
##   heart (12)
##   . X . X .
##   X X . X X
##   X . . . X
##   . X . X .
##   . . X . .
##   . . X . .
const ULT_HEART: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(3, 0),
	Vector2i(0, 1), Vector2i(1, 1), Vector2i(3, 1), Vector2i(4, 1),
	Vector2i(0, 2), Vector2i(4, 2),
	Vector2i(1, 3), Vector2i(3, 3),
	Vector2i(2, 4),
	Vector2i(2, 5),
]

## The picture templates the ultimate can build. For now there is only the
## heart; the search still walks a list (grandest first) so more shapes can be
## added back later.
static func ult_templates() -> Array[Dictionary]:
	return [
		{"name": "heart", "cells": ULT_HEART},
	]

## Build one of her picture groups from a template and the cards to fill it
## (in template order). Needs exactly as many cards as the template has cells;
## returns null when the count doesn't fit.
static func build_shape_meld(template: Array[Vector2i], cards: Array[Card]) -> CardSet:
	if cards.size() != template.size():
		return null
	var cells := {}
	for i in template.size():
		cells[cards[i]] = template[i]
	var meld := CardSet.new()
	meld.set_shape(cells)
	return meld

func _init() -> void:
	display_name = "The Cute Slime"
	strength = 1.0     # strongest difficulty (for now every enemy is)
	style = 0.0        # quick
	attention = 0.0    # oblivious

func mechanic_intro() -> String:
	return "[b]%s[/b] slimes every card in her own deck " \
		% display_name \
		+ "(green splotch) — one copy of each, so only her half is sticky. " \
		+ "Slimed cards stick to each other, so a run of them is one lump — " \
		+ "dragging one drags them all. She oozes freely and combines her slime " \
		+ "to guard her most valuable cards (jokers, then the versatile 4-8s) " \
		+ "out of your reach. Once her ultimate meter fills she squeezes every " \
		+ "slimed card she can gather into a hollow heart on the felt, sealed " \
		+ "away — only a joker can leave it, swapped out by the exact card it " \
		+ "stands for."

## Slime every card that came from her own deck, wherever they sit right after
## the deal (the stock and every player's hand). Only her copies carry slime —
## the player's matching cards stay clean — so of the two copies of any card
## exactly one is sticky, and only her two of the four jokers. Deterministic
## (no RNG), so a seeded game slimes the same cards every replay. Her own seat
## is marked immune so she moves slimed cards freely.
func on_combat_start(gm: GameManager) -> void:
	var own := own_deck_id(gm)
	for p in gm.players:
		if p.is_opponent:
			p.ignores_sticky = true
	for c in all_dealt_cards(gm):
		if c.deck_owner == own:
			_slime(c)

func _slime(card: Card) -> void:
	if not card.has_effect(Card.Effect.STICKY):
		card.effects.append(Card.Effect.STICKY)

# --- Slime strategy ---------------------------------------------------------

## Her best guarding move right now: relocate one slimed card so it locks the
## most valuable slimed card the player could still lift, weighting each card by
## how badly she wants it kept away — jokers most, then the versatile 4-8s, then
## anything. The move keeps both groups valid and leaves no unmatched card, and
## she only makes it when it strictly improves her grip; otherwise {}. The turn
## loop calls this repeatedly, so she guards as much as legally helps in a turn.
func plan_strategy_move(gm: GameManager) -> Dictionary:
	if not gm.current_player_is_open():
		return {}
	# The ultimate outranks the guard: a charged meter plus enough gatherable
	# slime for a picture fires it (see the template block above).
	var ult := _plan_ultimate(gm)
	if not ult.is_empty():
		return ult
	var melds := gm.board.melds
	# The lock score each group contributes right now, so a candidate only has
	# to re-score the two groups it changes.
	var scores: Array[int] = []
	for m in melds:
		scores.append(_meld_lock_score(m.cards))
	var best: Dictionary = {}
	var best_gain := 0
	for i in melds.size():
		var m1: CardSet = melds[i]
		# Pictures and their extension lines are off-limits to the guard too.
		if not GreedyAI._plain_meld(m1):
			continue
		for c in m1.cards:
			# Jokers are what she guards, not what she shuffles; she oozes the
			# other slimed cards (hearts, diamonds) around them as bodyguards.
			if c.is_joker or not c.is_sticky():
				continue
			var rest: Array[Card] = m1.cards.duplicate()
			rest.erase(c)
			if not (rest.is_empty() or Rules.is_valid_meld(rest)):
				continue
			var rest_score := _meld_lock_score(rest)
			for j in melds.size():
				if j == i:
					continue
				var m2: CardSet = melds[j]
				if not GreedyAI._plain_meld(m2):
					continue
				var grown: Array[Card] = m2.cards.duplicate()
				grown.append(c)
				if not Rules.is_valid_meld(grown):
					continue
				var gain := rest_score + _meld_lock_score(grown) - scores[i] - scores[j]
				if gain > best_gain:
					best_gain = gain
					var moved: Array[Card] = [c]
					best = {"cards": moved, "dest": m2, "borrowed": moved, "strategy": true,
						"text": _guard_text(c, _has_joker(grown))}
	return best

# --- The ultimate -------------------------------------------------------------

## How many board relocations the ultimate may owe the leftover table: after
## she pulls slimed cards out of their groups, the remainder must be mendable
## within this many moves (GreedyAI's repair engine), or she takes less.
const ULT_REPAIR_BUDGET := 12

## The ultimate as a strategy move, or {} when the meter isn't full or no
## template can be filled legally. She prefers pulling slime OFF THE TABLE
## (sealing the most valuable cards — jokers, then the versatile 4-8s — away
## from the player), topping the picture up from her own hand: naturals first,
## her wildcard jokers only if nothing else reaches the count. Hand top-ups
## stay within the play cap's leftover budget, even though sealing never
## counts as playing (see GameManager.move_cards_to_new_shape) — so an ult-only
## turn still ends in a draw. GreedyAI.apply_move realizes the move through
## move_cards_to_new_shape (plus the leftover repair) and resets her meter.
func _plan_ultimate(gm: GameManager) -> Dictionary:
	var me := gm.current_player()
	# The meter builds live as she plays this turn, so read the projected charge
	# (what her turn-so-far already earned): that lets the ultimate fire the very
	# turn the bar completes, not a turn later.
	if gm.meter_max <= 0 or gm.projected_meter(me) < gm.meter_max:
		return {}
	var naturals: Array[Card] = []
	var jokers: Array[Card] = []
	for c in me.hand:
		if not c.is_sticky():
			continue
		if c.is_joker:
			jokers.append(c)
		else:
			naturals.append(c)
	var hand_cap := naturals.size() + jokers.size()
	if gm.max_plays_per_turn > 0:
		hand_cap = clampi(gm.max_plays_per_turn - gm.cards_played_this_turn(), 0, hand_cap)
	# A cheap ceiling on what could ever be gathered, so hopeless templates
	# are skipped before any repair work is spent.
	var table_slimed := 0
	for m in gm.board.melds:
		if not GreedyAI._plain_meld(m):
			continue
		for c in m.cards:
			if c.is_sticky():
				table_slimed += 1
	for template: Dictionary in ult_templates():
		var cells: Array[Vector2i] = template["cells"]
		var need := cells.size()
		if table_slimed + hand_cap < need:
			continue
		var gathered := _gather_table_slime(gm, need, need - mini(hand_cap, need))
		if gathered.is_empty():
			continue
		var pick: Array[Card] = (gathered["cards"] as Array[Card]).duplicate()
		var hand_needed: int = need - pick.size()
		var natural_count := mini(hand_needed, naturals.size())
		for i in natural_count:
			pick.append(naturals[i])
		for i in hand_needed - natural_count:
			pick.append(jokers[i])
		var placed := {}
		for i in cells.size():
			placed[pick[i]] = cells[i]
		return {"cards": pick, "dest": null, "shape_cells": placed,
			"shape_repair": gathered["final_melds"],
			"shape_repair_moved": gathered["moved"],
			"ult": true, "strategy": true,
			"text": "unleashes her ultimate — squeezes %d slimed cards into a %s on the felt"
				% [pick.size(), template["name"]]}
	return {}

## Gather up to `want` slimed cards off the table, never leaving leftovers
## that can't be legally rearranged. Phase 1 takes the free donations — cards
## whose groups stay valid (or empty) without them, chosen by the per-group
## subset DP below. Phase 2 cracks groups open one slimed card at a time,
## keeping only extractions GreedyAI's repair engine can still mend within
## ULT_REPAIR_BUDGET relocations. Returns {} when fewer than `min_take` cards
## are gatherable; otherwise {"cards": the extracted slime, "final_melds": the
## repaired leftover board (Array of Array[Card]), "moved": the cards the
## repair relocates} — the caller owes the table that rearrangement.
func _gather_table_slime(gm: GameManager, want: int, min_take: int) -> Dictionary:
	# Phase 1: the best free donations, at most one batch per group.
	var donations: Array = []
	for m in gm.board.melds:
		if not GreedyAI._plain_meld(m):
			continue
		var options := _donation_options(m)
		if not options.is_empty():
			donations.append(options)
	var dp := {0: {"score": 0, "picks": []}}
	for options: Array in donations:
		var next := {}
		for s: int in dp:
			_dp_offer(next, s, dp[s]["score"], dp[s]["picks"])
			for take: Array in options:
				var s2: int = s + take.size()
				if s2 > want:
					continue
				var picks: Array = (dp[s]["picks"] as Array).duplicate()
				picks.append(take)
				_dp_offer(next, s2, dp[s]["score"] + _donation_score(take), picks)
		dp = next
	var taken: Array[Card] = []
	for count in range(want, -1, -1):
		if dp.has(count):
			for take: Array in dp[count]["picks"]:
				for c: Card in take:
					taken.append(c)
			break
	# The leftover board as a model the repair engine understands.
	var model: Array = []
	for m in gm.board.melds:
		if not GreedyAI._plain_meld(m):
			continue
		var arr: Array[Card] = m.cards.duplicate()
		for c in taken:
			arr.erase(c)
		model.append(arr)
	# Phase 2: crack groups open a card at a time, most valuable slime first.
	if taken.size() < want:
		var singles: Array[Card] = []
		for arr: Array[Card] in model:
			for c in arr:
				if c.is_sticky():
					singles.append(c)
		singles.sort_custom(func(a: Card, b: Card) -> bool:
			return _importance(a) > _importance(b))
		for c in singles:
			if taken.size() >= want:
				break
			var arr := _model_arr_of(model, c)
			arr.erase(c)
			var probe := _copy_model(model)
			if GreedyAI._repair_board(probe, ULT_REPAIR_BUDGET, {}, [0]) == null:
				arr.append(c)  # this one can't leave legally — put it back
			else:
				taken.append(c)
	if taken.size() < min_take:
		return {}
	# Mend the leftover for real. Every phase-2 step was verified mendable, so
	# this can only be the no-op mend of an already-valid leftover, or the
	# same repair the last verification found.
	var repairs: Variant = GreedyAI._repair_board(model, ULT_REPAIR_BUDGET, {}, [0])
	if repairs == null:
		return {}
	var moved: Array[Card] = []
	for op: Dictionary in repairs:
		moved.append(op["card"])
	var final_melds: Array = []
	for arr: Array[Card] in model:
		if not arr.is_empty():
			final_melds.append(arr)
	return {"cards": taken, "final_melds": final_melds, "moved": moved}

## The model group currently holding this card.
func _model_arr_of(model: Array, c: Card) -> Array[Card]:
	for arr: Array[Card] in model:
		if arr.has(c):
			return arr
	var none: Array[Card] = []
	return none

## A working copy of a board model (fresh inner arrays, shared card refs).
func _copy_model(model: Array) -> Array:
	var out: Array = []
	for arr: Array[Card] in model:
		out.append(arr.duplicate())
	return out

## Every non-empty batch of slimed cards this group can give up legally: the
## cards left behind must still be a valid group, or nothing at all (only
## possible when the whole group was slimed). Enumerated exhaustively — a
## group holds at most 13 cards.
func _donation_options(m: CardSet) -> Array:
	var slimed: Array[Card] = []
	for c in m.cards:
		if c.is_sticky():
			slimed.append(c)
	var out: Array = []
	if slimed.is_empty() or slimed.size() > 13:
		return out
	for mask in range(1, 1 << slimed.size()):
		var take: Array[Card] = []
		for i in slimed.size():
			if mask & (1 << i):
				take.append(slimed[i])
		var rest: Array[Card] = m.cards.duplicate()
		for c in take:
			rest.erase(c)
		if rest.is_empty() or Rules.is_valid_meld(rest):
			out.append(take)
	return out

## Keep the best-scoring way to reach each table-card count.
func _dp_offer(dp: Dictionary, count: int, score: int, picks: Array) -> void:
	if not dp.has(count) or dp[count]["score"] < score:
		dp[count] = {"score": score, "picks": picks}

func _donation_score(take: Array) -> int:
	var score := 0
	for c: Card in take:
		score += _importance(c)
	return score

func _guard_text(c: Card, seals_joker: bool) -> String:
	if seals_joker:
		return "oozes %s over to seal a joker in slime" % c.label()
	return "oozes %s over to guard a card in slime" % c.label()

## The total importance of the locked slimed cards in one group: a slimed card
## is locked when a slimed card sits next to it in display order, so the player
## can't peel it off on its own. Jokers and the versatile 4-8s are worth more
## than other cards (see _importance).
func _meld_lock_score(cards: Array[Card]) -> int:
	var order := Rules.display_order(cards)
	var score := 0
	for i in order.size():
		if not order[i].is_sticky():
			continue
		var stuck := (i > 0 and order[i - 1].is_sticky()) \
			or (i < order.size() - 1 and order[i + 1].is_sticky())
		if stuck:
			score += _importance(order[i])
	return score

## How badly she wants a card kept away from the player: jokers most of all,
## then the versatile middle ranks 4-8 (the most flexible cards in play), then
## any other card. Aces and faces are edge ranks, so they rate no higher than
## the rest.
func _importance(c: Card) -> int:
	if c.is_joker:
		return 100
	if c.rank >= 4 and c.rank <= 8:
		return 8
	return 1

func _has_joker(cards: Array[Card]) -> bool:
	for c in cards:
		if c.is_joker:
			return true
	return false
