class_name InstanceData
extends Resource

## ONE INSTANCE: a rule card revealed face up during a match (see MatchInstance,
## which is an instance in play). This holds its sheet row: name, Type, rule
## text and Effect — the commands it runs (see InstanceEffect).
##
## Source of truth is the `Instances` sheet of tools/Machiavelli Roguelike.xlsx,
## generated into data/instances/*.tres by tools/generate_instances.py. Edit the
## sheet, not these.

## The sheet's Name, slugified ("Coin Rush" -> &"coin_rush").
@export var id: StringName
@export var title: String = ""
## "reveal" or "ongoing" (the sheet's Type).
@export var kind: String = "reveal"
## The sheet's Description, ending in a full stop.
@export var text: String = ""
## The sheet's Effect: commands separated by `;` (see InstanceEffect). Empty =
## not playable yet.
@export var effect: String = ""
## Its row in the sheet, so the pool comes back in the sheet's order.
@export var order: int = 0
