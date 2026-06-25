@tool
class_name GdssPropHandler
extends StyleBox

static var _texture_cache: Dictionary = {}
static var _corner_start_angles: Array[float] = [PI, PI * 1.5, 0.0, PI * 0.5]
const _DEFAULT_SHADOW_COLOR: Color = Color(0, 0, 0, 0.4)

const _TRANSITION_FUNCS: Dictionary = {
	"LINEAR": Tween.TRANS_LINEAR, "SINE": Tween.TRANS_SINE, "QUINT": Tween.TRANS_QUINT,
	"QUART": Tween.TRANS_QUART, "QUAD": Tween.TRANS_QUAD, "EXPO": Tween.TRANS_EXPO,
	"ELASTIC": Tween.TRANS_ELASTIC, "CUBIC": Tween.TRANS_CUBIC, "CIRC": Tween.TRANS_CIRC,
	"BOUNCE": Tween.TRANS_BOUNCE, "BACK": Tween.TRANS_BACK, "SPRING": Tween.TRANS_SPRING,
}
const _EASE_TYPES: Dictionary = {
	"EASE_IN": Tween.EASE_IN, "EASE_OUT": Tween.EASE_OUT,
	"EASE_IN_OUT": Tween.EASE_IN_OUT, "EASE_OUT_IN": Tween.EASE_OUT_IN,
}


static func tween_trans(func_enum: GDSS.TransitionFunc) -> Tween.TransitionType:
	return _TRANSITION_FUNCS.get(GDSS.TransitionFunc.keys()[func_enum], Tween.TRANS_LINEAR)


static func tween_ease(type_enum: GDSS.TransitionType) -> Tween.EaseType:
	return _EASE_TYPES.get(GDSS.TransitionType.keys()[type_enum], Tween.EASE_IN_OUT)


var _slot_state: String = ""

var _ref_path: NodePath = NodePath()
# Typed Node (not CanvasItem) so Window-derived styled nodes (PopupMenu, Window,
# dialogs) can be handled alongside Controls. CanvasItem-only ops go through helpers.
var _ref_node: Node = null
var _ref_node_rt: Node = null
var _applying: bool = false

var _entry_cache: Dictionary = {}
var _entry_cache_dirty: bool = true
var _entry_cache_classes: PackedStringArray = []
var _entry_cache_variation: String = ""
# Set of prop names present in ANY state of the resolved entry. Lets _apply_overrides
# skip node properties the stylesheet never sets (e.g. the 8 offset_transform props on
# nodes that don't use them) instead of resolving + control.get-checking each one.
var _styled_props_cache: Dictionary = {}
var _styled_props_dirty: bool = true

var _animatable_cache: Dictionary = {}
var _animatable_dirty: bool = true

var _method_args_cache: Dictionary = {}

var _gdss_node: GdssNode = null

static var _shader: Shader = null
static var _blur_shader: Shader = null
static var _rr_cache: Dictionary = {}
static var _tri_cache: Dictionary = {}

var _gpu_material: ShaderMaterial = null
var _gpu_is_blur: bool = false
var _gpu_ci: RID = RID()
var _gpu_parent: RID = RID()
var _gpu_last: Dictionary = {}
var _gpu_quad: Rect2 = Rect2()
var _gpu_xform: Transform2D = Transform2D.IDENTITY
var _gpu_emitted: bool = false

var _style_vals_cache: Dictionary = {}
var _style_dynamic: Array[GdssProp] = []
var _style_vals_state: String = "￿"
var _nonstyle_dynamic: Array[GdssProp] = []
var _nonstyle_state: String = "￿"

var ref: Node:
	get:
		if Engine.is_editor_hint():
			if is_instance_valid(_ref_node):
				return _ref_node
			if _ref_path.is_empty():
				return null
			var tree: SceneTree = Engine.get_main_loop() as SceneTree
			if tree == null:
				return null
			var resolved: Node = tree.root.get_node_or_null(_ref_path)
			if is_instance_valid(resolved):
				_ref_node = resolved
				_connect_ref_signals(_ref_node)
			return resolved
		else:
			return _ref_node_rt if is_instance_valid(_ref_node_rt) else null
	set(v):
		_gdss_node = null
		var old: Node = _ref_node if Engine.is_editor_hint() else _ref_node_rt
		if old != null and old != v:
			_disconnect_ref_signals(old)
		if v == null:
			_ref_node = null
			_ref_node_rt = null
			_ref_path = NodePath()
			return
		if Engine.is_editor_hint():
			_ref_node = v
			if v.is_inside_tree():
				_ref_path = v.get_path()
		else:
			_ref_node_rt = v
		_connect_ref_signals(v)


# When _seeding, the setter just records the state (direct backing write, no transition
# or apply) so bind() can target a state inside its own bulk; reads stay direct field
# access (no getter), keeping the per-frame _draw / _get_state path fast.
var _seeding: bool = false
var current_state: String = "":
	set(s):
		if s == current_state:
			return
		if _seeding:
			current_state = s
			return
		var previous: String = current_state
		if not previous.is_empty():
			_start_transition(previous, s)
		current_state = s
		_apply_overrides(not previous.is_empty())
		if ref != null:
			_safe_redraw()


var _tweened_values: Dictionary[String, Variant] = {}
var _tween: Tween = null
var _state_sync_queued: bool = false

# on_show()/on_hide() event state. _self_toggle swallows the visibility_changed our
# own visible= writes fire (so re-showing to play an exit anim can't recurse).
# _last_visible filters parent-driven changes (where the node's own visible is unchanged).
var _self_toggle: bool = false
var _last_visible: bool = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _gpu_ci.is_valid():
			RenderingServer.free_rid(_gpu_ci)
			_gpu_ci = RID()
		if not Engine.is_editor_hint():
			return
		var interp: GdssInterpreter = GdssInterpreter.get_instance()
		if not is_instance_valid(interp):
			return
		var cb: Callable = Callable(self, &"_on_parsed_changed")
		if interp.parsed_changed.is_connected(cb):
			interp.parsed_changed.disconnect(cb)


func _connect_ref_signals(v: Node) -> void:
	if Engine.is_editor_hint():
		if not v.is_connected("renamed", _on_ref_renamed):
			v.connect("renamed", _on_ref_renamed)
		if not v.is_connected("tree_entered", _on_ref_tree_entered):
			v.connect("tree_entered", _on_ref_tree_entered)
		if not v.is_connected("tree_exiting", _on_ref_tree_exiting):
			v.connect("tree_exiting", _on_ref_tree_exiting)
		var interp: GdssInterpreter = GdssInterpreter.get_instance()
		if is_instance_valid(interp) and not interp.parsed_changed.is_connected(_on_parsed_changed):
			interp.parsed_changed.connect(_on_parsed_changed)
	else:
		# Only tree_exiting matters at runtime (frees the GPU child item for reparent);
		# the entered hook only refreshed the editor-only _ref_path, so it isn't connected.
		if not v.is_connected("tree_exiting", _on_ref_tree_exiting_rt):
			v.connect("tree_exiting", _on_ref_tree_exiting_rt)


func _disconnect_ref_signals(v: Node) -> void:
	if not is_instance_valid(v):
		return
	if Engine.is_editor_hint():
		if v.is_connected("renamed", _on_ref_renamed):
			v.disconnect("renamed", _on_ref_renamed)
		if v.is_connected("tree_entered", _on_ref_tree_entered):
			v.disconnect("tree_entered", _on_ref_tree_entered)
		if v.is_connected("tree_exiting", _on_ref_tree_exiting):
			v.disconnect("tree_exiting", _on_ref_tree_exiting)
	else:
		if v.is_connected("tree_exiting", _on_ref_tree_exiting_rt):
			v.disconnect("tree_exiting", _on_ref_tree_exiting_rt)


func _apply_dynamic_nonstyle(gdss_node: GdssNode, entry: Dictionary, state: String) -> void:
	if entry.is_empty() or _applying:
		return
	if _nonstyle_state != state:
		_classify_nonstyle(gdss_node, entry, state)
	if _nonstyle_dynamic.is_empty():
		return
	_applying = true
	var control: Variant = ref
	for prop: GdssProp in _nonstyle_dynamic:
		var val: Variant = _get_val_cached(prop.name, entry, state, prop.get_default_value())
		if val == null:
			val = prop.get_default_value()
		_apply_theme_prop(prop, control, gdss_node, val)
	_applying = false


func _classify_nonstyle(gdss_node: GdssNode, entry: Dictionary, state: String) -> void:
	_nonstyle_state = state
	_nonstyle_dynamic.clear()
	var prop_map: Dictionary[String, GdssProp] = gdss_node.get_props_by_name()
	var seen: Dictionary[String, bool] = {}
	for source_state: String in [state, "all"]:
		if not entry.has(source_state):
			continue
		for prop_name: String in entry[source_state]:
			if seen.has(prop_name):
				continue
			seen[prop_name] = true
			var prop: GdssProp = prop_map.get(prop_name)
			if prop == null or prop.category == GdssProp.Category.STYLE:
				continue
			if _is_dynamic_raw(_raw_entry_val(entry, state, prop_name)):
				_nonstyle_dynamic.append(prop)


func _on_ref_renamed() -> void:
	if is_instance_valid(_ref_node) and _ref_node.is_inside_tree():
		_ref_path = _ref_node.get_path()


func _on_ref_tree_entered() -> void:
	if is_instance_valid(_ref_node):
		_ref_path = _ref_node.get_path()
		GdssNodeHandler.apply_mode_tree.call_deferred(_ref_node)


func _on_ref_tree_exiting() -> void:
	_free_gpu_ci()
	if is_instance_valid(_ref_node) and _ref_node.is_inside_tree():
		_ref_path = _ref_node.get_path()


