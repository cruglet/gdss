@tool
class_name GDSS
extends RefCounted
## Looking for documentation on the plugin as a whole? See [GDSSDocumentation].


const DEBUG_MODE: bool = false
const DEBUG_WAS_VISIBLE: StringName = &"gdss_was_visible"
const CLASSES_META: StringName = &"gdss_classes"
const MODE_META: StringName = &"gdss_mode"

enum GdssMode {
	INHERIT,
	ENABLE,
	DISABLE,
}

enum Type {
	INT,
	FLOAT,
	BOOLEAN,
	COLOR,
	COMPOSITE,
	COMPOSITE4,
	CURSOR,
	TRANSITION_TYPE,
	TRANSITION_FUNC,
	ICON,
	FONT,
}

enum CursorType {
	ARROW,
	IBEAM,
	POINTING,
	CROSS,
	WAIT,
	BUSY,
	DRAG,
	CAN_DROP,
	FORBIDDEN,
	DISABLED = FORBIDDEN,
	VSIZE,
	HSIZE,
	BDIAGSIZE,
	FDIAGSIZE,
	MOVE,
	VSPLIT,
	HSPLIT,
	HELP,
}

enum TransitionType {
	EASE_IN,
	EASE_OUT,
	EASE_IN_OUT,
	EASE_OUT_IN,
}

enum TransitionFunc {
	LINEAR,
	SINE,
	QUINT,
	QUART,
	QUAD,
	EXPO,
	ELASTIC,
	CUBIC,
	CIRC,
	BOUNCE,
	BACK,
	SPRING
}

static var _db: GdssDB
static var _global_flush_scheduled: bool = false
static var _gpu_panels: int = -1
static var _runtime: Node
static var _scheme_tween: Tween


## Gets the value of a [b]global variable[/b] defined in GDSS.
## [br][br]
## Global variables are shared across the entire environment. If the variable
## does not exist, it returns the [param fallback] value.
## [codeblock]
## var my_color: Color = GDSS.get_global_var("theme_accent", Color.WHITE)
## [/codeblock]
static func get_global_var(name: String, fallback: Variant = null) -> Variant:
	return GdssInterpreter.globals.get(name, fallback)


## Sets the value of a [b]global variable[/b] and triggers a refresh.
## [br][br]
## This updates the global state and automatically notifies any objects or
## UI elements that are currently "listening" to or affected by this variable.
## [codeblock]
## GDSS.set_global_var("player_score", 100)
## [/codeblock]
static func set_global_var(name: String, value: Variant) -> void:
	GdssInterpreter.globals[name] = value
	_schedule_global_refresh()


## Restores a [b]global variable[/b] to the value declared in the stylesheet,
## discarding any runtime change made with [method set_global_var].
## [codeblock]
## GDSS.reset_global_var("theme_accent")
## [/codeblock]
static func reset_global_var(name: String) -> void:
	if GdssInterpreter._global_defaults.has(name):
		GdssInterpreter.globals[name] = GdssInterpreter._global_defaults.get(name)
	else:
		GdssInterpreter.globals.erase(name)
	_schedule_global_refresh()


static func _schedule_global_refresh() -> void:
	if _global_flush_scheduled:
		return
	if Engine.get_main_loop() == null:
		_flush_global_refresh()
		return
	_global_flush_scheduled = true
	_flush_global_refresh.call_deferred()


## Returns a copy of every currently-set global variable.
static func get_global_vars() -> Dictionary:
	return GdssInterpreter.globals.duplicate(true)


## Sets several global variables at once with a single refresh.
## [codeblock]
## GDSS.set_global_vars({"accent": Color.RED, "bg": Color.BLACK})
## [/codeblock]
static func set_global_vars(values: Dictionary) -> void:
	for key: String in values:
		GdssInterpreter.globals[key] = values[key]
	_schedule_global_refresh()


## Restores [b]every global variable[/b] to its stylesheet-declared value in a
## single refresh, discarding all runtime changes.
static func reset_global_vars() -> void:
	GdssInterpreter.globals = GdssInterpreter._global_defaults.duplicate(true)
	_schedule_global_refresh()


