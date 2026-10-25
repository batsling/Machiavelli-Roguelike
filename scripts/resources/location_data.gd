class_name LocationData
extends Resource

## ONE LOCATION: a rule card revealed face up during a match (see MatchEvent,
## which is a location in play). This holds what the card SAYS — its name, kind
## and rule text; what it DOES is code in GameManager, keyed by `id`.
##
## Source of truth is the `Locations` sheet of tools/Machiavelli Roguelike.xlsx,
## generated into data/locations/*.tres by tools/generate_locations.py. Edit the
## sheet, not these.

## The sheet's Name, slugified ("Coin Rush" -> &"coin_rush"). Matches a rule in
## MatchEvent.ID_NAMES; a row with no rule behind it stays out of the pool.
@export var id: StringName
@export var title: String = ""
## "on_reveal" or "ongoing" (the sheet's Type).
@export var kind: String = "on_reveal"
## The sheet's Description, ending in a full stop.
@export var text: String = ""
## Its row in the sheet, so the pool comes back in the sheet's order.
@export var order: int = 0
