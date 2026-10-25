class_name Locations
extends RefCounted

## Loads every LocationData under data/locations/ once and serves it by id, in
## the sheet's order. The data is generated from the `Locations` sheet of
## tools/Machiavelli Roguelike.xlsx by tools/generate_locations.py.

const DIR := "res://data/locations/"

static var _by_id: Dictionary = {}   # StringName -> LocationData
static var _ordered: Array[LocationData] = []
static var _loaded := false

## Every location in the sheet, in sheet order.
static func all() -> Array[LocationData]:
	_load()
	return _ordered

## The location with this id, or null if the sheet has no such row.
static func get_by_id(id: StringName) -> LocationData:
	_load()
	return _by_id.get(id)

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var dir := DirAccess.open(DIR)
	if dir == null:
		push_error("[Locations] no folder '%s' — run tools/generate_locations.py" % DIR)
		return
	var names: Array[String] = []
	for fname in dir.get_files():
		# An exported build lists a converted resource as "x.tres.remap".
		fname = fname.trim_suffix(".remap")
		if fname.ends_with(".tres") or fname.ends_with(".res"):
			names.append(fname)
	names.sort()
	for fname in names:
		var loc := load(DIR + fname) as LocationData
		if loc == null:
			push_error("[Locations] '%s' is not a LocationData" % fname)
			continue
		if _by_id.has(loc.id):
			push_error("[Locations] two files claim id '%s'" % loc.id)
			continue
		_by_id[loc.id] = loc
		_ordered.append(loc)
	_ordered.sort_custom(func(a: LocationData, b: LocationData) -> bool: return a.order < b.order)