## Animates several global variables to new values over [param tween_time] seconds
## in one tween. Tweenable values interpolate; anything else snaps.
static func tween_global_vars(values: Dictionary, tween_time: float = 0.0, trans: TransitionFunc = TransitionFunc.SINE, ease: TransitionType = TransitionType.EASE_OUT) -> void:
	if tween_time <= 0.0 or Engine.get_main_loop() == null:
		set_global_vars(values)
		return
	var from: Dictionary = {}
	for key: String in values:
		from[key] = GdssInterpreter.globals.get(key, values[key])
	var tween: Tween = (Engine.get_main_loop() as SceneTree).create_tween()
	tween.set_trans(GdssPropHandler.tween_trans(trans))
	tween.set_ease(GdssPropHandler.tween_ease(ease))
	tween.tween_method(func(t: float) -> void:
		for key: String in values:
			GdssInterpreter.globals[key] = _lerp_value(from[key], values[key], t)
		_flush_global_refresh()
	, 0.0, 1.0, tween_time)


## Switches the active [b]scheme[/b], applying every variable it defines.
## [br][br]
## A scheme is a named set of variable overrides declared in the stylesheet with
## [code]@scheme name { ... }[/code]. Pass a [param tween_time] greater than zero
## to animate the change; tweenable values (colors, numbers, composites)
## interpolate while anything else snaps.
## [codeblock]
## GDSS.set_scheme("light", 0.25)
## [/codeblock]
static func set_scheme(name: String, tween_time: float = 0.0, trans: TransitionFunc = TransitionFunc.SINE, ease: TransitionType = TransitionType.EASE_OUT) -> void:
	if not GdssInterpreter.schemes.has(name):
		push_warning("[GDSS] Unknown scheme '%s'" % name)
		return
	var target: Dictionary = GdssInterpreter.resolve_scheme(name)
	var keys: PackedStringArray = GdssInterpreter.scheme_keys()
	GdssInterpreter.current_scheme = name
	_invalidate_texture_cache()
	if _scheme_tween != null and _scheme_tween.is_valid():
		_scheme_tween.kill()
		_scheme_tween = null
	if tween_time <= 0.0 or Engine.get_main_loop() == null:
		for key: String in keys:
			_apply_scheme_value(key, target[key])
		_schedule_global_refresh()
		_emit_scheme_changed(name)
		return
	var from: Dictionary = {}
	for key: String in keys:
		var current: Variant = _scheme_value(key)
		from[key] = current if current != null else target[key]
	_scheme_tween = (Engine.get_main_loop() as SceneTree).create_tween()
	_scheme_tween.set_trans(GdssPropHandler.tween_trans(trans))
	_scheme_tween.set_ease(GdssPropHandler.tween_ease(ease))
	_scheme_tween.tween_method(func(t: float) -> void:
		for key: String in keys:
			_apply_scheme_value(key, _lerp_value(from[key], target[key], t))
		_flush_global_refresh()
	, 0.0, 1.0, tween_time)
	_scheme_tween.finished.connect(func() -> void:
		for key: String in keys:
			_apply_scheme_value(key, target[key])
		_flush_global_refresh()
		_scheme_tween = null
	)
	_emit_scheme_changed(name)


## Returns the name of the currently active scheme, falling back to the theme's
## [code]default_scheme[/code] metadata, or an empty string if none is set.
static func get_scheme() -> String:
	if not GdssInterpreter.current_scheme.is_empty():
		return GdssInterpreter.current_scheme
	return get_default_scheme()


## Returns every scheme name declared in the stylesheet, in declaration order.
static func get_schemes() -> PackedStringArray:
	return PackedStringArray(GdssInterpreter.schemes.keys())


## Returns [code]true[/code] if a scheme named [param name] is declared.
static func has_scheme(name: String) -> bool:
	return GdssInterpreter.schemes.has(name)


## Reads the value a [param scheme] assigns to [param name], resolving against the
## base variable defaults so unspecified keys still return a value.
static func get_scheme_var(scheme: String, name: String, fallback: Variant = null) -> Variant:
	return GdssInterpreter.resolve_scheme(scheme).get(name, fallback)


## Reads a value from the theme's [code]@meta { ... }[/code] block.
static func get_theme_meta(key: String, fallback: Variant = null) -> Variant:
	return GdssInterpreter.meta.get(key, fallback)


## Returns a copy of the theme's full metadata dictionary.
static func get_theme_info() -> Dictionary:
	return GdssInterpreter.meta.duplicate(true)


## Returns the theme's declared default scheme, or an empty string if none.
static func get_default_scheme() -> String:
	return str(GdssInterpreter.meta.get("default_scheme", ""))


