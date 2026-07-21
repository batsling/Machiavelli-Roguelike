class_name Enemy
extends RefCounted

## A designed roguelike opponent: a name, an AI personality (the three GreedyAI
## dials), and an optional hook that seeds its special mechanics onto the game
## once combat begins. The base class is a plain, strong opponent with no
## mechanic; each designed enemy is a subclass that sets its dials in _init and
## overrides on_combat_start.
##
## For now every enemy plays at the strongest skill (strength 1); only style and
## attention vary between enemies. The rogue ladder picks an enemy at random
## from Enemy.roster() each round.

var display_name := "Enemy"
var strength := 1.0
var style := 0.0
var attention := 1.0
## Planning depth (short-sighted → expert planner). Every designed enemy is an
## expert planner for now: it reworks as much of the table as it needs to lay
## down what it holds. See AIProfile.plan_budget and GreedyAI's deep planner.
var planning := 1.0

## Build the AIProfile GreedyAI drives this enemy with. Pass a seed for a
## reproducible (headless/test) game; omit it for a randomized live game.
func make_profile(seed_value: int = -1) -> AIProfile:
	return AIProfile.new(strength, style, attention, seed_value, planning)

## Called once after the game is dealt, before the first turn, to plant this
## enemy's mechanics on the freshly shuffled game. The base enemy does nothing.
func on_combat_start(_gm: GameManager) -> void:
	pass

## A short description of this enemy's mechanic for the game log, shown once
## when the round starts ("" for an enemy without one).
func mechanic_intro() -> String:
	return ""

## The deck_owner id of this enemy's own deck: the seat it sits in. In a rogue
## round there is exactly one opponent (this enemy), so its cards are the ones
## the combined stock tagged with that seat's id. A designed enemy corrupts only
## these — the player's own copies stay clean. Returns -1 if no opponent seat is
## found (shouldn't happen in a real round).
func own_deck_id(gm: GameManager) -> int:
	for p in gm.players:
		if p.is_opponent:
			return p.player_id
	return -1

## Every card in the game right after the deal — the stock plus every player's
## hand — so a combat-start hook can find its own deck's cards wherever they
## landed.
func all_dealt_cards(gm: GameManager) -> Array[Card]:
	var out: Array[Card] = gm.deck.cards.duplicate()
	for p in gm.players:
		out.append_array(p.hand)
	return out

## The enemy's special strategy move for the current (its own) turn, tried by
## GreedyAI once its ordinary plays are spent — a chance to act on a mechanic
## rather than just empty its hand. Returns a move Dictionary in GreedyAI's
## format ({cards, dest, text, ...}) or {} for "nothing special to do". The base
## enemy has no strategy.
func plan_strategy_move(_gm: GameManager) -> Dictionary:
	return {}

## True when this enemy fully drives its own turn this time, bypassing GreedyAI's
## ordinary play-or-draw entirely (the Billionaire declaring or being in Riichi).
## Checked at the start of the enemy's turn by both the UI and headless drivers.
func wants_control(_gm: GameManager) -> bool:
	return false

## Drive one complete turn for this enemy (only called when wants_control is
## true): the enemy stages/draws/advances the turn itself through GameManager and
## returns a small descriptor {"text": String, ...} for the log. The base enemy
## never claims control, so this is a stub.
func run_controlled_turn(_gm: GameManager) -> Dictionary:
	return {}

## Interceptor hook (see GameManager.play_interceptor): called right after any
## OTHER player commits a hand to the table, so a mechanic can claim that play
## and win outright. Returns true iff it ended the game (the Billionaire's ron).
## The base enemy never intercepts.
func on_opponent_commit(_gm: GameManager, _committer: PlayerState) -> bool:
	return false

## Strategy veto on the AI's own ordinary plays: GreedyAI's smart brain drops
## any candidate move this returns true for (unless the AI is racing to finish),
## so a designed enemy can refuse to make plays that work against its plan — the
## Billionaire holding a developing hand together as he builds toward a Riichi
## tenpai. The base enemy vetoes nothing.
func avoids_play(_gm: GameManager, _move: Dictionary) -> bool:
	return false

## Every designed enemy, in ladder order. The rogue mode draws from this pool.
static func roster() -> Array[Enemy]:
	var out: Array[Enemy] = []
	out.append(CuteSlime.new())
	out.append(SadisticBillionaire.new())
	return out

## Pick an enemy for a rogue round. `rng` (when given) keeps the choice
## reproducible; otherwise it is randomized.
static func random_enemy(rng: RandomNumberGenerator = null) -> Enemy:
	var pool := roster()
	var idx := 0
	if pool.size() > 1:
		idx = rng.randi_range(0, pool.size() - 1) if rng != null \
			else randi_range(0, pool.size() - 1)
	return pool[idx]
