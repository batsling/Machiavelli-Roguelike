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

## Build the AIProfile GreedyAI drives this enemy with. Pass a seed for a
## reproducible (headless/test) game; omit it for a randomized live game.
func make_profile(seed_value: int = -1) -> AIProfile:
	return AIProfile.new(strength, style, attention, seed_value)

## Called once after the game is dealt, before the first turn, to plant this
## enemy's mechanics on the freshly shuffled game. The base enemy does nothing.
func on_combat_start(_gm: GameManager) -> void:
	pass

## A short description of this enemy's mechanic for the game log, shown once
## when the round starts ("" for an enemy without one).
func mechanic_intro() -> String:
	return ""

## The enemy's special strategy move for the current (its own) turn, tried by
## GreedyAI once its ordinary plays are spent — a chance to act on a mechanic
## rather than just empty its hand. Returns a move Dictionary in GreedyAI's
## format ({cards, dest, text, ...}) or {} for "nothing special to do". The base
## enemy has no strategy.
func plan_strategy_move(_gm: GameManager) -> Dictionary:
	return {}

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