## Connects [param callable] to fire whenever the active scheme changes via
## [method set_scheme]; the callable receives the new scheme name. A convenience
## over reaching into the runtime autoload's [code]scheme_changed[/code] signal.
static func on_scheme_changed(callable: Callable) -> void:
	if is_instance_valid(_runtime) and _runtime.has_signal(&"scheme_changed"):
		_runtime.scheme_changed.connect(callable)


## Connects [param callable] to fire whenever global variables change (via
## [method set_global_var], a scheme switch, or a tween step).
static func on_globals_changed(callable: Callable) -> void:
	if is_instance_valid(_runtime) and _runtime.has_signal(&"globals_changed"):
		_runtime.globals_changed.connect(callable)


## Connects [param callable] to fire whenever the stylesheet is reparsed and
## reloaded at runtime.
static func on_parsed_reloaded(callable: Callable) -> void:
	if is_instance_valid(_runtime) and _runtime.has_signal(&"parsed_reloaded"):
		_runtime.parsed_reloaded.connect(callable)


static func _lerp_value(from_val: Variant, to_val: Variant, t: float) -> Variant:
	if from_val is Color and to_val is Color:
		return (from_val as Color).lerp(to_val as Color, t)
	if from_val is Vector4i and to_val is Vector4i:
		return Vector4i(Vector4(from_val as Vector4i).lerp(Vector4(to_val as Vector4i), t))
	if (from_val is float or from_val is int) and (to_val is float or to_val is int):
		var result: float = lerpf(float(from_val), float(to_val), t)
		if from_val is int and to_val is int:
			return int(round(result))
		return result
	return to_val


static func _invalidate_texture_cache() -> void:
	for method: GdssMethod in _get_gdss_methods().values():
		if method.returns_texture:
			method.clear_live_textures()


static func _emit_scheme_changed(name: String) -> void:
	if is_instance_valid(_runtime) and _runtime.has_signal(&"scheme_changed"):
		_runtime.scheme_changed.emit(name)


static func _emit_globals_changed() -> void:
	if is_instance_valid(_runtime) and _runtime.has_signal(&"globals_changed"):
		_runtime.globals_changed.emit()


static func _is_instance_scheme_key(key: String) -> bool:
	return GdssInterpreter._instance_defaults.has(key) and not GdssInterpreter._global_defaults.has(key)


static func _apply_scheme_value(key: String, value: Variant) -> void:
	if _is_instance_scheme_key(key):
		GdssInterpreter._instance_defaults[key] = value
	else:
		GdssInterpreter.globals[key] = value


static func _scheme_value(key: String) -> Variant:
	if _is_instance_scheme_key(key):
		return GdssInterpreter._instance_defaults.get(key)
	return GdssInterpreter.globals.get(key)


## Assigns an [b]instance-specific override[/b] for a GDSS variable on a Node.
## [br][br]
## If the [param node] is currently bound to GDSS, this function will
## automatically apply the new value, emit change signals, and queue a redraw
## if the node is a [CanvasItem].
## [codeblock]
## GDSS.set_instance_var(enemy_sprite, "modulate_color", Color.RED)
## [/codeblock]
static func set_instance_var(node: Node, name: String, value: Variant) -> void:
	var id: int = node.get_instance_id()
	if not GdssInterpreter._instance_vars.has(id):
		GdssInterpreter._instance_vars[id] = {}
	GdssInterpreter._instance_vars[id][name] = value
	if node is CanvasItem:
		GdssNodeHandler.refresh(node as CanvasItem)


## Retrieves the value of a variable for a [b]specific Node instance[/b].
## [br][br]
## This function checks for local overrides first. If no instance-specific
## value is found, it falls back to the default value defined in
## [code]_instance_defaults[/code].
## [codeblock]
## var speed = GDSS.get_instance_var(self, "move_speed", 200.0)
## [/codeblock]
static func get_instance_var(node: Node, name: String, fallback: Variant = null) -> Variant:
	var id: int = node.get_instance_id()
	if GdssInterpreter._instance_vars.has(id):
		return GdssInterpreter._instance_vars[id].get(name, fallback)
	return GdssInterpreter._instance_defaults.get(name, fallback)


