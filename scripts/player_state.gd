class_name PlayerState
extends Resource

@export var player_id: int = -1
@export var display_name: String = ""
@export var is_opponent: bool = false
@export var health: int = 100          # unused by the vanilla engine; roguelike layer
@export var gold: int = 0              # unused by the vanilla engine; roguelike layer
@export var hand: Array[Card] = []
@export var is_finished: bool = false  # true once hand is emptied — enters phantom-turn state

func take_damage(amount: int) -> void:
	health = max(0, health - amount)

func heal(amount: int) -> void:
	health += amount

func hand_is_empty() -> bool:
	return hand.is_empty()
