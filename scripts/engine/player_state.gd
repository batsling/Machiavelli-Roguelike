class_name PlayerState
extends Resource

@export var player_id: int = -1
@export var display_name: String = ""
@export var is_opponent: bool = false
@export var hand: Array[Card] = []
# Energy ceiling for the current turn (see GameManager's energy rules): starts
# at the game's start_energy on this player's first turn and grows each turn
# after, up to the cap. Energy never carries over — every turn starts full at
# this ceiling, and what is left is max_energy minus the cost of the cards
# played from hand so far (GameManager.energy_left). 0 while energy is off.
@export var max_energy: int = 0
# How many turns this player has started this game; drives max_energy.
@export var turns_taken: int = 0
# Max energy added for good by instances this match (Overcharge's +2), on top of
# the turn-by-turn ceiling.
@export var bonus_energy: int = 0
# Coins earned this match (combo coins and the Coin Rush instance). A run banks the
# player's coins when the match ends (RunState.coins).
@export var coins: int = 0
# Ultimate-meter charge: rises each time this player commits a hand (see
# GameManager._charge_meter) toward the game's meter_max, and holds there once
# full. Zero at the start of every game. Off (meter_max 0) in a roguelike run.
@export var meter: int = 0
@export var is_finished: bool = false  # true once hand is emptied — enters phantom-turn state
# True once the player has "opened": committed a turn containing at least one
# valid meld built entirely from their own hand. Until then they may not add
# to or take from other melds on the table.
@export var has_opened: bool = false
# True for a player the slime (Sticky) effect does not bind: they move a slimed
# card on its own instead of dragging its whole cluster.
@export var ignores_sticky: bool = false

## This player's own deck: they draw only from it (see Deck). Set by
## GameManager.setup.
var deck: Deck = null

func hand_is_empty() -> bool:
	return hand.is_empty()