func _on_ref_tree_exiting_rt() -> void:
	# Reparent-safe: free the GPU child item (re-created on the next draw under the new
	# canvas parent), but KEEP _ref_node_rt so the handler still resolves while detached
	# and dead-handler pruning works. Authoritative teardown (registry slot, per-node
	# caches, instance vars) happens via the runtime's tree_exited hook ->
	# GdssNodeHandler.purge once the node is truly gone.
	_free_gpu_ci()


func _invalidate_entry_cache() -> void:
	_entry_cache_dirty = true
	_styled_props_dirty = true
	_entry_cache = {}
	_animatable_dirty = true
	_method_args_cache.clear()
	_gdss_node = null
	_style_vals_state = "￿"
	_style_vals_cache.clear()
	_style_dynamic.clear()
	_nonstyle_state = "￿"
	_nonstyle_dynamic.clear()


func _resolve_gdss_node() -> GdssNode:
	if _gdss_node != null:
		return _gdss_node
	var node: Node = ref
	if node == null:
		return null
	_gdss_node = GDSS._get_gdss_nodes().get(node.get_class())
	return _gdss_node


func _on_parsed_changed() -> void:
	if ref == null:
		return
	for method: GdssMethod in GDSS._get_gdss_methods().values():
		if method.returns_texture:
			method.clear_live_textures()
	_invalidate_entry_cache()
	_apply_overrides()
	emit_changed()
	if ref is CanvasItem:
		(ref as CanvasItem).queue_redraw()
	if Engine.is_editor_hint():
		ref.notify_property_list_changed()
		var parent: Node = ref.get_parent()
		if is_instance_valid(parent) and parent is CanvasItem:
			(parent as CanvasItem).queue_redraw()


func _clear_overrides() -> void:
	var node: Node = ref
	if node == null:
		return
	var gdss_node: GdssNode = _resolve_gdss_node()
	if gdss_node == null:
		return
	var control: Variant = node
	for prop: GdssProp in gdss_node.get_enabled_props():
		match prop.category:
			GdssProp.Category.COLOR:
				if prop.category_subproperties.is_empty():
					control.remove_theme_color_override(prop.name)
				else:
					if gdss_node.colors.has(prop.name):
						control.remove_theme_color_override(prop.name)
					for subprop: String in prop.category_subproperties:
						if gdss_node.colors.has(subprop):
							control.remove_theme_color_override(subprop)
			GdssProp.Category.CONST:
				control.remove_theme_constant_override(prop.name)
			GdssProp.Category.FONT_SIZE:
				control.remove_theme_font_size_override(prop.name)
			GdssProp.Category.ICON:
				control.remove_theme_icon_override(prop.name)


func _apply_overrides(clear: bool = true) -> void:
	var node: Node = ref
	if node == null or _applying:
		return
	var gdss_node: GdssNode = _resolve_gdss_node()
	if gdss_node == null:
		return
	if not GDSS.resolve_mode(node):
		return
	var control: Variant = node
	# Batch every add/remove theme-override into a single theme-changed notification
	# per node, instead of one propagation per override. Big win when many nodes bind
	# at once (scene instantiate / re-enter), where per-override propagation is O(depth).
	control.begin_bulk_theme_override()
	_apply_overrides_unwrapped(gdss_node, control, clear)
	control.end_bulk_theme_override()


# Core override application without the bulk wrapper, so bind() can fold the stylebox
# adds and the value overrides for a node into one shared bulk (one theme-changed
# notification per fresh bind). Callers guarantee ref / gdss_node / enabled mode.
func _apply_overrides_unwrapped(gdss_node: GdssNode, control: Variant, clear: bool) -> void:
	if _applying:
		return
	_applying = true
	if clear:
		_clear_overrides()
	var entry: Dictionary = _resolve_entry()
	var state: String = _get_state()
	var styled: Dictionary = _entry_styled_props(entry)
	for prop: GdssProp in gdss_node.get_enabled_props():
		if prop.category == GdssProp.Category.STYLE:
			if prop.name == "padding":
				var pad_raw: Variant = _get_val_cached(prop.name, entry, state, prop.get_default_value())
				var padding: Vector4 = Vector4(pad_raw if pad_raw != null else prop.get_default_value())
				set_content_margin(SIDE_LEFT, padding.x)
				set_content_margin(SIDE_RIGHT, padding.y)
				set_content_margin(SIDE_TOP, padding.z)
				set_content_margin(SIDE_BOTTOM, padding.w)
			continue
		if not styled.has(prop.name):
			continue
		# The parser fills every enabled prop with its default (for transitions/completion),
		# so the styled set is mostly injected defaults the stylesheet never wrote. Applying
		# one is always a no-op - either there's no override to set, or a state change already
		# cleared the old one - so skip it without resolving. Tweened props are exempt (their
		# live value is in _tweened_values, not the entry). The typeof guard keeps the equality
		# safe: a user value can be a method/sentinel (Dictionary/String) while the default is
		# a value type, and == across those types is a runtime error.
		if not _tweened_values.has(prop.name):
			var raw: Variant = _raw_entry_val(entry, state, prop.name)
			if raw == null:
				continue
			var def: Variant = prop.get_default_value()
			if typeof(raw) == typeof(def) and raw == def:
				continue
		var val: Variant = _get_val_cached(prop.name, entry, state, prop.get_default_value())
		if val == null:
			val = prop.get_default_value()
		_apply_theme_prop(prop, control, gdss_node, val)
	_applying = false


func _apply_theme_prop(prop: GdssProp, control: Variant, gdss_node: GdssNode, val: Variant) -> void:
	match prop.category:
		GdssProp.Category.COLOR:
			if val is Color:
				if prop.category_subproperties.is_empty():
					_override_color_if_custom(control, gdss_node, prop.name, val)
				else:
					if gdss_node.colors.has(prop.name):
						_override_color_if_custom(control, gdss_node, prop.name, val)
					for subprop: String in prop.category_subproperties:
						if gdss_node.colors.has(subprop):
							_override_color_if_custom(control, gdss_node, subprop, val)
		GdssProp.Category.CONST:
			if val is int or val is float:
				var theme_def: Variant = gdss_node.theme_defaults.get(prop.name, null)
				if theme_def is int and int(val) == int(theme_def):
					if control.has_theme_constant_override(prop.name):
						control.remove_theme_constant_override(prop.name)
					return
				if control.has_theme_constant_override(prop.name) and control.get_theme_constant(prop.name) == int(val):
					return
				control.add_theme_constant_override(prop.name, int(val))
		GdssProp.Category.FONT_SIZE:
			if val is int or val is float:
				var theme_def: Variant = gdss_node.theme_defaults.get(prop.name, null)
				if theme_def is int and int(val) == int(theme_def):
					if control.has_theme_font_size_override(prop.name):
						control.remove_theme_font_size_override(prop.name)
					return
				if control.has_theme_font_size_override(prop.name) and control.get_theme_font_size(prop.name) == int(val):
					return
				control.add_theme_font_size_override(prop.name, int(val))
		GdssProp.Category.FONT:
			if val is Font:
				var theme_def: Variant = gdss_node.theme_defaults.get(prop.name, null)
				if theme_def is Font and val == theme_def:
					return
				if control.has_theme_font_override(prop.name) and control.get_theme_font(prop.name) == val:
					return
				control.add_theme_font_override(prop.name, val as Font)
		GdssProp.Category.ICON:
			if val is Texture2D:
				if control.has_theme_icon_override(prop.name) and control.get_theme_icon(prop.name) == val:
					return
				control.add_theme_icon_override(prop.name, val)
		GdssProp.Category.NODE_PROPERTY:
			if prop.type == GDSS.Type.CURSOR:
				control.set("mouse_default_cursor_shape", _get_cursor_shape(str(val)))
				return
			if prop.name == "opacity":
				var mod: Color = control.modulate
				var alpha: float = float(val)
				if not is_equal_approx(mod.a, alpha):
					mod.a = alpha
					control.modulate = mod
				return
			# GDSS exposes the 4.7 Control transforms as "transform_*"; the real node
			# property is "offset_transform_*".
			var node_prop: String = "offset_" + prop.name if prop.name.begins_with("transform_") else prop.name
			if control.get(node_prop) != val:
				control.set(node_prop, val)


func _override_color_if_custom(control: Variant, gdss_node: GdssNode, key: String, val: Color) -> void:
	var theme_def: Variant = gdss_node.theme_defaults.get(key, null)
	if theme_def is Color and val.is_equal_approx(theme_def as Color):
		if control.has_theme_color_override(key):
			control.remove_theme_color_override(key)
		return
	if control.has_theme_color_override(key) and control.get_theme_color(key).is_equal_approx(val):
		return
	control.add_theme_color_override(key, val)


func _apply_single_override(prop: GdssProp, val: Variant) -> void:
	var node: Node = ref
	if node == null:
		return
	var gdss_node: GdssNode = _resolve_gdss_node()
	if gdss_node == null:
		return
	if val == null:
		val = prop.get_default_value()
	_apply_theme_prop(prop, node, gdss_node, val)


func reapply() -> void:
	_tweened_values.clear()
	_invalidate_entry_cache()
	_apply_overrides()
	emit_changed()