## Resolves the [b]effective value[/b] GDSS uses for [param name] on [param node],
## following the same precedence as styling: a per-node instance override first,
## then the live global value, then the instance and global defaults, falling back
## to [param fallback]. Saves the caller from knowing whether [param name] is a
## global or an instance variable.
## [codeblock]
## var accent: Color = GDSS.get_var(my_button, "theme_accent", Color.WHITE)
## [/codeblock]
static func get_var(node: Node, name: String, fallback: Variant = null) -> Variant:
	if node != null:
		var overrides: Dictionary = GdssInterpreter._instance_vars.get(node.get_instance_id(), {})
		if overrides.has(name):
			return overrides.get(name)
	if GdssInterpreter.globals.has(name):
		return GdssInterpreter.globals.get(name)
	if GdssInterpreter._instance_defaults.has(name):
		return GdssInterpreter._instance_defaults.get(name)
	if GdssInterpreter._global_defaults.has(name):
		return GdssInterpreter._global_defaults.get(name)
	return fallback


## Clears a single GDSS instance override from [param node], reverting it to the
## stylesheet default, and reapplies its style.
static func clear_instance_var(node: Node, name: String) -> void:
	var id: int = node.get_instance_id()
	if GdssInterpreter._instance_vars.has(id):
		var overrides: Dictionary = GdssInterpreter._instance_vars.get(id)
		overrides.erase(name)
		if overrides.is_empty():
			GdssInterpreter._instance_vars.erase(id)
	if node is CanvasItem:
		GdssNodeHandler.refresh(node as CanvasItem)


## Clears all GDSS instance variables from a specific node and reapplies its style.
static func clear_instance_vars(node: Node) -> void:
	GdssInterpreter._instance_vars.erase(node.get_instance_id())
	if node is CanvasItem:
		GdssNodeHandler.refresh(node as CanvasItem)


## Forces [param node] to re-evaluate its GDSS styling immediately.
## [br][br]
## Re-checks the node's active visual state, so changes to properties GDSS cannot
## observe through a signal (such as a [Button]'s [code]disabled[/code] flag) take
## effect right away, then reapplies every resolved value and queues a redraw.
## Does nothing if [param node] is not a [CanvasItem] styled by GDSS.
## [codeblock]
## my_button.disabled = true
## GDSS.refresh(my_button)
## [/codeblock]
static func refresh(node: Node) -> void:
	if node == null or not node is CanvasItem:
		return
	var canvas_item: CanvasItem = node as CanvasItem
	GdssNodeHandler.refresh(canvas_item)
	var gdss_node: GdssNode = _get_gdss_nodes().get(canvas_item.get_class())
	if gdss_node != null:
		gdss_node.update_state(canvas_item)


## Returns the GDSS classes currently applied to [param node], in priority order.
## [codeblock]
## var classes: PackedStringArray = GDSS.get_classes(my_button)
## [/codeblock]
static func get_classes(node: Node) -> PackedStringArray:
	return node.get_meta(CLASSES_META, PackedStringArray()) as PackedStringArray


## Replaces every GDSS class on [param node] and reapplies its style.
## [codeblock]
## GDSS.set_classes(my_button, PackedStringArray(["GhostButton", "PillButton"]))
## [/codeblock]
static func set_classes(node: Node, classes: PackedStringArray) -> void:
	node.set_meta(CLASSES_META, classes)
	if node is CanvasItem:
		GdssNodeHandler.refresh(node as CanvasItem)


## Returns [code]true[/code] if [param gdss_class] is currently applied to [param node].
static func has_class(node: Node, gdss_class: String) -> bool:
	return get_classes(node).has(gdss_class)


## Adds [param gdss_class] to [param node] and reapplies its style.
## [br][br]
## Does nothing if the class is already present.
## [codeblock]
## GDSS.add_class(my_button, "PillButton")
## [/codeblock]
static func add_class(node: Node, gdss_class: String) -> void:
	var classes: PackedStringArray = get_classes(node)
	if classes.has(gdss_class):
		return
	classes.append(gdss_class)
	set_classes(node, classes)


## Removes [param gdss_class] from [param node] and reapplies its style.
## [br][br]
## Does nothing if the class is not present.
static func remove_class(node: Node, gdss_class: String) -> void:
	var classes: PackedStringArray = get_classes(node)
	var index: int = classes.find(gdss_class)
	if index == -1:
		return
	classes.remove_at(index)
	set_classes(node, classes)


