@tool
class_name GdssSharedEntry
extends RefCounted

static var _records: Dictionary[String, Dictionary] = {}

var data: Dictionary
var scoped_vars: Dictionary
var style_static: Dictionary[String, Dictionary] = {}
var style_live: Dictionary[String, Array] = {}
var style_per_node: Dictionary[String, Array] = {}
var fully_shared: Dictionary[String, bool] = {}
var _full_values: Dictionary[String, Dictionary] = {}
var _full_generations: Dictionary[String, int] = {}
var nonstyle_live: Dictionary[String, Array] = {}
var global_only: Dictionary[String, Dictionary] = {}
var _global_generation: int = -1
var _global_vals: Dictionary[String, Dictionary] = {}
var _styled_props: Dictionary = {}
var _styled_props_ready: bool = false


func _init(p_data: Dictionary, p_scoped_vars: Dictionary) -> void:
	data = p_data
	scoped_vars = p_scoped_vars


static func find(selector: String, key: String) -> GdssSharedEntry:
	return _entries_for(selector).get(key)


static func store(selector: String, key: String, shared: GdssSharedEntry) -> void:
	_entries_for(selector).set(key, shared)


static func clear_all() -> void:
	_records.clear()


static func _entries_for(selector: String) -> Dictionary:
	var base: Dictionary = GdssStylesheet.parsed.get(selector, {})
	var record: Dictionary = _records.get(selector, {})
	if record.is_empty() or not is_same(record.get("base"), base):
		record = {"base": base, "entries": {}}
		_records.set(selector, record)
	return record.get("entries")


func mark_global_only(state: String, prop_name: String) -> void:
	if not global_only.has(state):
		global_only.set(state, {})
	global_only.get(state).set(prop_name, true)


func is_global_only(state: String, prop_name: String) -> bool:
	return global_only.has(state) and global_only.get(state).has(prop_name)


func global_values(state: String, generation: int) -> Dictionary:
	if generation != _global_generation:
		_global_generation = generation
		_global_vals = {}
	if not _global_vals.has(state):
		_global_vals.set(state, {})
	return _global_vals.get(state)


func full_values(state: String, generation: int) -> Variant:
	if _full_generations.get(state, -1) != generation:
		return null
	return _full_values.get(state)


func store_full_values(state: String, generation: int, values: Dictionary) -> void:
	values.make_read_only()
	_full_values.set(state, values)
	_full_generations.set(state, generation)


func styled_props() -> Dictionary:
	if not _styled_props_ready:
		_styled_props = GdssCascade.styled_props(data)
		_styled_props_ready = true
	return _styled_props