func refresh_globals() -> void:
	if _applying:
		return
	var node: Node = ref
	if node == null:
		return
	var gdss_node: GdssNode = _resolve_gdss_node()
	if gdss_node == null:
		return
	var entry: Dictionary = _resolve_entry()
	if entry.is_empty():
		return
	var state: String = _get_state()
	if _nonstyle_state != state:
		_classify_nonstyle(gdss_node, entry, state)
	if _nonstyle_dynamic.is_empty():
		return
	_applying = true
	var control: Variant = node
	control.begin_bulk_theme_override()
	for prop: GdssProp in _nonstyle_dynamic:
		var val: Variant = _get_val_cached(prop.name, entry, state, prop.get_default_value())
		if val == null:
			val = prop.get_default_value()
		_apply_theme_prop(prop, control, gdss_node, val)
	control.end_bulk_theme_override()
	_applying = false


func _get_cursor_shape(type: String) -> Control.CursorShape:
	match type:
		"ARROW": return Control.CursorShape.CURSOR_ARROW
		"IBEAM": return Control.CursorShape.CURSOR_IBEAM
		"POINTING": return Control.CursorShape.CURSOR_POINTING_HAND
		"CROSS": return Control.CursorShape.CURSOR_CROSS
		"WAIT": return Control.CursorShape.CURSOR_WAIT
		"BUSY": return Control.CursorShape.CURSOR_BUSY
		"DRAG": return Control.CursorShape.CURSOR_DRAG
		"CAN_DROP": return Control.CursorShape.CURSOR_CAN_DROP
		"FORBIDDEN", "DISABLED": return Control.CursorShape.CURSOR_FORBIDDEN
		"VSIZE": return Control.CursorShape.CURSOR_VSIZE
		"HSIZE": return Control.CursorShape.CURSOR_HSIZE
		"BDIAGSIZE": return Control.CursorShape.CURSOR_BDIAGSIZE
		"FDIAGSIZE": return Control.CursorShape.CURSOR_FDIAGSIZE
		"MOVE": return Control.CursorShape.CURSOR_MOVE
		"VSPLIT": return Control.CursorShape.CURSOR_VSPLIT
		"HSPLIT": return Control.CursorShape.CURSOR_HSPLIT
		"HELP": return Control.CursorShape.CURSOR_HELP
	return Control.CursorShape.CURSOR_ARROW


func _get_animatable_props() -> Dictionary:
	if not _animatable_dirty:
		return _animatable_cache
	_animatable_cache.clear()
	if ref == null:
		return _animatable_cache
	var gdss_node: GdssNode = _resolve_gdss_node()
	if gdss_node == null:
		return _animatable_cache
	for prop: GdssProp in gdss_node.get_enabled_props():
		match prop.type:
			GDSS.Type.COLOR, GDSS.Type.COMPOSITE4, GDSS.Type.FLOAT, GDSS.Type.INT, GDSS.Type.VECTOR2:
				_animatable_cache[prop.name] = prop
	_animatable_dirty = false
	return _animatable_cache


func _safe_redraw() -> void:
	var node: Node = ref
	if node == null:
		return
	if node is CanvasItem:
		(node as CanvasItem).queue_redraw()
	else:
		emit_changed() # Window-derived nodes redraw via theme-changed notification


func _sync_active_state() -> void:
	_state_sync_queued = false
	var node: Node = ref
	if not node is CanvasItem:
		return
	var gdss_node: GdssNode = _resolve_gdss_node()
	if gdss_node == null:
		return
	current_state = gdss_node.get_active_state(node as CanvasItem)


func _start_transition(from_state: String, to_state: String, timing_state: String = "", on_finished: Callable = Callable()) -> void:
	# timing_state selects which block supplies transition_time/func/type (defaults to
	# to_state; on_show/on_hide events pass their own key). on_finished fires after the
	# tween completes (or immediately if there's nothing to tween) - used to hide on on_hide.
	var ts: String = timing_state if not timing_state.is_empty() else to_state
	var transition_time: float = _get_parsed_val("transition_time", ts, 0.0)
	if transition_time <= 0.0 or ref == null or not ref.is_inside_tree():
		_tweened_values.clear()
		if on_finished.is_valid():
			on_finished.call()
		return

	var gdss_node: GdssNode = _resolve_gdss_node()
	var default_state: String = gdss_node.states[0] if gdss_node and not gdss_node.states.is_empty() else "all"
	var resolved_from: String = from_state if not from_state.is_empty() else default_state

	var trans: Tween.TransitionType = _TRANSITION_FUNCS.get(_get_parsed_val("transition_func", ts, "LINEAR"), Tween.TRANS_LINEAR)
	var ease: Tween.EaseType = _EASE_TYPES.get(_get_parsed_val("transition_type", ts, "EASE_IN_OUT"), Tween.EASE_IN_OUT)

	var tweener_count: int = 0
	var pending_tween: Tween = (Engine.get_main_loop() as SceneTree).create_tween()
	pending_tween.set_parallel(true)
	pending_tween.set_trans(trans)
	pending_tween.set_ease(ease)

	var animatable: Dictionary = _get_animatable_props()

	for prop_name: String in animatable:
		var prop: GdssProp = animatable[prop_name]
		var is_style: bool = prop.category == GdssProp.Category.STYLE

		var from_raw: Variant = _get_raw_parsed_val(prop_name, resolved_from)
		var to_raw: Variant = _get_raw_parsed_val(prop_name, to_state)

		if from_raw is Dictionary and (from_raw as Dictionary).has("__gdss_method__") and \
		   to_raw is Dictionary and (to_raw as Dictionary).has("__gdss_method__") and \
		   (from_raw as Dictionary)["__gdss_method__"] == (to_raw as Dictionary)["__gdss_method__"]:
			var mn: String = (from_raw as Dictionary)["__gdss_method__"]
			var method: GdssMethod = GDSS._get_gdss_methods().get(mn)
			if method != null and not method.get_tweenable_args().is_empty():
				var from_args: Array[Variant] = _resolve_method_args(from_raw as Dictionary)
				var to_args: Array[Variant] = _resolve_method_args(to_raw as Dictionary)
				var captured_prop: String = prop_name
				var captured_method: GdssMethod = method
				var node_id: int = ref.get_instance_id() if ref != null else -1
				pending_tween.tween_method(func(t: float) -> void:
					var interp_args: Array[Variant] = captured_method.interpolate_args(from_args, to_args, t)
					var result: Variant = captured_method.call_method(interp_args, node_id, "tween:" + captured_prop)
					if result != null:
						_tweened_values[captured_prop] = result
					_safe_redraw()
				, 0.0, 1.0, transition_time)
				tweener_count += 1
				continue
		
		match prop.type:
			GDSS.Type.COLOR:
				var fallback: Color = prop.get_default_value() if prop.get_default_value() is Color else Color.TRANSPARENT
				var from_val: Variant = _tweened_values.get(prop_name, _get_parsed_val(prop_name, resolved_from, fallback))
				var to_val: Variant = _get_parsed_val(prop_name, to_state, fallback)
				if not from_val is Color or not to_val is Color:
					continue
				var from: Color = from_val as Color
				var to: Color = to_val as Color
				if from == to:
					continue
				var captured: String = prop_name
				var captured_prop: GdssProp = prop
				_tweened_values[captured] = from
				pending_tween.tween_method(func(v: Color) -> void:
					_tweened_values[captured] = v
					if is_style:
						_safe_redraw()
					else:
						_apply_single_override(captured_prop, v)
				, from, to, transition_time)
				tweener_count += 1
			
			GDSS.Type.COMPOSITE4:
				var fallback: Vector4i = prop.get_default_value() if prop.get_default_value() is Vector4i else Vector4i.ZERO
				var composite_from_raw: Variant = _tweened_values.get(prop_name, _get_parsed_val(prop_name, resolved_from, fallback))
				var from: Vector4 = Vector4(composite_from_raw) if composite_from_raw is Vector4 else Vector4(composite_from_raw as Vector4i)
				var to: Vector4 = Vector4(_get_parsed_val(prop_name, to_state, fallback) as Vector4i)
				if from == to:
					continue
				var captured: String = prop_name
				var captured_prop: GdssProp = prop
				_tweened_values[captured] = from
				pending_tween.tween_method(func(v: Vector4) -> void:
					_tweened_values[captured] = v
					if is_style:
						_safe_redraw()
					else:
						_apply_single_override(captured_prop, v)
				, from, to, transition_time)
				tweener_count += 1

			GDSS.Type.VECTOR2:
				var fallback: Vector2 = prop.get_default_value() if prop.get_default_value() is Vector2 else Vector2.ZERO
				var from_val: Variant = _tweened_values.get(prop_name, _get_parsed_val(prop_name, resolved_from, fallback))
				var to_val: Variant = _get_parsed_val(prop_name, to_state, fallback)
				if not from_val is Vector2 or not to_val is Vector2:
					continue
				var from: Vector2 = from_val as Vector2
				var to: Vector2 = to_val as Vector2
				if from == to:
					continue
				var captured: String = prop_name
				var captured_prop: GdssProp = prop
				_tweened_values[captured] = from
				pending_tween.tween_method(func(v: Vector2) -> void:
					_tweened_values[captured] = v
					if is_style:
						_safe_redraw()
					else:
						_apply_single_override(captured_prop, v)
				, from, to, transition_time)
				tweener_count += 1

			GDSS.Type.FLOAT:
				var fallback: float = float(prop.get_default_value())
				var from: float = float(_tweened_values.get(prop_name, _get_parsed_val(prop_name, resolved_from, fallback)))
				var to: float = float(_get_parsed_val(prop_name, to_state, fallback))
				if from == to:
					continue
				var captured: String = prop_name
				var captured_prop: GdssProp = prop
				_tweened_values[captured] = from
				pending_tween.tween_method(func(v: float) -> void:
					_tweened_values[captured] = v
					if is_style:
						_safe_redraw()
					else:
						_apply_single_override(captured_prop, v)
				, from, to, transition_time)
				tweener_count += 1

			GDSS.Type.INT:
				var fallback: int = int(prop.get_default_value())
				var from: int = int(_tweened_values.get(prop_name, _get_parsed_val(prop_name, resolved_from, fallback)))
				var to: int = int(_get_parsed_val(prop_name, to_state, fallback))
				if from == to:
					continue
				var captured: String = prop_name
				var captured_prop: GdssProp = prop
				_tweened_values[captured] = from
				pending_tween.tween_method(func(v: float) -> void:
					_tweened_values[captured] = int(v)
					if is_style:
						_safe_redraw()
					else:
						_apply_single_override(captured_prop, int(v))
				, float(from), float(to), transition_time)
				tweener_count += 1


	if tweener_count == 0:
		pending_tween.kill()
		if on_finished.is_valid():
			on_finished.call()
		return

	if _tween:
		_tween.kill()
	_tween = pending_tween
	_tween.finished.connect(func() -> void:
		_tween = null
		_tweened_values.clear()
		_apply_overrides()
		_safe_redraw()
		if on_finished.is_valid():
			on_finished.call()
	)