## Toggles [param gdss_class] on [param node], returning its new state
## ([code]true[/code] if the class is now applied).
## [codeblock]
## var active: bool = GDSS.toggle_class(my_button, "Active")
## [/codeblock]
static func toggle_class(node: Node, gdss_class: String) -> bool:
	if has_class(node, gdss_class):
		remove_class(node, gdss_class)
		return false
	add_class(node, gdss_class)
	return true


## Removes all GDSS classes from [param node] and reapplies its style.
static func clear_classes(node: Node) -> void:
	if get_classes(node).is_empty():
		return
	set_classes(node, PackedStringArray())


## Returns [code]true[/code] if GDSS styling resolves to enabled on [param node],
## taking its [enum GdssMode] and that of its ancestors into account.
static func is_gdss_enabled(node: Node) -> bool:
	return resolve_mode(node)


## Resolves whether [param node] should be styled by GDSS.
## [br][br]
## Walks up from [param node] looking for an explicit [code]ENABLE[/code] or
## [code]DISABLE[/code] mode; nodes left on [code]INHERIT[/code] defer to their
## parent. With nothing set anywhere, the project's root default applies (disabled
## by default, so GDSS stays opt-in). A node carried over from an older project
## (in the legacy "gdss" group with no explicit mode) counts as enabled.
static func resolve_mode(node: Node) -> bool:
	if node == null:
		return false
	if node.is_in_group(GdssNodeHandler.GROUP) and get_gdss_mode(node) == GdssMode.INHERIT:
		return true
	var current: Node = node
	while current != null:
		if current.has_meta(MODE_META):
			var mode: int = int(current.get_meta(MODE_META))
			if mode == GdssMode.ENABLE:
				return true
			if mode == GdssMode.DISABLE:
				return false
		current = current.get_parent()
	return _root_default_enabled()


static func _root_default_enabled() -> bool:
	return int(ProjectSettings.get_setting("gdss/binding/root_default", 0)) == 1


## Returns the explicit [enum GdssMode] set on [param node] ([code]INHERIT[/code]
## if none).
static func get_gdss_mode(node: Node) -> GdssMode:
	return node.get_meta(MODE_META, GdssMode.INHERIT) as GdssMode


## Sets the [enum GdssMode] on [param node] and re-applies styling to it and its
## descendants. [code]INHERIT[/code] clears the explicit mode.
## [codeblock]
## GDSS.set_gdss_mode(my_panel, GDSS.GdssMode.ENABLE)
## [/codeblock]
static func set_gdss_mode(node: Node, mode: GdssMode) -> void:
	GdssNodeHandler.set_mode_state(node, mode, false)


## Enables GDSS styling on [param node] (sets its mode to [code]ENABLE[/code]).
## [codeblock]
## GDSS.enable_gdss(my_button)
## [/codeblock]
static func enable_gdss(node: Node) -> void:
	set_gdss_mode(node, GdssMode.ENABLE)


## Disables GDSS styling on [param node] (sets its mode to [code]DISABLE[/code]).
## [codeblock]
## GDSS.disable_gdss(my_button)
## [/codeblock]
static func disable_gdss(node: Node) -> void:
	set_gdss_mode(node, GdssMode.DISABLE)


static func gpu_panels_enabled() -> bool:
	if _gpu_panels == -1:
		if not ProjectSettings.has_setting("gdss/rendering/gpu_panels"):
			ProjectSettings.set_setting("gdss/rendering/gpu_panels", true)
		_gpu_panels = 1 if ProjectSettings.get_setting("gdss/rendering/gpu_panels", true) else 0
	return _gpu_panels == 1


static func _flush_global_refresh() -> void:
	_global_flush_scheduled = false
	var seen: Dictionary[int, bool] = {}
	for handler: GdssPropHandler in GdssNodeHandler.get_all_handlers():
		var item: CanvasItem = handler.ref
		if item == null:
			continue
		var id: int = item.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		item.queue_redraw()
	_emit_globals_changed()


static func _get_gdss_nodes() -> Dictionary[String, GdssNode]:
	return get_db().node_list


static func _get_gdss_methods() -> Dictionary[String, GdssMethod]:
	return get_db().method_list


static func get_db() -> GdssDB:
	if _db != null and not _db.node_list.is_empty():
		return _db
	var db: GdssDB = load("res://addons/gdss/db/db.tres")
	if db != null:
		_db = db
	if _db == null:
		_db = GdssDB.new()
	return _db
