class_name Instances
extends RefCounted

## Loads every InstanceData under data/instances/ once and serves it by id, in
## the sheet's order. The data is generated from the `Instances` sheet of
## tools/Machiavelli Roguelike.xlsx by tools/generate_instances.py.

const DIR := "res://data/instances/"

static var _by_id: Dictionary = {}   # StringName -> InstanceData
static var _ordered: Array[InstanceData] = []
static var _loaded := false

## Every instance in the sheet, in sheet order.
static func all() -> Array[InstanceData]:
	_load()
	return _ordered

## The instance with this id, or null if the sheet has no such row.
static func get_by_id(id: StringName) -> InstanceData:
	_load()
	return _by_id.get(id)

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var dir := DirAccess.open(DIR)
	if dir == null:
		push_error("[Instances] no folder '%s' — run tools/generate_instances.py" % DIR)
		return
	var names: Array[String] = []
	for fname in dir.get_files():
		# An exported build lists a converted resource as "x.tres.remap".
		fname = fname.trim_suffix(".remap")
		if fname.ends_with(".tres") or fname.ends_with(".res"):
			names.append(fname)
	names.sort()
	for fname in names:
		var loc := load(DIR + fname) as InstanceData
		if loc == null:
			push_error("[Instances] '%s' is not a InstanceData" % fname)
			continue
		if _by_id.has(loc.id):
			push_error("[Instances] two files claim id '%s'" % loc.id)
			continue
		_by_id[loc.id] = loc
		_ordered.append(loc)
	_ordered.sort_custom(func(a: InstanceData, b: InstanceData) -> bool: return a.order < b.order)