# The visual state the node settles into after an enter animation / animates out of
# before an exit: the bound slot for static nodes, else the active interaction state.
func _resting_state(gdss_node: GdssNode, node: Node) -> String:
	if not _slot_state.is_empty():
		return _slot_state
	if not gdss_node.is_static and node is CanvasItem:
		var active: String = gdss_node.get_active_state(node as CanvasItem)
		if not active.is_empty():
			return active
	return gdss_node.states[0] if not gdss_node.states.is_empty() else "all"


# Runtime hook (connected to the node's visibility_changed via the runtime autoload).
func _on_node_visibility_changed() -> void:
	if _self_toggle:
		_self_toggle = false
		return
	var node: Control = ref as Control
	if node == null:
		return
	var vis: bool = node.visible
	if vis == _last_visible:
		return # an ancestor toggled; this node's own `visible` didn't change
	_last_visible = vis
	if vis:
		_play_show()
	else:
		_play_hide()


# Snap to the on_show() values, then animate to the resting state.
func _play_show() -> void:
	_play_event("on_show")


func _play_event(event_key: String) -> void:
	var node: Node = ref
	if node == null:
		return
	var gdss_node: GdssNode = _resolve_gdss_node()
	if gdss_node == null or not _resolve_entry().has(event_key):
		return
	_start_transition(event_key, _resting_state(gdss_node, node), event_key)
	_apply_overrides(false)


func _ev_pressed() -> void: _play_event("on_pressed")
func _ev_focus() -> void: _play_event("on_focus")
func _ev_blur() -> void: _play_event("on_blur")
func _ev_mouse_entered() -> void: _play_event("on_mouse_entered")
func _ev_mouse_exited() -> void: _play_event("on_mouse_exited")
func _ev_toggled(_on: bool) -> void: _play_event("on_toggled")


# Re-show the node so the exit animation can play, animate resting -> on_hide() values,
# then actually hide once the tween finishes.
func _play_hide() -> void:
	var node: Control = ref as Control
	if node == null:
		return
	var gdss_node: GdssNode = _resolve_gdss_node()
	if gdss_node == null or not _resolve_entry().has("on_hide") or not node.is_inside_tree():
		# No exit animation: make sure the node ends up hidden.
		if node != null and node.visible:
			_self_toggle = true
			node.visible = false
		return
	if not node.visible:
		_self_toggle = true
		node.visible = true
	_start_transition(_resting_state(gdss_node, node), "on_hide", "on_hide", func() -> void:
		if is_instance_valid(node) and node.visible:
			_self_toggle = true
			node.visible = false
	)


# Interrupt-safe programmatic visibility (GDSS.show/hide/set_visible). Because intent
# is explicit we don't depend on the visibility_changed signal to detect it.
func _request_visible(want_visible: bool) -> void:
	var node: Control = ref as Control
	if node == null:
		return
	if want_visible:
		if not node.visible:
			_self_toggle = true
			node.visible = true
		_last_visible = true
		_play_show()
	else:
		if not node.visible:
			return
		_last_visible = false
		_play_hide()


# Recursively searches a _classes tree for a given name, returning the entry or {}.
func _find_class_in_tree(classes: Dictionary, name: String) -> Dictionary:
	if classes.has(name):
		return classes[name]
	for key: String in classes:
		var nested: Dictionary = classes[key].get("_classes", {})
		if nested.is_empty():
			continue
		var found: Dictionary = _find_class_in_tree(nested, name)
		if not found.is_empty():
			return found
	return {}


# Merges override state dicts on top of base, skipping "_classes".
func _merge_entries(base: Dictionary, override: Dictionary) -> Dictionary:
	var merged: Dictionary = {}
	for state: String in base:
		if state == "_classes":
			continue
		merged[state] = base[state].duplicate() if base[state] is Dictionary else base[state]
	for state: String in override:
		if state == "_classes":
			continue
		if not merged.has(state):
			merged[state] = override[state].duplicate() if override[state] is Dictionary else override[state]
			continue
		if override[state] is Dictionary:
			for key: String in override[state]:
				merged[state][key] = override[state][key]
		else:
			merged[state] = override[state]
	merged["_classes"] = override.get("_classes", {})
	return merged


# Builds a merged entry dict by starting from parsed[ref.get_class()] and then
# layering each gdss_class in order (lowest to highest priority).
# Each name is looked up in the current entry's "_classes", allowing nesting.
## Set of prop names appearing in any state of the resolved entry (cached). A prop
## styled in ANY state stays in the set, so state-transition resets still run; only
## properties the stylesheet never sets are skipped by _apply_overrides.
func _entry_styled_props(entry: Dictionary) -> Dictionary:
	if not _styled_props_dirty:
		return _styled_props_cache
	_styled_props_cache.clear()
	for key: String in entry:
		if key == "_classes" or key == "_variations":
			continue
		var sd: Variant = entry[key]
		if sd is Dictionary:
			for prop_name: String in (sd as Dictionary):
				_styled_props_cache[prop_name] = true
	_styled_props_dirty = false
	return _styled_props_cache


func _resolve_entry() -> Dictionary:
	if ref == null:
		return {}
	var current_classes: PackedStringArray = ref.get_meta(GDSS.CLASSES_META, PackedStringArray()) as PackedStringArray
	var variation: String = String((ref as Control).theme_type_variation) if ref is Control else ""
	if not _entry_cache_dirty and _entry_cache_classes == current_classes and _entry_cache_variation == variation:
		return _entry_cache
	_styled_props_dirty = true # entry is being recomputed; its styled-prop set is stale
	var parsed: Dictionary[String, Dictionary] = GdssInterpreter.parsed
	var selector: String = ref.get_class()
	if not parsed.has(selector):
		return {}
	var entry: Dictionary = parsed[selector]
	var variations: Dictionary = parsed[selector].get("_variations", {})
	var has_variation: bool = not variation.is_empty() and variations.has(variation)
	if current_classes.is_empty() and not has_variation:
		_entry_cache = entry
		_entry_cache_classes = current_classes
		_entry_cache_variation = variation
		_entry_cache_dirty = false
		return entry
	# Layer order (lowest to highest priority): base type -> theme_type_variation
	# -> explicit gdss_classes. Classes win because they're the explicit runtime layer.
	if has_variation:
		entry = _merge_entries(entry, variations[variation])
	for gdss_class_name: String in current_classes:
		var override: Dictionary = _find_class_in_tree(parsed[selector].get("_classes", {}), gdss_class_name)
		if not override.is_empty():
			entry = _merge_entries(entry, override)
	_entry_cache = entry
	_entry_cache_classes = current_classes
	_entry_cache_variation = variation
	_entry_cache_dirty = false
	return entry


func _resolve_value(raw: Variant, fallback: Variant, state_key: String = "") -> Variant:
	if raw is Dictionary and (raw as Dictionary).has("__gdss_composite4__"):
		var parts: Array = (raw as Dictionary)["__gdss_composite4__"]
		return Vector4i(_resolve_composite_part(parts[0]), _resolve_composite_part(parts[1]), _resolve_composite_part(parts[2]), _resolve_composite_part(parts[3]))
	if raw is Dictionary and (raw as Dictionary).has("__gdss_calc__"):
		return _eval_calc((raw as Dictionary)["__gdss_calc__"])
	raw = _resolve_sentinel(raw, fallback)
	if raw is Dictionary:
		var d: Dictionary = raw as Dictionary
		if d.has("__gdss_method__"):
			return _call_method(d, fallback, state_key)
	if raw is String:
		var s: String = raw as String
		if not s.is_empty() and s.unicode_at(0) == 35: # '#'
			if Color.html_is_valid(s):
				return Color.html(s)
			return raw
		if not s.begins_with("__gdss_"):
			var named: Color = GdssInterpreter.parse_named_color(s, Color(-1, -1, -1, -1))
			if named.r != -1:
				return named
	return raw


func _eval_calc(node: Variant) -> float:
	if not node is Dictionary:
		return 0.0
	var d: Dictionary = node as Dictionary
	if d.has("calc_num"):
		return float(d["calc_num"])
	if d.has("calc_ref"):
		return _calc_ref_value(d["calc_ref"])
	if d.has("calc_neg"):
		return -_eval_calc(d["calc_neg"])
	if d.has("calc_op"):
		var l: float = _eval_calc(d["l"])
		var r: float = _eval_calc(d["r"])
		match d["calc_op"]:
			"+": return l + r
			"-": return l - r
			"*": return l * r
			"/": return l / r if r != 0.0 else 0.0
	return 0.0


