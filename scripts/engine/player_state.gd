class_name PlayerState
extends Resource

@export var player_id: int = -1
@export var display_name: String = ""
@export var is_opponent: bool = false
@export var health: int = 100          # unused by the vanilla engine; roguelike layer
@export var gold: int = 0              # unused by the vanilla engine; roguelike layer
@export var hand: Array[Card] = []
@export var is_finished: bool = false  # true once hand is emptied — enters phantom-turn state
# True once the player has "opened": committed a turn containing at least one
# valid meld built entirely from their own hand. Until then they may not add
# to or take from other melds on the table.
@export var has_opened: bool = false
# True for a player the slime (Sticky) effect does not bind: they move a slimed
# card on its own instead of dragging its whole cluster. The Cute Slime sets
# this on herself, so she alone slips her slime around freely.
@export var ignores_sticky: bool = false

func take_damage(amount: int) -> void:
	health = max(0, health - amount)

func heal(amount: int) -> void:
	health += amount

func hand_is_empty() -> bool:
	return hand.is_empty()
