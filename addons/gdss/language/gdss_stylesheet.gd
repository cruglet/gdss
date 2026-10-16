@tool
class_name GdssStylesheet
extends Node

signal parsed_changed
signal source_loaded(source: String)
signal saved

static var parsed: Dictionary[String, Dictionary] = {}
static var globals: Dictionary = {}
static var global_overrides: Dictionary = {}
static var _global_defaults: Dictionary = {}
static var _instance_vars: Dictionary = {}
static var _instance_defaults: Dictionary = {}
static var _instance_scheme_base: Dictionary = {}
static var _local_vars: Dictionary = {}
static var schemes: Dictionary[String, Dictionary] = {}
static var resources: Dictionary[String, Dictionary] = {}
static var config: Dictionary = {}
static var meta: Dictionary = {}
static var current_scheme: String = ""
var _last_modified: int = 0
var _saving: bool = false
static var _inst: GdssStylesheet

static var has_descendant_rules: bool = false


static func get_instance() -> GdssStylesheet:
	return _inst


static func refresh_descendant_flag() -> void:
	has_descendant_rules = _entries_use_combinators(parsed)


static func _entries_use_combinators(entries: Dictionary) -> bool:
	for key: String in entries:
		var entry: Variant = entries.get(key)
		if not entry is Dictionary:
			continue
		var container: Variant = (entry as Dictionary).get(GdssValue.DESCENDANTS_KEY)
		if container is Dictionary and not (container as Dictionary).is_empty():
			return true
		for nested_key: String in [GdssValue.CLASSES_KEY, GdssValue.VARIATIONS_KEY]:
			var nested: Variant = (entry as Dictionary).get(nested_key)
			if nested is Dictionary and _entries_use_combinators(nested as Dictionary):
				return true
	return false


static func get_class_names(node_type: String) -> PackedStringArray:
	var names: PackedStringArray = []
	if not parsed.has(node_type):
		return names
	_collect_class_names(parsed.get(node_type).get(GdssValue.CLASSES_KEY, {}), names)
	names.sort()
	return names


static func _collect_class_names(classes: Dictionary, names: PackedStringArray) -> void:
	for class_key: String in classes:
		if not names.has(class_key):
			names.append(class_key)
		var entry: Variant = classes.get(class_key)
		if entry is Dictionary:
			_collect_class_names((entry as Dictionary).get(GdssValue.CLASSES_KEY, {}), names)


func _ready() -> void:
	_inst = self


func initialize() -> void:
	_load_from_file()
	if Engine.is_editor_hint() and OS.is_debug_build() and Engine.has_singleton(&"EditorInterface"):
		var fs: Object = Engine.get_singleton(&"EditorInterface").call(&"get_resource_filesystem")
		if fs != null and not fs.is_connected(&"filesystem_changed", _on_editor_file_saved):
			fs.connect(&"filesystem_changed", _on_editor_file_saved)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and Engine.is_editor_hint():
		var modified: int = FileAccess.get_modified_time(GdssStorage.get_save_path())
		if modified == _last_modified:
			return
		_last_modified = modified
		_load_from_file()
		_force_viewport_redraw()


func _on_editor_file_saved() -> void:
	if _saving:
		return
	var modified: int = FileAccess.get_modified_time(GdssStorage.get_save_path())
	if modified == _last_modified:
		return
	_last_modified = modified
	_load_from_file()
	if Engine.is_editor_hint():
		_force_viewport_redraw()


func save_current(source: String) -> void:
	_saving = true
	GdssStorage.write_source(GdssStorage.get_save_path(), source)
	parsed = GdssParser.parse(source)
	refresh_descendant_flag()
	if GdssChecker.new().check_errors(source).is_empty():
		GdssStorage.write_cache(parsed, _global_defaults, _instance_defaults, _local_vars, schemes, meta, resources, config)
	_last_modified = FileAccess.get_modified_time(GdssStorage.get_save_path())
	saved.emit()
	parsed_changed.emit()
	if Engine.is_editor_hint():
		_force_viewport_redraw()
	_saving = false


func _force_viewport_redraw() -> void:
	if not Engine.has_singleton(&"EditorInterface"):
		return
	var viewport: Object = Engine.get_singleton(&"EditorInterface").call(&"get_editor_viewport_2d")
	if viewport == null:
		return
	var viewport_container: Control = (viewport as Node).get_parent() as Control
	if viewport_container == null:
		return
	var original_size: Vector2 = viewport_container.size
	viewport_container.size = original_size + Vector2(1, 0)
	viewport_container.size = original_size


