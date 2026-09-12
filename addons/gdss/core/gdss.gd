@tool
class_name GDSS
extends RefCounted
## Looking for documentation on the plugin as a whole? See [GDSSDocumentation].


const DEBUG_MODE: bool = false
const DEBUG_WAS_VISIBLE: StringName = &"gdss_was_visible"
const CLASSES_META: StringName = &"gdss_classes"
const MODE_META: StringName = &"gdss_mode"
const OVERRIDES_META: StringName = &"gdss_overrides"

enum GdssMode {
	INHERIT,
	ENABLE,
	DISABLE,
	DISABLE_SELF = 3,
	ENABLE_SELF = 4,
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
	VECTOR2,
	AUDIO,
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

enum BlurQuality {
	HIGH,
	LOW,
	OFF,
}

## Every runtime setting an [code]@config[/code] block may set, and the kind of value it takes.
const CONFIG_KEYS: Dictionary = {
	"animations_enabled": "bool",
	"animation_speed_scale": "float",
	"blur_quality": "BlurQuality",
	"transforms_enabled": "bool",
	"gpu_panels": "bool",
	"sfx_enabled": "bool",
	"sfx_bus": "string",
}

## When [code]false[/code] every transition applies instantly: state changes, event
## blocks, [method set_scheme] and [method tween_global_vars] all snap to their target,
## and anything mid-flight settles at once.
## [codeblock]
## GDSS.animations_enabled = false
## [/codeblock]
static var animations_enabled: bool = true:
	set(value):
		if animations_enabled == value:
			return
		animations_enabled = value
		_restyle_all()

## Multiplies every GDSS transition duration. [code]0.5[/code] plays everything twice as
## fast, [code]2.0[/code] half as fast, [code]0.0[/code] is instant. Clamped at zero.
static var animation_speed_scale: float = 1.0:
	set(value):
		var scaled: float = maxf(value, 0.0)
		if is_equal_approx(animation_speed_scale, scaled):
			return
		animation_speed_scale = scaled
		_restyle_all()

## Detail level for [code]blur()[/code] and [code]liquid_blur()[/code] backdrops.
## [br][br]
## [code]HIGH[/code] draws them as authored. [code]LOW[/code] drops the refraction and
## edge highlight, so [code]liquid_blur()[/code] renders as a plain blur.
## [code]OFF[/code] skips the backdrop copy altogether and fills with the tint colour
## alone, which is what the CPU fallback already does.
## [codeblock]
## GDSS.blur_quality = GDSS.BlurQuality.LOW
## [/codeblock]
static var blur_quality: BlurQuality = BlurQuality.HIGH:
	set(value):
		if blur_quality == value:
			return
		blur_quality = value
		_redraw_all()

## When [code]false[/code] the [code]transform_*[/code] properties are ignored and nodes
## keep their untransformed position and scale: a reduce-motion switch that leaves colour
## and size transitions alone.
static var transforms_enabled: bool = true:
	set(value):
		if transforms_enabled == value:
			return
		transforms_enabled = value
		_restyle_all()

## When [code]false[/code] no [code]sfx[/code] property plays. UI sound is suppressed in
## the editor regardless, so hovering a styled node while editing stays silent.
static var sfx_enabled: bool = true

## The audio bus every [code]sfx[/code] plays on. Point it at your own "UI" bus to give the
## player a volume slider for it. Unknown bus names fall back to the default bus.
static var sfx_bus: StringName = &"Master"

## Runtime switch for the GPU panel shader, initialised from the
## [code]gdss/rendering/gpu_panels[/code] project setting. Turn it off to draw panels with
## the CPU geometry fallback instead.
static var gpu_panels: bool:
	get():
		return gpu_panels_enabled()
	set(value):
		if gpu_panels_enabled() == value:
			return
		_gpu_panels = 1 if value else 0
		_redraw_all()

static var _db: GdssRegistry
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
	return GdssStylesheet.globals.get(name, fallback)


## Sets the value of a [b]global variable[/b] and triggers a refresh.
## [br][br]
## This updates the global state and automatically notifies any objects or
## UI elements that are currently "listening" to or affected by this variable.
## [codeblock]
## GDSS.set_global_var("player_score", 100)
## [/codeblock]
static func set_global_var(name: String, value: Variant) -> void:
	GdssStylesheet.globals.set(name, value)
	_schedule_global_refresh()


## Restores a [b]global variable[/b] to the value declared in the stylesheet,
## discarding any runtime change made with [method set_global_var].
## [codeblock]
## GDSS.reset_global_var("theme_accent")
## [/codeblock]
static func reset_global_var(name: String) -> void:
	if GdssStylesheet._global_defaults.has(name):
		GdssStylesheet.globals.set(name, GdssStylesheet._global_defaults.get(name))
	else:
		GdssStylesheet.globals.erase(name)
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
	return GdssStylesheet.globals.duplicate(true)


## Sets several global variables at once with a single refresh.
## [codeblock]
## GDSS.set_global_vars({"accent": Color.RED, "bg": Color.BLACK})
## [/codeblock]
static func set_global_vars(values: Dictionary) -> void:
	for key: String in values:
		GdssStylesheet.globals.set(key, values.get(key))
	_schedule_global_refresh()


## Restores [b]every global variable[/b] to its stylesheet-declared value in a
## single refresh, discarding all runtime changes.
static func reset_global_vars() -> void:
	GdssStylesheet.globals = GdssStylesheet._global_defaults.duplicate(true)
	_schedule_global_refresh()


## Animates several global variables to new values over [param tween_time] seconds
## in one tween. Tweenable values interpolate; anything else snaps.
static func tween_global_vars(values: Dictionary, tween_time: float = 0.0, trans: TransitionFunc = TransitionFunc.SINE, ease: TransitionType = TransitionType.EASE_OUT) -> void:
	var duration: float = scaled_duration(tween_time)
	if duration <= 0.0 or Engine.get_main_loop() == null:
		set_global_vars(values)
		return
	var from: Dictionary = {}
	for key: String in values:
		from.set(key, GdssStylesheet.globals.get(key, values.get(key)))
	var tween: Tween = (Engine.get_main_loop() as SceneTree).create_tween()
	tween.set_trans(GdssStylebox.tween_trans(trans))
	tween.set_ease(GdssStylebox.tween_ease(ease))
	tween.tween_method(func(t: float) -> void:
		for key: String in values:
			GdssStylesheet.globals.set(key, _lerp_value(from.get(key), values.get(key), t))
		_flush_global_refresh()
	, 0.0, 1.0, duration)


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
	if not GdssStylesheet.schemes.has(name):
		push_warning("[GDSS] Unknown scheme '%s'" % name)
		return
	var target: Dictionary = GdssStylesheet.resolve_scheme(name)
	var keys: PackedStringArray = GdssStylesheet.scheme_keys()
	GdssStylesheet.current_scheme = name
	_invalidate_texture_cache()
	if _scheme_tween != null and _scheme_tween.is_valid():
		_scheme_tween.kill()
		_scheme_tween = null
	var duration: float = scaled_duration(tween_time)
	if duration <= 0.0 or Engine.get_main_loop() == null:
		for key: String in keys:
			_apply_scheme_value(key, target.get(key))
		_schedule_global_refresh()
		_emit_scheme_changed(name)
		return
	var from: Dictionary = {}
	for key: String in keys:
		var current: Variant = _scheme_value(key)
		from.set(key, current if current != null else target.get(key))
	_scheme_tween = (Engine.get_main_loop() as SceneTree).create_tween()
	_scheme_tween.set_trans(GdssStylebox.tween_trans(trans))
	_scheme_tween.set_ease(GdssStylebox.tween_ease(ease))
	_scheme_tween.tween_method(func(t: float) -> void:
		for key: String in keys:
			_apply_scheme_value(key, _lerp_value(from.get(key), target.get(key), t))
		_flush_global_refresh()
	, 0.0, 1.0, duration)
	_scheme_tween.finished.connect(func() -> void:
		for key: String in keys:
			_apply_scheme_value(key, target.get(key))
		_flush_global_refresh()
		_scheme_tween = null
	)
	_emit_scheme_changed(name)


## Returns the name of the currently active scheme, falling back to the theme's
## [code]default_scheme[/code] metadata, or an empty string if none is set.
static func get_scheme() -> String:
	if not GdssStylesheet.current_scheme.is_empty():
		return GdssStylesheet.current_scheme
	return get_default_scheme()


## Returns every scheme name declared in the stylesheet, in declaration order.
static func get_schemes() -> PackedStringArray:
	return PackedStringArray(GdssStylesheet.schemes.keys())


## Returns [code]true[/code] if a scheme named [param name] is declared.
static func has_scheme(name: String) -> bool:
	return GdssStylesheet.schemes.has(name)


## Reads the value a [param scheme] assigns to [param name], resolving against the
## base variable defaults so unspecified keys still return a value.
static func get_scheme_var(scheme: String, name: String, fallback: Variant = null) -> Variant:
	return GdssStylesheet.resolve_scheme(scheme).get(name, fallback)


## Reads a value from the theme's [code]@meta { ... }[/code] block.
static func get_theme_meta(key: String, fallback: Variant = null) -> Variant:
	return GdssStylesheet.meta.get(key, fallback)


## Returns a copy of the theme's full metadata dictionary.
static func get_theme_info() -> Dictionary:
	return GdssStylesheet.meta.duplicate(true)


## Returns the theme's declared default scheme, or an empty string if none.
static func get_default_scheme() -> String:
	return str(GdssStylesheet.meta.get("default_scheme", ""))


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
	if from_val is Vector2 and to_val is Vector2:
		return (from_val as Vector2).lerp(to_val as Vector2, t)
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
	return GdssStylesheet._instance_defaults.has(key) and not GdssStylesheet._global_defaults.has(key)


static func _apply_scheme_value(key: String, value: Variant) -> void:
	if _is_instance_scheme_key(key):
		GdssStylesheet._instance_defaults.set(key, value)
	else:
		GdssStylesheet.globals.set(key, value)


static func _scheme_value(key: String) -> Variant:
	if _is_instance_scheme_key(key):
		return GdssStylesheet._instance_defaults.get(key)
	return GdssStylesheet.globals.get(key)


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
	if not GdssStylesheet._instance_vars.has(id):
		GdssStylesheet._instance_vars.set(id, {})
	GdssStylesheet._instance_vars.get(id).set(name, value)
	if node is CanvasItem:
		GdssNodeBinder.refresh_vars(node as CanvasItem)


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
	if GdssStylesheet._instance_vars.has(id):
		return GdssStylesheet._instance_vars.get(id).get(name, fallback)
	return GdssStylesheet._instance_defaults.get(name, fallback)


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
		var overrides: Dictionary = GdssStylesheet._instance_vars.get(node.get_instance_id(), {})
		if overrides.has(name):
			return overrides.get(name)
	if GdssStylesheet.globals.has(name):
		return GdssStylesheet.globals.get(name)
	if GdssStylesheet._instance_defaults.has(name):
		return GdssStylesheet._instance_defaults.get(name)
	if GdssStylesheet._global_defaults.has(name):
		return GdssStylesheet._global_defaults.get(name)
	return fallback


## Clears a single GDSS instance override from [param node], reverting it to the
## stylesheet default, and reapplies its style.
static func clear_instance_var(node: Node, name: String) -> void:
	var id: int = node.get_instance_id()
	if GdssStylesheet._instance_vars.has(id):
		var overrides: Dictionary = GdssStylesheet._instance_vars.get(id)
		overrides.erase(name)
		if overrides.is_empty():
			GdssStylesheet._instance_vars.erase(id)
	if node is CanvasItem:
		GdssNodeBinder.refresh_vars(node as CanvasItem)


## Clears all GDSS instance variables from a specific node and reapplies its style.
static func clear_instance_vars(node: Node) -> void:
	GdssStylesheet._instance_vars.erase(node.get_instance_id())
	if node is CanvasItem:
		GdssNodeBinder.refresh_vars(node as CanvasItem)


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
	GdssNodeBinder.refresh(canvas_item)
	var node_type: GdssNodeType = _get_node_types().get(canvas_item.get_class())
	if node_type != null:
		node_type.update_state(canvas_item)


## Sets [param node]'s visibility, playing its GDSS [code]on_show()[/code] /
## [code]on_hide()[/code] transition if one is defined. Unlike toggling
## [code]visible[/code] directly, this is interrupt-safe during an exit animation
## (it knows the intended visibility). Falls back to setting [code]visible[/code]
## for nodes GDSS isn't styling.
## [codeblock]
## GDSS.set_visible(my_menu, false) # plays on_hide(), then hides
## [/codeblock]
static func set_visible(node: Node, visible: bool) -> void:
	if node is CanvasItem:
		var stylebox: GdssStylebox = GdssNodeBinder.get_primary_stylebox(node as CanvasItem)
		if stylebox != null:
			stylebox._request_visible(visible)
			return
	if node != null:
		node.set("visible", visible)


## Shows [param node], playing its [code]on_show()[/code] transition if defined.
## See [method set_visible].
static func show(node: Node) -> void:
	set_visible(node, true)


## Hides [param node], playing its [code]on_hide()[/code] transition if defined
## (the node stays visible until the exit animation finishes). See [method set_visible].
static func hide(node: Node) -> void:
	set_visible(node, false)


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
		GdssNodeBinder.refresh(node as CanvasItem)


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


## Returns the freeform GDSS override text stored on [param node], or an empty
## string if none (or if the node uses dictionary-form overrides).
static func get_override_text(node: Node) -> String:
	var raw: Variant = node.get_meta(OVERRIDES_META, "")
	return raw if raw is String else ""


## Stores per-node style overrides as freeform GDSS text (property lines, with
## optional [code]:state { }[/code] blocks) and reapplies the node's style. The
## overrides layer on top of everything else - base type, variation, and classes.
## Methods, [code]$variables[/code], and [code]calc()[/code] all work. An empty
## string removes the overrides.
## [codeblock]
## GDSS.set_override_text(my_button, "bg_color: $accent\ncorner_radius: 16 16 16 16")
## [/codeblock]
static func set_override_text(node: Node, text: String) -> void:
	if text.strip_edges().is_empty():
		if node.has_meta(OVERRIDES_META):
			node.remove_meta(OVERRIDES_META)
	else:
		node.set_meta(OVERRIDES_META, text)
	if node is CanvasItem or node is Window:
		GdssNodeBinder.refresh(node)


## Returns the dictionary-form overrides stored on [param node] ({prop: value}),
## or an empty dictionary if none (or if the node uses text-form overrides).
static func get_prop_overrides(node: Node) -> Dictionary:
	var raw: Variant = node.get_meta(OVERRIDES_META, {})
	return (raw as Dictionary).duplicate() if raw is Dictionary else {}


## Sets a single per-node property override with a final value (no parsing) and
## reapplies the node's style. Coexists with classes/variations but not with
## text-form overrides - clear those first.
## [codeblock]
## GDSS.set_prop_override(my_button, "corner_radius", Vector4i(16, 16, 16, 16))
## [/codeblock]
static func set_prop_override(node: Node, prop: String, value: Variant) -> void:
	var raw: Variant = node.get_meta(OVERRIDES_META) if node.has_meta(OVERRIDES_META) else null
	if raw is String:
		push_warning("[GDSS] %s has text-form overrides; clear them before using set_prop_override." % node)
		return
	var overrides: Dictionary = (raw as Dictionary).duplicate() if raw is Dictionary else {}
	overrides.set(prop, value)
	node.set_meta(OVERRIDES_META, overrides)
	if node is CanvasItem or node is Window:
		GdssNodeBinder.refresh(node)


## Removes a single dictionary-form override from [param node] and reapplies its
## style. Removes the meta entirely when the last override is cleared.
static func clear_prop_override(node: Node, prop: String) -> void:
	var raw: Variant = node.get_meta(OVERRIDES_META) if node.has_meta(OVERRIDES_META) else null
	if not raw is Dictionary:
		return
	var overrides: Dictionary = (raw as Dictionary).duplicate()
	overrides.erase(prop)
	if overrides.is_empty():
		node.remove_meta(OVERRIDES_META)
	else:
		node.set_meta(OVERRIDES_META, overrides)
	if node is CanvasItem or node is Window:
		GdssNodeBinder.refresh(node)


## Removes every per-node override (text or dictionary form) from [param node]
## and reapplies its style.
static func clear_overrides(node: Node) -> void:
	if not node.has_meta(OVERRIDES_META):
		return
	node.remove_meta(OVERRIDES_META)
	if node is CanvasItem or node is Window:
		GdssNodeBinder.refresh(node)


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
## [br][br]
## [code]ENABLE_SELF[/code]/[code]DISABLE_SELF[/code] apply only to the node they
## are set on; descendants ignore them and keep resolving from further up the tree.
static func resolve_mode(node: Node) -> bool:
	if node == null:
		return false
	if node.is_in_group(GdssNodeBinder.GROUP) and get_gdss_mode(node) == GdssMode.INHERIT:
		return true
	var current: Node = node
	while current != null:
		if current.has_meta(MODE_META):
			var mode: int = int(current.get_meta(MODE_META))
			if mode == GdssMode.ENABLE:
				return true
			if mode == GdssMode.DISABLE:
				return false
			if current == node:
				if mode == GdssMode.ENABLE_SELF:
					return true
				if mode == GdssMode.DISABLE_SELF:
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
	GdssNodeBinder.set_mode_state(node, mode, false)


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


## Disables GDSS styling on [param node] itself only, leaving its descendants
## unaffected (sets its mode to [code]DISABLE_SELF[/code]).
## [codeblock]
## GDSS.disable_gdss_self(my_panel)
## [/codeblock]
static func disable_gdss_self(node: Node) -> void:
	set_gdss_mode(node, GdssMode.DISABLE_SELF)


## Enables GDSS styling on [param node] itself only, without forcing it onto its
## descendants (sets its mode to [code]ENABLE_SELF[/code]).
## [codeblock]
## GDSS.enable_gdss_self(my_panel)
## [/codeblock]
static func enable_gdss_self(node: Node) -> void:
	set_gdss_mode(node, GdssMode.ENABLE_SELF)


static func gpu_panels_enabled() -> bool:
	if _gpu_panels == -1:
		if not ProjectSettings.has_setting("gdss/rendering/gpu_panels"):
			ProjectSettings.set_setting("gdss/rendering/gpu_panels", true)
		_gpu_panels = 1 if ProjectSettings.get_setting("gdss/rendering/gpu_panels", true) else 0
	return _gpu_panels == 1


## Returns [param seconds] scaled by [member animation_speed_scale], or [code]0.0[/code]
## when [member animations_enabled] is off. Every GDSS transition runs through this, so
## tweens written by hand can follow the same settings.
static func scaled_duration(seconds: float) -> float:
	if not animations_enabled:
		return 0.0
	return maxf(seconds, 0.0) * animation_speed_scale


## Applies the stylesheet's [code]@config[/code] entries on top of whatever the settings are
## now. Keys the block leaves out are untouched.
static func apply_config(values: Dictionary) -> void:
	for key: String in values:
		var raw: String = str(values.get(key))
		match key:
			"animations_enabled":
				animations_enabled = config_bool(raw)
			"animation_speed_scale":
				animation_speed_scale = float(config_string(raw))
			"blur_quality":
				blur_quality = config_blur_quality(raw)
			"transforms_enabled":
				transforms_enabled = config_bool(raw)
			"gpu_panels":
				gpu_panels = config_bool(raw)
			"sfx_enabled":
				sfx_enabled = config_bool(raw)
			"sfx_bus":
				sfx_bus = StringName(config_string(raw))


## Restores every runtime setting to its built-in default and then re-applies the stylesheet's
## [code]@config[/code] block, which is the state GDSS starts a run in. Use it for an options
## menu's "reset to defaults".
static func reset_config() -> void:
	animations_enabled = true
	animation_speed_scale = 1.0
	blur_quality = BlurQuality.HIGH
	transforms_enabled = true
	sfx_enabled = true
	sfx_bus = &"Master"
	_gpu_panels = -1
	apply_config(GdssStylesheet.config)


static func config_bool(raw: String) -> bool:
	return ["true", "1"].has(config_string(raw).to_lower())


static func config_string(raw: String) -> String:
	return raw.strip_edges().trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'")


static func config_blur_quality(raw: String) -> BlurQuality:
	var index: int = BlurQuality.keys().find(config_string(raw).to_upper())
	return (index if index != -1 else BlurQuality.HIGH) as BlurQuality


## Plays a one-shot UI sound through GDSS's voice pool, the same way an [code]sfx[/code]
## property does. Honours [member sfx_enabled] and [member sfx_bus].
## [codeblock]
## GDSS.play_sfx(GDSS.get_resource("SFX_CLICK"))
## [/codeblock]
static func play_sfx(stream: AudioStream) -> void:
	if stream == null or not sfx_enabled or Engine.is_editor_hint():
		return
	if _runtime != null:
		_runtime.play_sfx(stream)


## Returns the resource a [code]@resources[/code] key points at, or [code]null[/code] when
## the key is unknown or its file is missing.
## [codeblock]
## var logo: Texture2D = GDSS.get_resource("LOGO")
## [/codeblock]
static func get_resource(key: String) -> Resource:
	var entry: Variant = GdssStylesheet.resources.get(key)
	if not entry is Dictionary:
		return null
	var method: GdssMethod = _get_gdss_methods().get((entry as Dictionary).get("method"))
	if method == null:
		return null
	var args: Array[Variant] = [(entry as Dictionary).get("path")]
	return method.call_method(args) as Resource


static func _redraw_all() -> void:
	for stylebox: GdssStylebox in GdssNodeBinder.get_all_styleboxes():
		stylebox._safe_redraw()


static func _restyle_all() -> void:
	for stylebox: GdssStylebox in GdssNodeBinder.get_all_styleboxes():
		if stylebox.ref != null:
			stylebox.reapply()
	_redraw_all()


static func _flush_global_refresh() -> void:
	# queue_redraw() is idempotent within a frame, so no per-item dedup set is needed
	# (a static multi-slot node redrawing twice is a free no-op, cheaper than hashing).
	_global_flush_scheduled = false
	var found_dead: bool = false
	for stylebox: GdssStylebox in GdssNodeBinder.get_all_styleboxes():
		var item: Node = stylebox.ref
		if item == null:
			found_dead = true
			continue
		stylebox.refresh_globals()
		if item is CanvasItem:
			(item as CanvasItem).queue_redraw()
		else:
			stylebox.emit_changed() # Window-derived nodes repaint via theme-changed notify
	if found_dead:
		GdssNodeBinder.mark_dirty()
	_emit_globals_changed()


static func _get_node_types() -> Dictionary[String, GdssNodeType]:
	return get_registry().node_list


static func _get_gdss_methods() -> Dictionary[String, GdssMethod]:
	return get_registry().method_list


static func get_registry() -> GdssRegistry:
	if _db != null and not _db.node_list.is_empty():
		return _db
	# Built entirely in code (props/components/methods + ThemeDB-derived nodes), so the
	# plugin ships no registry resources to load, keep in sync, or repopulate. Cached for the run.
	_db = GdssRegistry.new()
	_db.build_code()
	return _db