func _calc_ref_value(token: String) -> float:
	var t: String = token
	if t.begins_with("$"):
		t = "__gdss_global__" + t.substr(1)
	var resolved: Variant = _resolve_sentinel(t, null)
	if resolved == null and token.begins_with("$"):
		resolved = _resolve_sentinel("__gdss_instance__" + token.substr(1), null)
		if resolved == null:
			resolved = _resolve_sentinel("__gdss_local__" + token.substr(1), null)
	if resolved is int or resolved is float:
		return float(resolved)
	if resolved is String and (resolved as String).is_valid_float():
		return float(resolved)
	return 0.0


func _resolve_composite_part(part: String) -> int:
	if part.is_valid_int():
		return int(part)
	var resolved: Variant = _resolve_sentinel(part, 0)
	if resolved is int or resolved is float:
		return int(resolved)
	if resolved is String and (resolved as String).is_valid_int():
		return int(resolved)
	return 0


func _resolve_method_args(descriptor: Dictionary, state_key: String = "") -> Array[Variant]:
	var method_name: String = descriptor["__gdss_method__"]
	var raw_args: Array = descriptor.get("args", [])
	var has_live_ref: bool = false
	for raw: Variant in raw_args:
		if raw is Dictionary:
			has_live_ref = true
			break
		var s: String = (raw as String).strip_edges()
		if s.begins_with("$") or s.begins_with("__gdss_global__") or s.begins_with("__gdss_instance__"):
			has_live_ref = true
			break
	var cache_key: String = ""
	if not has_live_ref:
		cache_key = method_name + "\n" + "\n".join(PackedStringArray(raw_args))
		if _method_args_cache.has(cache_key):
			return _method_args_cache[cache_key]
	var method: GdssMethod = GDSS._get_gdss_methods().get(method_name)
	var resolved: Array[Variant] = []
	for arg_index: int in raw_args.size():
		var param: GdssMethod.Param = method.parameters[arg_index] if method != null and arg_index < method.parameters.size() else null
		if raw_args[arg_index] is Dictionary:
			resolved.append(_resolve_value(raw_args[arg_index], null, state_key))
			continue
		var stripped: String = (raw_args[arg_index] as String).strip_edges()
		if stripped == "pass":
			resolved.append(method.parameters[arg_index].default_value if method != null and arg_index < method.parameters.size() else null)
		elif stripped.begins_with("__gdss_global__"):
			var key: String = stripped.substr("__gdss_global__".length())
			resolved.append(GdssInterpreter.globals.get(key, null))
		elif stripped.begins_with("__gdss_instance__"):
			var key: String = stripped.substr("__gdss_instance__".length())
			if ref != null and GdssInterpreter._instance_vars.has(ref.get_instance_id()):
				resolved.append(GdssInterpreter._instance_vars[ref.get_instance_id()].get(key, null))
			else:
				resolved.append(GdssInterpreter._instance_defaults.get(key, null))
		elif stripped.begins_with("$"):
			var key: String = stripped.substr(1)
			if GdssInterpreter.globals.has(key):
				resolved.append(GdssInterpreter.globals[key])
			elif ref != null and GdssInterpreter._instance_vars.has(ref.get_instance_id()):
				resolved.append(GdssInterpreter._instance_vars[ref.get_instance_id()].get(key, null))
			else:
				resolved.append(GdssInterpreter._instance_defaults.get(key, null))
		else:
			var unquoted: String = stripped.trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'")
			var resolved_arg: Variant = method._resolve_arg(unquoted) if method != null else unquoted
			if resolved_arg is String and param != null and param.type == GdssMethod.ParamType.COLOR:
				var named: Color = GdssInterpreter.parse_named_color(resolved_arg as String, Color(-1, -1, -1, -1))
				if named.r != -1:
					resolved_arg = named
			resolved.append(resolved_arg)
	if not has_live_ref:
		_method_args_cache[cache_key] = resolved
	return resolved


func _call_method(descriptor: Dictionary, fallback: Variant, state_key: String = "") -> Variant:
	var name: String = descriptor["__gdss_method__"]
	var method: GdssMethod = GDSS._get_gdss_methods().get(name)
	if method == null:
		return fallback
	var resolved_args: Array[Variant] = _resolve_method_args(descriptor, state_key)
	var node_id: int = ref.get_instance_id() if ref != null else -1
	if method.returns_texture:
		var result: Variant = method.call_method(resolved_args, node_id, state_key)
		return result if result != null else fallback
	return method.call_method(resolved_args, node_id, state_key)


func _get_parsed_val(key: String, state: String, fallback: Variant) -> Variant:
	var entry: Dictionary = _resolve_entry()
	if entry.is_empty():
		return fallback
	var raw: Variant = null
	if entry.has(state) and (entry[state] as Dictionary).has(key):
		raw = entry[state][key]
	elif entry.has("all") and (entry["all"] as Dictionary).has(key):
		raw = entry["all"][key]
	else:
		return fallback
	return _resolve_value(raw, fallback, state)


func _get_state() -> String:
	if not _slot_state.is_empty():
		return _slot_state
	if ref == null:
		return "all"
	if not current_state.is_empty():
		return current_state
	var gdss_node: GdssNode = _resolve_gdss_node()
	if gdss_node and not gdss_node.states.is_empty():
		return gdss_node.states[0]
	return "all"


func _resolve_sentinel(raw: Variant, fallback: Variant) -> Variant:
	if not raw is String:
		return raw
	var s: String = raw as String
	if not s.begins_with("__gdss_"):
		return raw
	if s.begins_with("__gdss_global__"):
		var name: String = s.substr("__gdss_global__".length())
		if GdssInterpreter.globals.has(name):
			return GdssInterpreter.globals[name]
		if GdssInterpreter._global_defaults.has(name):
			return GdssInterpreter._global_defaults[name]
		return fallback
	if s.begins_with("__gdss_instance__"):
		var name: String = s.substr("__gdss_instance__".length())
		if ref != null:
			var id: int = ref.get_instance_id()
			if GdssInterpreter._instance_vars.has(id) and GdssInterpreter._instance_vars[id].has(name):
				return GdssInterpreter._instance_vars[id][name]
		if GdssInterpreter._instance_defaults.has(name):
			return GdssInterpreter._instance_defaults[name]
		return fallback
	if s.begins_with("__gdss_local__"):
		var name: String = s.substr("__gdss_local__".length())
		if GdssInterpreter._local_vars.has(name):
			return GdssInterpreter._local_vars[name]
		return fallback
	if s.begins_with("__gdss_local_method__"):
		var name: String = s.substr("__gdss_local_method__".length())
		if GdssInterpreter._local_vars.has(name):
			return GdssInterpreter._local_vars[name]
		return fallback
	return raw


func _get_val(key: String, fallback: Variant = null) -> Variant:
	if ref == null:
		return fallback
	if _tweened_values.has(key):
		return _tweened_values[key]
	return _get_val_cached(key, _resolve_entry(), _get_state(), fallback)


func _get_val_cached(key: String, entry: Dictionary, state: String, fallback: Variant) -> Variant:
	if _tweened_values.has(key):
		return _tweened_values[key]
	if entry.is_empty():
		return fallback
	# Parsed raw values are never null, so null unambiguously means "key absent",
	# which lets us probe each dict once instead of has()+[].
	var raw: Variant = null
	var sd: Variant = entry.get(state)
	if sd is Dictionary:
		raw = (sd as Dictionary).get(key)
	if raw == null:
		var ad: Variant = entry.get("all")
		if ad is Dictionary:
			raw = (ad as Dictionary).get(key)
		if raw == null:
			return fallback
	return _resolve_value(raw, fallback, state)


func _get_raw_parsed_val(key: String, state: String) -> Variant:
	var entry: Dictionary = _resolve_entry()
	if entry.is_empty():
		return null
	var raw: Variant = null
	if entry.has(state) and entry[state].has(key):
		raw = entry[state][key]
	elif entry.has("all") and entry["all"].has(key):
		raw = entry["all"][key]
	else:
		return null
	raw = _resolve_sentinel(raw, null)
	if raw is String and (raw as String).begins_with("__gdss_local_method__"):
		var local_key: String = (raw as String).substr("__gdss_local_method__".length())
		return GdssInterpreter._local_vars.get(local_key, null)
	return raw


func _build_style_vals(gdss_node: GdssNode, entry: Dictionary, state: String) -> Dictionary:
	if not _tweened_values.is_empty():
		if _style_vals_state != state or _style_vals_cache.is_empty():
			var fresh: Dictionary = {}
			for prop: GdssProp in gdss_node.get_style_props():
				var fv: Variant = _get_val_cached(prop.name, entry, state, prop.get_default_value())
				fresh[prop.name] = fv if fv != null else prop.get_default_value()
			return fresh
		var out: Dictionary = _style_vals_cache.duplicate()
		for prop: GdssProp in _style_dynamic:
			var dv: Variant = _get_val_cached(prop.name, entry, state, prop.get_default_value())
			out[prop.name] = dv if dv != null else prop.get_default_value()
		for prop: GdssProp in gdss_node.get_style_props():
			if _tweened_values.has(prop.name):
				out[prop.name] = _tweened_values[prop.name]
		return out
	if _style_vals_state != state:
		_style_vals_cache.clear()
		_style_dynamic.clear()
		_style_vals_state = state
		for prop: GdssProp in gdss_node.get_style_props():
			var rv: Variant = _get_val_cached(prop.name, entry, state, prop.get_default_value())
			_style_vals_cache[prop.name] = rv if rv != null else prop.get_default_value()
			if _is_dynamic_raw(_raw_entry_val(entry, state, prop.name)):
				_style_dynamic.append(prop)
		return _style_vals_cache
	for prop: GdssProp in _style_dynamic:
		var dv: Variant = _get_val_cached(prop.name, entry, state, prop.get_default_value())
		_style_vals_cache[prop.name] = dv if dv != null else prop.get_default_value()
	return _style_vals_cache