func reload_active_file() -> void:
	_load_from_file()
	if Engine.is_editor_hint():
		_force_viewport_redraw()


func _load_from_file() -> void:
	if Engine.is_editor_hint():
		GdssStorage.sync_save_path()
	GdssParser.reset_known_states()
	_last_modified = FileAccess.get_modified_time(GdssStorage.get_save_path())
	var source: String = GdssStorage.read_source(GdssStorage.get_save_path())
	source_loaded.emit(source)
	parsed = GdssParser.parse(source)
	refresh_descendant_flag()
	parsed_changed.emit()


static func compile_for_export() -> PackedByteArray:
	var source: String = GdssStorage.read_source(GdssStorage.get_save_path())
	if source.is_empty():
		return PackedByteArray()
	var errors: Array[Array] = GdssChecker.new().check_errors(source)
	if not errors.is_empty():
		var first: Array = errors.front()
		push_error("[GDSS] Stylesheet has %d validation error(s); export aborted. First: line %d: %s" % [errors.size(), int(first.back()) + 1, str(first.front())])
		return PackedByteArray()
	var snapshot: Dictionary = {
		"globals": globals.duplicate(true),
		"global_defaults": _global_defaults.duplicate(true),
		"instance_defaults": _instance_defaults.duplicate(true),
		"local_vars": _local_vars.duplicate(true),
		"schemes": schemes.duplicate(true),
		"resources": resources.duplicate(true),
		"config": config.duplicate(true),
		"meta": meta.duplicate(true),
		"parsed": parsed.duplicate(true),
		"current_scheme": current_scheme,
	}
	var compiled_parsed: Dictionary = GdssParser.parse(source)
	var bundle: Dictionary = {
		"parsed": compiled_parsed,
		"global_defaults": _global_defaults.duplicate(true),
		"instance_defaults": _instance_defaults.duplicate(true),
		"local_vars": _local_vars.duplicate(true),
		"schemes": schemes.duplicate(true),
		"resources": resources.duplicate(true),
		"config": config.duplicate(true),
		"meta": meta.duplicate(true),
	}
	var bytes: PackedByteArray = GdssStorage.compiled_bytes(source, bundle, FileAccess.get_modified_time(GdssStorage.get_save_path()))
	_restore_statics(snapshot)
	return bytes


static func _restore_statics(snapshot: Dictionary) -> void:
	globals = snapshot.get("globals")
	_global_defaults = snapshot.get("global_defaults")
	_instance_defaults = snapshot.get("instance_defaults")
	_local_vars = snapshot.get("local_vars")
	meta = snapshot.get("meta")
	current_scheme = snapshot.get("current_scheme")
	parsed.clear()
	for key: String in (snapshot.get("parsed") as Dictionary):
		parsed.set(key, snapshot.get("parsed").get(key))
	schemes.clear()
	for key: String in (snapshot.get("schemes") as Dictionary):
		schemes.set(key, snapshot.get("schemes").get(key))
	resources.clear()
	for key: String in (snapshot.get("resources") as Dictionary):
		resources.set(key, snapshot.get("resources").get(key))
	config.clear()
	for key: String in (snapshot.get("config") as Dictionary):
		config.set(key, snapshot.get("config").get(key))
	refresh_descendant_flag()


static func resolve_scheme(name: String) -> Dictionary:
	var result: Dictionary = _global_defaults.duplicate(true)
	for key: String in _instance_scheme_base:
		result.set(key, _instance_scheme_base.get(key))
	for scheme_name: String in _scheme_chain(name):
		var deltas: Dictionary = schemes.get(scheme_name, {})
		for key: String in deltas:
			if key != GdssValue.SCHEME_PARENT_KEY:
				result.set(key, deltas.get(key))
	return result


static func _scheme_chain(name: String) -> PackedStringArray:
	var chain: PackedStringArray = []
	var current: String = name
	while not current.is_empty() and schemes.has(current) and not chain.has(current):
		chain.append(current)
		current = str((schemes.get(current, {}) as Dictionary).get(GdssValue.SCHEME_PARENT_KEY, ""))
	chain.reverse()
	return chain


static func scheme_keys() -> PackedStringArray:
	var keys: Dictionary = {}
	for scheme_name: String in schemes:
		for key: String in (schemes.get(scheme_name) as Dictionary):
			if key != GdssValue.SCHEME_PARENT_KEY:
				keys.set(key, true)
	return PackedStringArray(keys.keys())
