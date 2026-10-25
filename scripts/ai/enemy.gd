class_name Enemy
extends RefCounted

## A roguelike opponent: a name, a one-line description, an AI personality (the
## four GreedyAI dials) and its own deck. The base class is a plain opponent with
## no mechanic — the three enemies of the current run map are all base enemies
## with different dials (see roster). A designed enemy with a special mechanic is
## a subclass that overrides the hooks below (on_combat_start, build_deck,
## plan_strategy_move, ...); none exist yet.

var display_name := "Enemy"
## One line for the run map and the info pop-up.
var description := ""
var strength := 1.0
var style := 0.0
var attention := 1.0
## Planning depth (short-sighted → expert planner). See AIProfile.plan_budget and
## GreedyAI's deep planner.
var planning := 1.0

func _init(name_value := "Enemy", description_value := "", strength_value := 1.0,
		style_value := 0.0, attention_value := 1.0, planning_value := 1.0) -> void:
	display_name = name_value
	description = description_value
	strength = strength_value
	style = style_value
	attention = attention_value
	planning = planning_value

## Build the AIProfile GreedyAI drives this enemy with. Pass a seed for a
## reproducible (headless/test) game; omit it for a randomized live game.
func make_profile(seed_value: int = -1) -> AIProfile:
	return AIProfile.new(strength, style, attention, seed_value, planning)

## The deck this enemy brings to the table, or null for a standard deck (52
## cards, +2 jokers when the run has jokers on). GameManager.setup tags the cards
## with the enemy's seat and shuffles it. Override to author an enemy's deck.
func build_deck(_include_jokers: bool) -> Deck:
	return null

## Called once after the game is dealt, before the first turn, to plant this
## enemy's mechanics on the freshly shuffled game. The base enemy does nothing.
func on_combat_start(_gm: GameManager) -> void:
	pass

## A short description of this enemy's mechanic for the game log, shown once
## when the match starts ("" for an enemy without one).
func mechanic_intro() -> String:
	return ""

## The enemy's special strategy move for the current (its own) turn, tried by
## GreedyAI once its ordinary plays are spent — a chance to act on a mechanic
## rather than just empty its hand. Returns a move Dictionary in GreedyAI's
## format ({cards, dest, text, ...}) or {} for "nothing special to do". The base
## enemy has no strategy.
func plan_strategy_move(_gm: GameManager) -> Dictionary:
	return {}

## True when this enemy fully drives its own turn this time, bypassing GreedyAI's
## ordinary play-or-draw entirely. Checked at the start of the enemy's turn by
## both the UI and headless drivers. The base enemy never does.
func wants_control(_gm: GameManager) -> bool:
	return false

## Drive one complete turn for this enemy (only called when wants_control is
## true): the enemy stages/draws/advances the turn itself through GameManager and
## returns a small descriptor {"text": String, ...} for the log.
func run_controlled_turn(_gm: GameManager) -> Dictionary:
	return {}

## Strategy veto on the AI's own ordinary plays: GreedyAI's smart brain drops
## any candidate move this returns true for (unless the AI is racing to finish),
## so a designed enemy can refuse plays that work against its plan. The base
## enemy vetoes nothing.
func avoids_play(_gm: GameManager, _move: Dictionary) -> bool:
	return false

## The enemies of the run map, in the order they are fought: three plain
## opponents that ramp up in skill. No special mechanics yet.
static func roster() -> Array[Enemy]:
	var out: Array[Enemy] = []
	out.append(Enemy.new("Scrap Drone",
		"A salvage bot running on old code. Lays what it holds and rarely looks at the table.",
		0.5, 0.0, 0.5, 0.0))
	out.append(Enemy.new("Rust Raider",
		"A scavenger who reads the table and will borrow a card or two to build a group.",
		0.8, 0.3, 0.8, 0.5))
	out.append(Enemy.new("Belt Warden",
		"Guards the jump gate. Counts cards, plans deep rearrangements, and races you out.",
		1.0, 0.4, 1.0, 1.0))
	return out