func _raw_entry_val(entry: Dictionary, state: String, key: String) -> Variant:
	var sd: Variant = entry.get(state)
	if sd is Dictionary:
		var v: Variant = (sd as Dictionary).get(key)
		if v != null:
			return v
	var ad: Variant = entry.get("all")
	if ad is Dictionary:
		var v2: Variant = (ad as Dictionary).get(key)
		if v2 != null:
			return v2
	return null


func _is_dynamic_raw(raw: Variant) -> bool:
	if raw is String:
		var s: String = raw as String
		return s.begins_with("__gdss_global__") or s.begins_with("__gdss_instance__")
	if raw is Dictionary:
		var d: Dictionary = raw as Dictionary
		if d.has("__gdss_composite4__"):
			for part: Variant in d["__gdss_composite4__"]:
				if part is String and ((part as String).begins_with("__gdss_global__") or (part as String).begins_with("__gdss_instance__")):
					return true
			return false
		if d.has("__gdss_calc__"):
			return _calc_has_dynamic_ref(d["__gdss_calc__"])
		if not d.has("__gdss_method__"):
			return false
		for arg: Variant in d.get("args", []):
			if not arg is String:
				continue
			var a: String = (arg as String).strip_edges()
			if a.begins_with("__gdss_global__") or a.begins_with("__gdss_instance__") or a.begins_with("$"):
				return true
	return false


func _calc_has_dynamic_ref(node: Variant) -> bool:
	if not node is Dictionary:
		return false
	var d: Dictionary = node as Dictionary
	if d.has("calc_ref"):
		var r: String = d["calc_ref"]
		return r.begins_with("__gdss_global__") or r.begins_with("__gdss_instance__") or r.begins_with("$")
	if d.has("calc_neg"):
		return _calc_has_dynamic_ref(d["calc_neg"])
	if d.has("calc_op"):
		return _calc_has_dynamic_ref(d["l"]) or _calc_has_dynamic_ref(d["r"])
	return false


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if ref == null:
		return
	var gdss_node: GdssNode = _resolve_gdss_node()
	if gdss_node == null:
		return
	if not Engine.is_editor_hint() and ref is CanvasItem and _slot_state.is_empty() and not gdss_node.is_static and not _state_sync_queued:
		var active: String = gdss_node.get_active_state(ref as CanvasItem)
		if active != current_state:
			_state_sync_queued = true
			_sync_active_state.call_deferred()
	var entry: Dictionary = _resolve_entry()
	var state: String = _get_state()
	_apply_dynamic_nonstyle(gdss_node, entry, state)
	var vals: Dictionary = _build_style_vals(gdss_node, entry, state)
	var expand: Vector4 = Vector4(vals.get("expand", Vector4i.ZERO))
	rect = rect.grow_individual(expand.x, expand.z, expand.y, expand.w)
	if not rect.has_area():
		return
	if GDSS.gpu_panels_enabled():
		_draw_gpu(to_canvas_item, rect, vals)
		return
	_free_gpu_ci()
	_draw_cpu(to_canvas_item, rect, vals)


func _draw_cpu(to_canvas_item: RID, rect: Rect2, vals: Dictionary) -> void:
	var corner_radius: Vector4 = Vector4(vals.get("corner_radius", Vector4i.ZERO))
	var anti_aliasing: bool = vals.get("anti_aliasing", true)
	var aa_size: float = 1.0 if anti_aliasing else 0.0
	var detail: int = max(1, int(vals.get("corner_detail", 8)))
	var skew_x: float = vals.get("skew_x", 0.0)
	var skew_y: float = vals.get("skew_y", 0.0)
	var shadow: Vector4 = Vector4(vals.get("shadow", Vector4i.ZERO))
	var shadow_src: Variant = vals.get("shadow_color", Color(0, 0, 0, 0.4))
	var shadow_size: float = float(shadow.x + shadow.y + shadow.z + shadow.w) * 0.25
	if shadow_size > 1.0:
		var shadow_outer: Rect2 = rect.grow(shadow_size)
		var fitted: Vector4 = _fit_corners(corner_radius, rect)
		if shadow_src is GdssGradient:
			_draw_linear_gradient_ring(to_canvas_item, shadow_src as GdssGradient, rect, shadow_outer, fitted, detail, skew_x, skew_y, true)
		elif shadow_src is Texture2D:
			_draw_textured_ring(to_canvas_item, rect, shadow_outer, fitted, shadow_src as Texture2D, detail, skew_x, skew_y, true)
		elif shadow_src is Color:
			_draw_ring_raw(to_canvas_item, rect, shadow_outer, fitted, _fit_corners(corner_radius, shadow_outer), shadow_src as Color, true, detail, skew_x, skew_y)
	var bg: Variant = vals.get("bg_color", Color.TRANSPARENT)
	if bg is GdssGradient:
		var bgrad: GdssGradient = bg as GdssGradient
		if bgrad.mode == 2:
			_draw_radial_gradient_rect(to_canvas_item, bgrad, rect, corner_radius, detail, skew_x, skew_y)
		else:
			_draw_linear_gradient_rect(to_canvas_item, bgrad, rect, corner_radius, detail, skew_x, skew_y)
	elif bg is GdssBlur:
		var blur_tint: Color = (bg as GdssBlur).tint
		if blur_tint.a > 0.0:
			_draw_rect(to_canvas_item, rect, blur_tint, corner_radius, aa_size, detail, skew_x, skew_y)
	elif bg is Texture2D:
		_draw_texture_in_rect(to_canvas_item, bg as Texture2D, rect, corner_radius, detail, skew_x, skew_y)
	elif bg is Color and (bg as Color).a > 0.0:
		_draw_rect(to_canvas_item, rect, bg as Color, corner_radius, aa_size, detail, skew_x, skew_y)
	var border: Vector4 = Vector4(vals.get("border", Vector4i.ZERO))
	var border_src: Variant = vals.get("border_color", Color.TRANSPARENT)
	var has_border: bool = border.x > 0 or border.y > 0 or border.z > 0 or border.w > 0
	if has_border:
		var inner_rect: Rect2 = rect.grow_individual(-border.x, -border.z, -border.y, -border.w)
		if inner_rect.has_area():
			if border_src is GdssGradient:
				_draw_linear_gradient_ring(to_canvas_item, border_src as GdssGradient, inner_rect, rect, corner_radius, detail, skew_x, skew_y)
			elif border_src is GdssBlur:
				var border_tint: Color = (border_src as GdssBlur).tint
				if border_tint.a > 0.0:
					_draw_ring(to_canvas_item, inner_rect, rect, corner_radius, border_tint, aa_size, detail, skew_x, skew_y)
			elif border_src is Color and (border_src as Color).a > 0.0:
				_draw_ring(to_canvas_item, inner_rect, rect, corner_radius, border_src as Color, aa_size, detail, skew_x, skew_y)


static func _get_shared_shader() -> Shader:
	if _shader == null:
		_shader = load("res://addons/gdss/db/props/gdss_panel.gdshader") as Shader
	return _shader


static func _get_blur_shader() -> Shader:
	if _blur_shader == null:
		_blur_shader = load("res://addons/gdss/db/props/gdss_blur.gdshader") as Shader
	return _blur_shader


func _ensure_gpu_ci(to_canvas_item: RID, want_blur: bool = false) -> void:
	if not _gpu_ci.is_valid():
		_gpu_ci = RenderingServer.canvas_item_create()
		_gpu_material = ShaderMaterial.new()
		_gpu_is_blur = want_blur
		_gpu_material.shader = _get_blur_shader() if want_blur else _get_shared_shader()
		RenderingServer.canvas_item_set_material(_gpu_ci, _gpu_material.get_rid())
		RenderingServer.canvas_item_set_draw_behind_parent(_gpu_ci, true)
		_gpu_parent = RID()
	elif _gpu_is_blur != want_blur:
		_gpu_is_blur = want_blur
		_gpu_material.shader = _get_blur_shader() if want_blur else _get_shared_shader()
		_gpu_last.clear()
	if _gpu_parent != to_canvas_item:
		RenderingServer.canvas_item_set_parent(_gpu_ci, to_canvas_item)
		_gpu_parent = to_canvas_item


func _free_gpu_ci() -> void:
	if _gpu_ci.is_valid():
		RenderingServer.free_rid(_gpu_ci)
		_gpu_ci = RID()
		_gpu_parent = RID()
	_gpu_material = null
	_gpu_last.clear()
	_gpu_emitted = false


func _set_param(key: StringName, value: Variant) -> void:
	if _gpu_last.get(key) == value and _gpu_last.has(key):
		return
	_gpu_last[key] = value
	_gpu_material.set_shader_parameter(key, value)


