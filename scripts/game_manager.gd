extends Node
class_name GameManager

## Skeleton turn loop for an encounter: player + 2+ opponents, phantom-turn damage
## once a participant empties their hand. This is intentionally minimal — it's a
## scaffold for Claude Code to build out, not a finished system.

@export var players: Array[PlayerState] = []  # index 0 assumed to be the human player
@export var board_sets: Array[CardSet] = []

var turn_index: int = 0

func start_encounter(participants: Array[PlayerState]) -> void:
	players = participants
	turn_index = 0

func advance_turn() -> void:
	var current := players[turn_index]

	if current.is_finished:
		_apply_phantom_turn_damage(current)
	else:
		_take_real_turn(current)
		if current.hand_is_empty():
			current.is_finished = true

	turn_index = (turn_index + 1) % players.size()

func _take_real_turn(p: PlayerState) -> void:
	# TODO: hook up to actual player/AI decision-making (play card or reposition card).
	pass

func _apply_phantom_turn_damage(finished_player: PlayerState) -> void:
	# OPEN QUESTION: does phantom-turn damage stack across multiple finished opponents?
	# OPEN QUESTION: do finished opponents' abilities keep triggering on phantom turns?
	# Stub: only the human player (index 0) takes phantom-turn damage for now.
	if finished_player == players[0]:
		return
	var human := players[0]
	human.take_damage(1)  # placeholder damage value