func _draw_gpu(to_canvas_item: RID, rect: Rect2, vals: Dictionary) -> void:
	var bg: Variant = vals.get("bg_color", Color.TRANSPARENT)
	var border_src: Variant = vals.get("border_color", Color.TRANSPARENT)
	_ensure_gpu_ci(to_canvas_item, bg is GdssBlur or border_src is GdssBlur)
	var shadow: Vector4 = Vector4(vals.get("shadow", Vector4i.ZERO))
	var shadow_size: float = (shadow.x + shadow.y + shadow.z + shadow.w) * 0.25
	var pad: float = shadow_size + 2.0 if shadow_size > 0.5 else 0.0
	var quad: Rect2 = rect.grow(pad)
	var pad_frac: Vector2 = Vector2(pad / quad.size.x, pad / quad.size.y) if pad > 0.0 else Vector2.ZERO
	var anti_aliasing: bool = vals.get("anti_aliasing", true)
	_set_param(&"u_size", quad.size)
	_set_param(&"u_pad", Vector2(pad, pad))
	_set_param(&"u_corner_radius", Vector4(vals.get("corner_radius", Vector4i.ZERO)))
	_set_param(&"u_border_widths", Vector4(vals.get("border", Vector4i.ZERO)))
	_set_param(&"u_shadow", shadow)
	_set_param(&"u_aa", 1.0 if anti_aliasing else 0.0)
	var shadow_src: Variant = vals.get("shadow_color", _DEFAULT_SHADOW_COLOR)
	_set_param(&"u_shadow_color", shadow_src if shadow_src is Color else _DEFAULT_SHADOW_COLOR)
	_push_fill(bg, pad_frac)
	_push_border(border_src, pad_frac)
	var xform: Transform2D = _skew_transform(rect, vals.get("skew_x", 0.0), vals.get("skew_y", 0.0))
	if not _gpu_emitted or quad != _gpu_quad or xform != _gpu_xform:
		_gpu_quad = quad
		_gpu_xform = xform
		_gpu_emitted = true
		RenderingServer.canvas_item_clear(_gpu_ci)
		RenderingServer.canvas_item_set_transform(_gpu_ci, xform)
		RenderingServer.canvas_item_add_rect(_gpu_ci, quad, Color.WHITE)


func _push_fill(bg: Variant, pad_frac: Vector2) -> void:
	if bg is GdssGradient:
		var grad: GdssGradient = bg as GdssGradient
		_set_param(&"u_fill_a", grad.color_a)
		_set_param(&"u_fill_b", grad.color_b)
		_set_param(&"u_grad_offsets", grad.offsets)
		_set_param(&"u_grad_p0", _remap_uv(grad.p0, pad_frac))
		_set_param(&"u_grad_p1", _remap_uv(grad.p1, pad_frac))
		_set_param(&"u_fill_mode", grad.mode)
	elif bg is GdssBlur:
		var blur: GdssBlur = bg as GdssBlur
		_set_param(&"u_fill_a", blur.tint)
		_set_param(&"u_fill_glass", Vector4(blur.strength, blur.refraction, blur.highlight, blur.saturation))
		if blur.strength_end != blur.strength:
			_set_param(&"u_fill_mode", 5)
			_set_param(&"u_fill_glass2", Vector4(blur.strength_end, blur.refraction, blur.highlight, blur.saturation))
			_set_param(&"u_grad_offsets", blur.grad_offsets)
			_set_param(&"u_grad_p0", _remap_uv(blur.grad_p0, pad_frac))
			_set_param(&"u_grad_p1", _remap_uv(blur.grad_p1, pad_frac))
		else:
			_set_param(&"u_fill_mode", 4)
	elif bg is Texture2D:
		_set_param(&"u_fill_mode", 3)
		_set_param(&"u_tex", bg as Texture2D)
	elif bg is Color:
		_set_param(&"u_fill_mode", 0)
		_set_param(&"u_fill_a", bg as Color)
	else:
		_set_param(&"u_fill_mode", 0)
		_set_param(&"u_fill_a", Color.TRANSPARENT)


func _push_border(border_src: Variant, pad_frac: Vector2) -> void:
	if border_src is GdssGradient:
		var grad: GdssGradient = border_src as GdssGradient
		_set_param(&"u_border_mode", 1)
		_set_param(&"u_border_a", grad.color_a)
		_set_param(&"u_border_b", grad.color_b)
		_set_param(&"u_border_p0", _remap_uv(grad.p0, pad_frac))
		_set_param(&"u_border_p1", _remap_uv(grad.p1, pad_frac))
	elif border_src is GdssBlur:
		var blur: GdssBlur = border_src as GdssBlur
		_set_param(&"u_border_a", blur.tint)
		_set_param(&"u_border_glass", Vector4(blur.strength, blur.refraction, blur.highlight, blur.saturation))
		if blur.strength_end != blur.strength:
			_set_param(&"u_border_mode", 3)
			_set_param(&"u_border_glass2", Vector4(blur.strength_end, blur.refraction, blur.highlight, blur.saturation))
			_set_param(&"u_border_p0", _remap_uv(blur.grad_p0, pad_frac))
			_set_param(&"u_border_p1", _remap_uv(blur.grad_p1, pad_frac))
		else:
			_set_param(&"u_border_mode", 2)
	elif border_src is Color:
		_set_param(&"u_border_mode", 0)
		_set_param(&"u_border_a", border_src as Color)
	else:
		_set_param(&"u_border_mode", 0)
		_set_param(&"u_border_a", Color.TRANSPARENT)


func _remap_uv(uv: Vector2, pad_frac: Vector2) -> Vector2:
	return pad_frac + uv * (Vector2.ONE - pad_frac * 2.0)


func _skew_transform(rect: Rect2, skew_x: float, skew_y: float) -> Transform2D:
	if skew_x == 0.0 and skew_y == 0.0:
		return Transform2D.IDENTITY
	var center: Vector2 = rect.position + rect.size * 0.5
	var bx: Vector2 = Vector2(1.0, skew_y)
	var by: Vector2 = Vector2(skew_x, 1.0)
	# translate(center) * shear * translate(-center) folded into one transform:
	# result(p) = M*p + (center - M*center), with basis M = (bx, by).
	return Transform2D(bx, by, center - (bx * center.x + by * center.y))


func _draw_texture_in_rect(to_canvas_item: RID, tex: Texture2D, rect: Rect2, corner_radii: Vector4, detail: int, skew_x: float, skew_y: float) -> void:
	var points: PackedVector2Array = _apply_skew(_get_rounded_rect(rect, _fit_corners(corner_radii, rect), detail), rect, skew_x, skew_y)
	var n: int = points.size()
	var tex_size: Vector2 = tex.get_size()
	var scale: float = maxf(rect.size.x / tex_size.x, rect.size.y / tex_size.y)
	var scaled: Vector2 = tex_size * scale
	var uv_scale: Vector2 = rect.size / scaled
	var uv_offset: Vector2 = (Vector2.ONE - uv_scale) * 0.5
	var uvs: PackedVector2Array
	uvs.resize(n)
	for i: int in n:
		var local: Vector2 = (points[i] - rect.position) / rect.size
		uvs[i] = uv_offset + local * uv_scale
	RenderingServer.canvas_item_add_polygon(to_canvas_item, points, [Color.WHITE], uvs, tex.get_rid())


func _draw_textured_ring(to_canvas_item: RID, inner_rect: Rect2, outer_rect: Rect2, corner_radii: Vector4, tex: Texture2D, detail: int, skew_x: float, skew_y: float, fade: bool = false) -> void:
	var outer_fitted: Vector4 = _fit_corners(corner_radii, outer_rect)
	var inner_fitted: Vector4 = _fit_corners(corner_radii, inner_rect)
	var inner_points: PackedVector2Array = _apply_skew(_get_rounded_rect(inner_rect, inner_fitted, detail), inner_rect, skew_x, skew_y)
	var outer_points: PackedVector2Array = _apply_skew(_get_rounded_rect(outer_rect, outer_fitted, detail), outer_rect, skew_x, skew_y)
	var n: int = max(inner_points.size(), outer_points.size())
	for i: int in n:
		var i0: int = i % inner_points.size()
		var i1: int = (i + 1) % inner_points.size()
		var o0: int = i % outer_points.size()
		var o1: int = (i + 1) % outer_points.size()
		var p0: Vector2 = inner_points[i0]
		var p1: Vector2 = outer_points[o0]
		var p2: Vector2 = outer_points[o1]
		var p3: Vector2 = inner_points[i1]
		if p0.is_equal_approx(p1) or p0.is_equal_approx(p3) or p1.is_equal_approx(p2) or p2.is_equal_approx(p3) or p0.is_equal_approx(p2) or p1.is_equal_approx(p3):
			continue
		var quad: PackedVector2Array = PackedVector2Array([p0, p1, p2, p3])
		var uvs: PackedVector2Array
		uvs.resize(4)
		var colors: PackedColorArray
		colors.resize(4)
		for j: int in 4:
			uvs[j] = (quad[j] - outer_rect.position) / outer_rect.size
			var is_outer: bool = j == 1 or j == 2
			colors[j] = Color(1, 1, 1, 0.0 if (fade and is_outer) else 1.0)
		RenderingServer.canvas_item_add_polygon(to_canvas_item, quad, colors, uvs, tex.get_rid())


func _sample_grad(c1: Color, c2: Color, offsets: Vector2, t: float) -> Color:
	var span: float = maxf(offsets.y - offsets.x, 0.0001)
	return c1.lerp(c2, clampf((t - offsets.x) / span, 0.0, 1.0))


func _draw_linear_gradient_rect(to_canvas_item: RID, grad: GdssGradient, rect: Rect2, corner_radii: Vector4, detail: int, skew_x: float, skew_y: float) -> void:
	var c1: Color = grad.color_a
	var c2: Color = grad.color_b
	var angle: float = grad.p0.angle_to_point(grad.p1)
	var points: PackedVector2Array = _apply_skew(_get_rounded_rect(rect, _fit_corners(corner_radii, rect), detail), rect, skew_x, skew_y)
	var dir: Vector2 = Vector2(cos(angle), sin(angle))
	var colors: PackedColorArray
	colors.resize(points.size())
	for i: int in points.size():
		var p: Vector2 = points[i]
		var t: float = ((p - rect.position) / rect.size).dot(dir) * 0.5 + 0.5
		colors[i] = _sample_grad(c1, c2, grad.offsets, t)
	RenderingServer.canvas_item_add_polygon(to_canvas_item, points, colors)


func _draw_radial_gradient_rect(to_canvas_item: RID, grad: GdssGradient, rect: Rect2, corner_radii: Vector4, detail: int, skew_x: float, skew_y: float) -> void:
	var perimeter: PackedVector2Array = _apply_skew(_get_rounded_rect(rect, _fit_corners(corner_radii, rect), detail), rect, skew_x, skew_y)
	var n: int = perimeter.size()
	if n < 3:
		return
	var radius: float = maxf((grad.p1 - grad.p0).length(), 0.0001)
	var center: Vector2 = rect.position + grad.p0 * rect.size
	var verts: PackedVector2Array
	var cols: PackedColorArray
	var indices: PackedInt32Array
	verts.resize(n + 1)
	cols.resize(n + 1)
	verts[0] = center
	cols[0] = _sample_grad(grad.color_a, grad.color_b, grad.offsets, 0.0)
	for i: int in n:
		verts[i + 1] = perimeter[i]
		var uv: Vector2 = (perimeter[i] - rect.position) / rect.size
		cols[i + 1] = _sample_grad(grad.color_a, grad.color_b, grad.offsets, (uv - grad.p0).length() / radius)
	for i: int in n:
		indices.append_array([0, i + 1, (i + 1) % n + 1])
	RenderingServer.canvas_item_add_triangle_array(to_canvas_item, indices, verts, cols)


func _draw_linear_gradient_ring(to_canvas_item: RID, grad: GdssGradient, inner_rect: Rect2, outer_rect: Rect2, corner_radii: Vector4, detail: int, skew_x: float, skew_y: float, fade: bool = false) -> void:
	var c1: Color = grad.color_a
	var c2: Color = grad.color_b
	var angle: float = grad.p0.angle_to_point(grad.p1)
	var outer_fitted: Vector4 = _fit_corners(corner_radii, outer_rect)
	var inner_fitted: Vector4 = _fit_corners(corner_radii, inner_rect)
	var inner_points: PackedVector2Array = _apply_skew(_get_rounded_rect(inner_rect, inner_fitted, detail), inner_rect, skew_x, skew_y)
	var outer_points: PackedVector2Array = _apply_skew(_get_rounded_rect(outer_rect, outer_fitted, detail), outer_rect, skew_x, skew_y)
	var dir: Vector2 = Vector2(cos(angle), sin(angle))
	var n: int = max(inner_points.size(), outer_points.size())
	for i: int in n:
		var i0: int = i % inner_points.size()
		var i1: int = (i + 1) % inner_points.size()
		var o0: int = i % outer_points.size()
		var o1: int = (i + 1) % outer_points.size()
		var p0: Vector2 = inner_points[i0]
		var p1: Vector2 = outer_points[o0]
		var p2: Vector2 = outer_points[o1]
		var p3: Vector2 = inner_points[i1]
		var quad: PackedVector2Array = PackedVector2Array([p0, p1, p2, p3])
		var quad_colors: PackedColorArray
		quad_colors.resize(4)
		for j: int in 4:
			var p: Vector2 = quad[j]
			var t: float = ((p - outer_rect.position) / outer_rect.size).dot(dir) * 0.5 + 0.5
			var col: Color = _sample_grad(c1, c2, grad.offsets, t)
			var is_outer: bool = j == 1 or j == 2
			if fade and is_outer:
				col.a = 0.0
			quad_colors[j] = col
		RenderingServer.canvas_item_add_polygon(to_canvas_item, quad, quad_colors)


func _draw_rect(to_canvas_item: RID, rect: Rect2, color: Color, corner_radii: Vector4, aa: float, detail: int, skew_x: float, skew_y: float) -> void:
	if corner_radii == Vector4.ZERO and aa == 0.0:
		var points: PackedVector2Array = _apply_skew(_get_rounded_rect(rect, corner_radii, detail), rect, skew_x, skew_y)
		RenderingServer.canvas_item_add_polygon(to_canvas_item, points, [color])
		return

	var fitted: Vector4 = _fit_corners(corner_radii, rect)

	if aa > 0.0:
		var inner_rect: Rect2 = rect.grow(-aa)
		var inner_fitted: Vector4 = _fit_corners(corner_radii, inner_rect)
		_draw_ring_raw(to_canvas_item, inner_rect, rect, inner_fitted, fitted, color, true, detail, skew_x, skew_y)
		rect = inner_rect
		fitted = inner_fitted

	var points: PackedVector2Array = _apply_skew(_get_rounded_rect(rect, fitted, detail), rect, skew_x, skew_y)
	RenderingServer.canvas_item_add_polygon(to_canvas_item, points, [color])


func _draw_ring(to_canvas_item: RID, inner_rect: Rect2, outer_rect: Rect2, corner_radii: Vector4, color: Color, aa: float, detail: int, skew_x: float, skew_y: float) -> void:
	var outer_fitted: Vector4 = _fit_corners(corner_radii, outer_rect)
	var inner_fitted: Vector4 = _fit_corners(corner_radii, inner_rect)
	_draw_ring_raw(to_canvas_item, inner_rect, outer_rect, inner_fitted, outer_fitted, color, false, detail, skew_x, skew_y)


func _draw_ring_raw(to_canvas_item: RID, inner_rect: Rect2, outer_rect: Rect2, inner_radii: Vector4, outer_radii: Vector4, color: Color, fade: bool, detail: int, skew_x: float, skew_y: float) -> void:
	var inner_points: PackedVector2Array = _apply_skew(_get_rounded_rect(inner_rect, inner_radii, detail), inner_rect, skew_x, skew_y)
	var outer_points: PackedVector2Array = _apply_skew(_get_rounded_rect(outer_rect, outer_radii, detail), outer_rect, skew_x, skew_y)
	var all_points: PackedVector2Array = inner_points + outer_points
	var indices: PackedInt32Array = _triangulate_ring(inner_points.size(), outer_points.size())

	var colors: PackedColorArray
	if fade:
		colors.resize(all_points.size())
		for i: int in inner_points.size():
			colors[i] = color
		for i: int in outer_points.size():
			colors[inner_points.size() + i] = Color(color.r, color.g, color.b, 0.0)
	else:
		colors = [color]

	RenderingServer.canvas_item_add_triangle_array(to_canvas_item, indices, all_points, colors)


func _triangulate_ring(inner_size: int, outer_size: int) -> PackedInt32Array:
	var key: int = inner_size * 100003 + outer_size
	if _tri_cache.has(key):
		return _tri_cache[key]
	var indices: PackedInt32Array
	var total: int = max(inner_size, outer_size)
	for i: int in total:
		var i0: int = i % inner_size
		var i1: int = (i + 1) % inner_size
		var o0: int = i % outer_size + inner_size
		var o1: int = (i + 1) % outer_size + inner_size
		indices.append_array([i0, o0, o1, i0, o1, i1])
	_tri_cache[key] = indices
	return indices


func _get_rounded_rect(rect: Rect2, corner_radii: Vector4, detail: int = 8) -> PackedVector2Array:
	var key: String = "%.2f,%.2f,%.2f,%.2f|%.2f,%.2f,%.2f,%.2f|%d" % [rect.position.x, rect.position.y, rect.size.x, rect.size.y, corner_radii.x, corner_radii.y, corner_radii.z, corner_radii.w, detail]
	if _rr_cache.has(key):
		return _rr_cache[key]
	var corner_centers: Array[Vector2] = [
		rect.position + Vector2(corner_radii[0], corner_radii[0]),
		Vector2(rect.end.x, rect.position.y) + Vector2(-corner_radii[1], corner_radii[1]),
		rect.end + Vector2(-corner_radii[2], -corner_radii[2]),
		Vector2(rect.position.x, rect.end.y) + Vector2(corner_radii[3], -corner_radii[3]),
	]

	var points: PackedVector2Array
	for corner_idx: int in 4:
		var radius: float = corner_radii[corner_idx]
		if radius == 0.0:
			match corner_idx:
				0: points.append(rect.position)
				1: points.append(Vector2(rect.end.x, rect.position.y))
				2: points.append(rect.end)
				3: points.append(Vector2(rect.position.x, rect.end.y))
		else:
			for i: int in range(detail + 1):
				var theta: float = _corner_start_angles[corner_idx] + (PI * 0.5) * i / detail
				points.append(corner_centers[corner_idx] + Vector2(cos(theta), sin(theta)) * radius)
	if _rr_cache.size() > 2048:
		_rr_cache.clear()
	_rr_cache[key] = points
	return points


func _apply_skew(points: PackedVector2Array, rect: Rect2, skew_x: float, skew_y: float) -> PackedVector2Array:
	if skew_x == 0.0 and skew_y == 0.0:
		return points
	var result: PackedVector2Array = points
	for i: int in result.size():
		var p: Vector2 = result[i]
		var t: Vector2 = (p - rect.position) / rect.size
		result[i] = Vector2(
			p.x + skew_x * (t.y - 0.5) * rect.size.y,
			p.y + skew_y * (t.x - 0.5) * rect.size.x
		)
	return result


func _fit_corners(corners: Vector4, rect: Rect2) -> Vector4:
	var scale: float = min(
		1.0,
		rect.size.x / maxf(corners[0] + corners[1], 0.001),
		rect.size.y / maxf(corners[1] + corners[2], 0.001),
		rect.size.x / maxf(corners[2] + corners[3], 0.001),
		rect.size.y / maxf(corners[3] + corners[0], 0.001),
	)
	return Vector4(
		maxf(0.0, corners[0] * scale - 0.001),
		maxf(0.0, corners[1] * scale - 0.001),
		maxf(0.0, corners[2] * scale - 0.001),
		maxf(0.0, corners[3] * scale - 0.001),
	)
