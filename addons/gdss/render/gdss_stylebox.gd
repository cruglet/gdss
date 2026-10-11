@tool
class_name GdssStylebox
extends StyleBox

static var _corner_start_angles: Array[float] = [PI, PI * 1.5, 0.0, PI * 0.5]
const _DEFAULT_SHADOW_COLOR: Color = Color(0, 0, 0, 0.4)
const _SHADOW_CORNER_SPILL: float = 0.4

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
	return _TRANSITION_FUNCS.get(GDSS.TransitionFunc.find_key(func_enum), Tween.TRANS_LINEAR)


static func tween_ease(type_enum: GDSS.TransitionType) -> Tween.EaseType:
	return _EASE_TYPES.get(GDSS.TransitionType.find_key(type_enum), Tween.EASE_IN_OUT)


static func _time_for(raw: Variant, prop_name: String) -> float:
	if raw is Dictionary and (raw as Dictionary).has(GdssStylesheet.SCOPED_TIME_KEY):
		var map: Dictionary = raw.get(GdssStylesheet.SCOPED_TIME_KEY)
		if map.has(prop_name):
			return float(map.get(prop_name))
		return float(map.get(GdssStylesheet.SCOPED_TIME_ANY, -1.0))
	return float(raw) if raw is int or raw is float else 0.0


func _resolve_time(prop_name: String, state: String) -> float:
	var seconds: float = _time_for(_get_parsed_val("transition_time", state, 0.0), prop_name)
	if seconds >= 0.0:
		return seconds
	var node_type: GdssNodeType = _resolve_gdss_node()
	var base: String = node_type.states.get(0) if node_type and not node_type.states.is_empty() else "all"
	return maxf(_time_for(_get_parsed_val("transition_time", base, 0.0), prop_name), 0.0)


static func _longest_time(raw: Variant) -> float:
	if not (raw is Dictionary and (raw as Dictionary).has(GdssStylesheet.SCOPED_TIME_KEY)):
		return float(raw) if raw is int or raw is float else 0.0
	var longest: float = 0.0
	for key: String in (raw.get(GdssStylesheet.SCOPED_TIME_KEY) as Dictionary):
		longest = maxf(longest, float(raw.get(GdssStylesheet.SCOPED_TIME_KEY).get(key)))
	return longest


static func _resolve_trans_val(raw: Variant) -> Tween.TransitionType:
	if raw is int or raw is float:
		var keys: Array = GDSS.TransitionFunc.keys()
		var index: int = int(raw)
		if index >= 0 and index < keys.size():
			return _TRANSITION_FUNCS.get(keys.get(index), Tween.TRANS_LINEAR)
		return Tween.TRANS_LINEAR
	return _TRANSITION_FUNCS.get(raw, Tween.TRANS_LINEAR)


static func _resolve_ease_val(raw: Variant) -> Tween.EaseType:
	if raw is int or raw is float:
		var keys: Array = GDSS.TransitionType.keys()
		var index: int = int(raw)
		if index >= 0 and index < keys.size():
			return _EASE_TYPES.get(keys.get(index), Tween.EASE_OUT)
		return Tween.EASE_OUT
	return _EASE_TYPES.get(raw, Tween.EASE_OUT)


var _slot_state: String = ""

var _ref_path: NodePath = NodePath()
var _ref_node: Node = null
var _ref_node_rt: Node = null
var _applying: bool = false

var _entry_cache: Dictionary = {}
var _entry_cache_dirty: bool = true
var _entry_cache_classes: PackedStringArray = []
var _entry_cache_variation: String = ""
var _entry_cache_overrides: Variant = null
var _entry_cache_ancestry: String = ""
var _scoped_vars: Dictionary = {}
var _ancestor_states_dirty: bool = true
var _ancestor_states: bool = false
var _styled_props_cache: Dictionary = {}
var _styled_props_dirty: bool = true

var _animatable_cache: Dictionary = {}
var _animatable_dirty: bool = true

var _method_args_cache: Dictionary = {}

var _gdss_node: GdssNodeType = null

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
var _gpu_warned_clip: bool = false
var _fill_tint: Color = Color.WHITE
var _fill_scroll: Vector2 = Vector2.ZERO
var _fill_scale: Vector2 = Vector2.ZERO
var _fill_texture: Texture2D = null
var _fill_aspect: bool = false
var _fill_repeat: bool = false
var _fill_nearest: bool = false
var _fill_natural: bool = false
var _fade_texture: Texture2D = null
var _fade_target: Texture2D = null
var _fade_value: float = 1.0
var _fade_tween: Tween

var _style_vals_cache: Dictionary = {}
var _style_dynamic: Array[GdssProp] = []
var _style_vals_state: String = "￿"
var _style_vals_tween: Dictionary = {}
var _style_dynamic_tween: Array[GdssProp] = []
var _style_tween_state: String = "￿"
var _style_tween_session: int = -1
var _tween_session: int = 0
var _nonstyle_dynamic: Array[GdssProp] = []
var _nonstyle_state: String = "￿"
var _event_callables: Dictionary = {}

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


var _seeding: bool = false
var current_state: String = "":
	set(s):
		if s == current_state:
			return
		if _seeding:
			current_state = s
			return
		if _applying:
			if not _state_sync_queued:
				_state_sync_queued = true
				_sync_active_state.call_deferred()
			return
		var previous: String = current_state
		if not previous.is_empty():
			_start_transition(previous, s)
			_play_sfx(s)
		current_state = s
		_apply_overrides(not previous.is_empty())
		_notify_descendant_rules()
		if ref != null:
			_safe_redraw()


var _tweened_values: Dictionary[String, Variant] = {}
var _tweened_args: Dictionary[String, Array] = {}
var _tween: Tween = null
var _state_sync_queued: bool = false
var _applied_node_props: Dictionary = {}
var _applied_overrides: Dictionary = {}

var _self_toggle: bool = false
var _last_visible: bool = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _tween != null:
			_tween.kill()
			_tween = null
		if _gpu_ci.is_valid():
			RenderingServer.free_rid(_gpu_ci)
			_gpu_ci = RID()
		if not Engine.is_editor_hint():
			return
		var interp: GdssStylesheet = GdssStylesheet.get_instance()
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
		var interp: GdssStylesheet = GdssStylesheet.get_instance()
		if is_instance_valid(interp) and not interp.parsed_changed.is_connected(_on_parsed_changed):
			interp.parsed_changed.connect(_on_parsed_changed)
	else:
		if not v.is_connected("tree_entered", _on_ref_tree_entered_rt):
			v.connect("tree_entered", _on_ref_tree_entered_rt)
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
		if v.is_connected("tree_entered", _on_ref_tree_entered_rt):
			v.disconnect("tree_entered", _on_ref_tree_entered_rt)
		if v.is_connected("tree_exiting", _on_ref_tree_exiting_rt):
			v.disconnect("tree_exiting", _on_ref_tree_exiting_rt)


func _apply_dynamic_nonstyle(node_type: GdssNodeType, entry: Dictionary, state: String) -> void:
	if entry.is_empty() or _applying:
		return
	if _nonstyle_state != state:
		_classify_nonstyle(node_type, entry, state)
	if _nonstyle_dynamic.is_empty():
		return
	_applying = true
	var control: Variant = ref
	for prop: GdssProp in _nonstyle_dynamic:
		var val: Variant = _get_val_cached(prop.name, entry, state, prop.get_default_value())
		if val == null:
			val = prop.get_default_value()
		_apply_theme_prop(prop, control, node_type, val)
	_refresh_font_transform(control, node_type)
	_applying = false


func _classify_nonstyle(node_type: GdssNodeType, entry: Dictionary, state: String) -> void:
	_nonstyle_state = state
	_nonstyle_dynamic.clear()
	var prop_map: Dictionary[String, GdssProp] = node_type.get_props_by_name()
	var seen: Dictionary[String, bool] = {}
	for source_state: String in [state, "all"]:
		if not entry.has(source_state):
			continue
		for prop_name: String in entry.get(source_state):
			if seen.has(prop_name):
				continue
			seen.set(prop_name, true)
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
		_repositioned()
		GdssNodeBinder.apply_mode_tree.call_deferred(_ref_node)


func _on_ref_tree_entered_rt() -> void:
	_repositioned()


func _repositioned() -> void:
	if ref == null:
		return
	GdssNodeBinder.reposition(ref)


func _on_ref_tree_exiting() -> void:
	_free_gpu_ci()
	if is_instance_valid(_ref_node) and _ref_node.is_inside_tree():
		_ref_path = _ref_node.get_path()


func _on_ref_tree_exiting_rt() -> void:
	_free_gpu_ci()


func _invalidate_entry_cache() -> void:
	_invalidate_entry_cache_self()
	var node: Node = ref
	if node == null:
		return
	for stylebox: GdssStylebox in GdssNodeBinder.get_slots(node).values():
		if stylebox != null and stylebox != self:
			stylebox._invalidate_entry_cache_self()


func _invalidate_entry_cache_self() -> void:
	_entry_cache_dirty = true
	_styled_props_dirty = true
	_entry_cache = {}
	_entry_cache_ancestry = ""
	_ancestor_states_dirty = true
	_animatable_dirty = true
	_method_args_cache.clear()
	_gdss_node = null
	_style_vals_state = "￿"
	_style_vals_cache.clear()
	_style_dynamic.clear()
	_style_tween_state = "￿"
	_style_tween_session = -1
	_style_vals_tween.clear()
	_style_dynamic_tween.clear()
	_nonstyle_state = "￿"
	_nonstyle_dynamic.clear()


func _resolve_gdss_node() -> GdssNodeType:
	if _gdss_node != null:
		return _gdss_node
	var node: Node = ref
	if node == null:
		return null
	_gdss_node = GDSS._get_node_types().get(node.get_class())
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
	var node_type: GdssNodeType = _resolve_gdss_node()
	if node_type == null:
		return
	var control: Variant = node
	remove_applied_overrides(control)
	_reset_node_props(node_type, control, true)


func remove_applied_overrides(control: Variant) -> void:
	for key: String in _applied_overrides.keys():
		match int(_applied_overrides.get(key)):
			GdssProp.Category.COLOR:
				control.remove_theme_color_override(key)
			GdssProp.Category.CONST:
				control.remove_theme_constant_override(key)
			GdssProp.Category.FONT_SIZE:
				control.remove_theme_font_size_override(key)
			GdssProp.Category.FONT:
				control.remove_theme_font_override(key)
			GdssProp.Category.ICON:
				control.remove_theme_icon_override(key)
	_applied_overrides.clear()


func _reset_node_props(node_type: GdssNodeType, control: Variant, skip_tweened: bool) -> void:
	if _applied_node_props.is_empty():
		return
	var props_by_name: Dictionary = node_type.get_props_by_name()
	for prop_name: String in _applied_node_props.keys():
		if skip_tweened and _tweened_values.has(prop_name):
			continue
		var prop: GdssProp = props_by_name.get(prop_name)
		if prop != null:
			_apply_theme_prop(prop, control, node_type, prop.get_default_value())
		_applied_node_props.erase(prop_name)


func _apply_overrides(clear: bool = true) -> void:
	var node: Node = ref
	if node == null or _applying:
		return
	var node_type: GdssNodeType = _resolve_gdss_node()
	if node_type == null:
		return
	if not GDSS.resolve_mode(node):
		return
	var control: Variant = node
	control.begin_bulk_theme_override()
	_apply_overrides_unwrapped(node_type, control, clear)
	control.end_bulk_theme_override()


func _apply_overrides_unwrapped(node_type: GdssNodeType, control: Variant, clear: bool) -> void:
	if _applying:
		return
	_applying = true
	if clear:
		_clear_overrides()
	var entry: Dictionary = _resolve_entry()
	var state: String = _get_state()
	var styled: Dictionary = _entry_styled_props(entry)
	for prop: GdssProp in node_type.get_enabled_props():
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
		var val: Variant = _get_val_cached(prop.name, entry, state, prop.get_default_value())
		if val == null:
			val = prop.get_default_value()
		_apply_theme_prop(prop, control, node_type, val)
	_refresh_font_transform(control, node_type)
	_applying = false


func _apply_theme_prop(prop: GdssProp, control: Variant, node_type: GdssNodeType, val: Variant) -> void:
	match prop.category:
		GdssProp.Category.COLOR:
			if val is Color:
				if prop.category_subproperties.is_empty():
					_override_color_if_custom(control, node_type, prop.name, val)
				else:
					if node_type.colors.has(prop.name):
						_override_color_if_custom(control, node_type, prop.name, val)
					for subprop: String in prop.category_subproperties:
						if node_type.colors.has(subprop):
							_override_color_if_custom(control, node_type, subprop, val)
		GdssProp.Category.CONST:
			if val is int or val is float:
				var theme_def: Variant = node_type.theme_defaults.get(prop.name, null)
				if theme_def is int and int(val) == int(theme_def):
					if _applied_overrides.has(prop.name):
						control.remove_theme_constant_override(prop.name)
						_applied_overrides.erase(prop.name)
					return
				_applied_overrides.set(prop.name, GdssProp.Category.CONST)
				if control.has_theme_constant_override(prop.name) and control.get_theme_constant(prop.name) == int(val):
					return
				control.add_theme_constant_override(prop.name, int(val))
		GdssProp.Category.FONT_SIZE:
			if val is int or val is float:
				var theme_def: Variant = node_type.theme_defaults.get(prop.name, null)
				if theme_def is int and int(val) == int(theme_def):
					if _applied_overrides.has(prop.name):
						control.remove_theme_font_size_override(prop.name)
						_applied_overrides.erase(prop.name)
					return
				_applied_overrides.set(prop.name, GdssProp.Category.FONT_SIZE)
				if control.has_theme_font_size_override(prop.name) and control.get_theme_font_size(prop.name) == int(val):
					return
				control.add_theme_font_size_override(prop.name, int(val))
		GdssProp.Category.FONT:
			if val is Font:
				var theme_def: Variant = node_type.theme_defaults.get(prop.name, null)
				if theme_def is Font and val == theme_def:
					return
				_applied_overrides.set(prop.name, GdssProp.Category.FONT)
				if control.has_theme_font_override(prop.name) and control.get_theme_font(prop.name) == val:
					return
				control.add_theme_font_override(prop.name, val as Font)
		GdssProp.Category.ICON:
			if val is Texture2D:
				_applied_overrides.set(prop.name, GdssProp.Category.ICON)
				if control.has_theme_icon_override(prop.name) and control.get_theme_icon(prop.name) == val:
					return
				control.add_theme_icon_override(prop.name, val)
		GdssProp.Category.NODE_PROPERTY:
			if not GDSS.transforms_enabled and prop.name.begins_with("transform_"):
				val = prop.get_default_value()
			if prop.type == GDSS.Type.VECTOR2 and (val is int or val is float):
				val = Vector2(float(val), float(val))
			var def: Variant = prop.get_default_value()
			if not (typeof(val) == typeof(def) and val == def):
				_applied_node_props.set(prop.name, true)
			if prop.type == GDSS.Type.CURSOR:
				control.set("mouse_default_cursor_shape", _get_cursor_shape(str(val)))
				return
			if prop.name == "char_skew" or prop.name == "char_embolden":
				_refresh_font_transform(control, node_type)
				return
			if prop.name == "opacity":
				var mod: Color = control.modulate
				var alpha: float = float(val)
				if not is_equal_approx(mod.a, alpha):
					mod.a = alpha
					control.modulate = mod
				return
			var node_prop: String = "offset_" + prop.name if prop.name.begins_with("transform_") else prop.name
			var current: Variant = control.get(node_prop)
			if typeof(current) != typeof(val) or current != val:
				control.set(node_prop, val)


func _override_color_if_custom(control: Variant, node_type: GdssNodeType, key: String, val: Color) -> void:
	var theme_def: Variant = node_type.theme_defaults.get(key, null)
	if theme_def is Color and val.is_equal_approx(theme_def as Color):
		if _applied_overrides.has(key):
			control.remove_theme_color_override(key)
			_applied_overrides.erase(key)
		return
	_applied_overrides.set(key, GdssProp.Category.COLOR)
	if control.has_theme_color_override(key) and control.get_theme_color(key).is_equal_approx(val):
		return
	control.add_theme_color_override(key, val)


func _apply_single_override(prop: GdssProp, val: Variant) -> void:
	var node: Node = ref
	if node == null:
		return
	var node_type: GdssNodeType = _resolve_gdss_node()
	if node_type == null:
		return
	if val == null:
		val = prop.get_default_value()
	var was_applying: bool = _applying
	_applying = true
	_apply_theme_prop(prop, node, node_type, val)
	_applying = was_applying


func _kill_tween() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	_tweened_values.clear()
	_tweened_args.clear()


func reapply() -> void:
	_kill_tween()
	_invalidate_entry_cache()
	_apply_overrides()
	emit_changed()


func refresh_globals() -> void:
	if _applying:
		return
	var node: Node = ref
	if node == null:
		return
	var node_type: GdssNodeType = _resolve_gdss_node()
	if node_type == null:
		return
	var entry: Dictionary = _resolve_entry()
	if entry.is_empty():
		return
	var state: String = _get_state()
	if _nonstyle_state != state:
		_classify_nonstyle(node_type, entry, state)
	if _nonstyle_dynamic.is_empty():
		return
	_applying = true
	var control: Variant = node
	control.begin_bulk_theme_override()
	for prop: GdssProp in _nonstyle_dynamic:
		var val: Variant = _get_val_cached(prop.name, entry, state, prop.get_default_value())
		if val == null:
			val = prop.get_default_value()
		_apply_theme_prop(prop, control, node_type, val)
	_refresh_font_transform(control, node_type)
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
	var node_type: GdssNodeType = _resolve_gdss_node()
	if node_type == null:
		return _animatable_cache
	for prop: GdssProp in node_type.get_enabled_props():
		match prop.type:
			GDSS.Type.CLIP_PATH, GDSS.Type.COLOR, GDSS.Type.COMPOSITE4, GDSS.Type.FLOAT, GDSS.Type.INT, GDSS.Type.VECTOR2:
				if not prop.name.begins_with("transition_"):
					_animatable_cache.set(prop.name, prop)
	_animatable_dirty = false
	return _animatable_cache


func _safe_redraw() -> void:
	var node: Node = ref
	if node == null:
		return
	if node is CanvasItem:
		(node as CanvasItem).queue_redraw()
	else:
		emit_changed()


func _sync_active_state() -> void:
	_state_sync_queued = false
	var node: Node = ref
	if not node is CanvasItem:
		return
	var node_type: GdssNodeType = _resolve_gdss_node()
	if node_type == null:
		return
	current_state = node_type.resolve_state(node as CanvasItem)


func _start_transition(from_state: String, to_state: String, timing_state: String = "", on_finished: Callable = Callable()) -> void:
	var ts: String = timing_state if not timing_state.is_empty() else to_state
	var transition_time: float = GDSS.scaled_duration(maxf(
		_longest_time(_get_parsed_val("transition_time", ts, 0.0)),
		_resolve_time(GdssStylesheet.SCOPED_TIME_ANY, ts)))
	if transition_time <= 0.0 or ref == null or not ref.is_inside_tree():
		_kill_tween()
		if on_finished.is_valid():
			on_finished.call()
		return
	
	var node_type: GdssNodeType = _resolve_gdss_node()
	var default_state: String = node_type.states.get(0) if node_type and not node_type.states.is_empty() else "all"
	var resolved_from: String = from_state if not from_state.is_empty() else default_state
	
	var trans: Tween.TransitionType = _resolve_trans_val(_get_parsed_val("transition_func", ts, "LINEAR"))
	var ease: Tween.EaseType = _resolve_ease_val(_get_parsed_val("transition_type", ts, "EASE_OUT"))
	
	var tweener_count: int = 0
	var pending_tween: Tween = (Engine.get_main_loop() as SceneTree).create_tween()
	pending_tween.set_parallel(true)
	pending_tween.set_trans(trans)
	pending_tween.set_ease(ease)
	
	var animatable: Dictionary = _get_animatable_props()
	
	for prop_name: String in animatable:
		var prop: GdssProp = animatable.get(prop_name)
		var prop_time: float = GDSS.scaled_duration(_resolve_time(prop_name, ts))
		if prop_time <= 0.0:
			continue
		var is_style: bool = prop.category == GdssProp.Category.STYLE
		
		var from_raw: Variant = _get_raw_parsed_val(prop_name, resolved_from)
		var to_raw: Variant = _get_raw_parsed_val(prop_name, to_state)
		
		if from_raw is Dictionary and (from_raw as Dictionary).has("__gdss_method__") and \
		   to_raw is Dictionary and (to_raw as Dictionary).has("__gdss_method__") and \
		   (from_raw as Dictionary).get("__gdss_method__") == (to_raw as Dictionary).get("__gdss_method__"):
			var mn: String = (from_raw as Dictionary).get("__gdss_method__")
			var method: GdssMethod = GDSS._get_gdss_methods().get(mn)
			if method != null and not method.get_tweenable_args().is_empty():
				var from_args: Array[Variant] = _tweened_args.get(prop_name, _resolve_method_args(from_raw as Dictionary))
				var to_args: Array[Variant] = _resolve_method_args(to_raw as Dictionary)
				var captured_prop: String = prop_name
				var captured_method: GdssMethod = method
				var node_id: int = ref.get_instance_id() if ref != null else -1
				pending_tween.tween_method(func(t: float) -> void:
					var interp_args: Array[Variant] = captured_method.interpolate_args(from_args, to_args, t)
					_tweened_args.set(captured_prop, interp_args)
					var result: Variant = captured_method.call_method(interp_args, node_id, "tween:" + captured_prop)
					if result != null:
						_tweened_values.set(captured_prop, result)
					_safe_redraw()
				, 0.0, 1.0, prop_time)
				tweener_count += 1
				continue
		
		match prop.type:
			GDSS.Type.COLOR:
				var fallback: Color = prop.get_default_value() if prop.get_default_value() is Color else Color.TRANSPARENT
				var from_val: Variant = _tweened_values.get(prop_name, _get_parsed_val(prop_name, resolved_from, fallback))
				var to_val: Variant = _get_parsed_val(prop_name, to_state, fallback)
				if from_val is Array or to_val is Array:
					var sides_from: Array = _side_colors(from_val, fallback)
					var sides_to: Array = _side_colors(to_val, fallback)
					if sides_from == sides_to:
						continue
					var captured_sides: String = prop_name
					_tweened_values.set(captured_sides, sides_from)
					pending_tween.tween_method(func(t: float) -> void:
						var lerped: Array = []
						for side: int in 4:
							lerped.append((sides_from.get(side) as Color).lerp(sides_to.get(side), t))
						_tweened_values.set(captured_sides, lerped)
						_safe_redraw()
					, 0.0, 1.0, prop_time)
					tweener_count += 1
					continue
				if not from_val is Color or not to_val is Color:
					continue
				var from: Color = from_val as Color
				var to: Color = to_val as Color
				if from == to:
					continue
				var captured: String = prop_name
				var captured_prop: GdssProp = prop
				_tweened_values.set(captured, from)
				pending_tween.tween_method(func(v: Color) -> void:
					_tweened_values.set(captured, v)
					if is_style:
						_safe_redraw()
					else:
						_apply_single_override(captured_prop, v)
				, from, to, prop_time)
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
				_tweened_values.set(captured, from)
				pending_tween.tween_method(func(v: Vector4) -> void:
					_tweened_values.set(captured, v)
					if is_style:
						_safe_redraw()
					else:
						_apply_single_override(captured_prop, v)
				, from, to, prop_time)
				tweener_count += 1
			
			GDSS.Type.VECTOR2:
				var fallback: Vector2 = prop.get_default_value() if prop.get_default_value() is Vector2 else Vector2.ZERO
				var from_val: Variant = _tweened_values.get(prop_name, _get_parsed_val(prop_name, resolved_from, fallback))
				var to_val: Variant = _get_parsed_val(prop_name, to_state, fallback)
				if from_val is int or from_val is float:
					from_val = Vector2(float(from_val), float(from_val))
				if to_val is int or to_val is float:
					to_val = Vector2(float(to_val), float(to_val))
				if not from_val is Vector2 or not to_val is Vector2:
					continue
				var from: Vector2 = from_val as Vector2
				var to: Vector2 = to_val as Vector2
				if from == to:
					continue
				var captured: String = prop_name
				var captured_prop: GdssProp = prop
				_tweened_values.set(captured, from)
				pending_tween.tween_method(func(v: Vector2) -> void:
					_tweened_values.set(captured, v)
					if is_style:
						_safe_redraw()
					else:
						_apply_single_override(captured_prop, v)
				, from, to, prop_time)
				tweener_count += 1
			
			GDSS.Type.FLOAT:
				var fallback: float = float(prop.get_default_value())
				var from: float = float(_tweened_values.get(prop_name, _get_parsed_val(prop_name, resolved_from, fallback)))
				var to: float = float(_get_parsed_val(prop_name, to_state, fallback))
				if from == to:
					continue
				var captured: String = prop_name
				var captured_prop: GdssProp = prop
				_tweened_values.set(captured, from)
				pending_tween.tween_method(func(v: float) -> void:
					_tweened_values.set(captured, v)
					if is_style:
						_safe_redraw()
					else:
						_apply_single_override(captured_prop, v)
				, from, to, prop_time)
				tweener_count += 1
			
			GDSS.Type.INT:
				var fallback: int = int(prop.get_default_value())
				var from: int = int(_tweened_values.get(prop_name, _get_parsed_val(prop_name, resolved_from, fallback)))
				var to: int = int(_get_parsed_val(prop_name, to_state, fallback))
				if from == to:
					continue
				var captured: String = prop_name
				var captured_prop: GdssProp = prop
				_tweened_values.set(captured, from)
				pending_tween.tween_method(func(v: float) -> void:
					_tweened_values.set(captured, int(v))
					if is_style:
						_safe_redraw()
					else:
						_apply_single_override(captured_prop, int(v))
				, float(from), float(to), prop_time)
				tweener_count += 1
	
	
	if tweener_count == 0:
		pending_tween.kill()
		_kill_tween()
		if on_finished.is_valid():
			on_finished.call()
		return
	
	if _tween:
		_tween.kill()
	_tween = pending_tween
	_tween_session += 1
	_tween.finished.connect(func() -> void:
		_tween = null
		_tweened_values.clear()
		_tweened_args.clear()
		if ref != null:
			_apply_overrides()
			_safe_redraw()
		if on_finished.is_valid():
			on_finished.call()
	)


func _resting_state(node_type: GdssNodeType, node: Node) -> String:
	if not _slot_state.is_empty():
		return _slot_state
	if not node_type.is_static and node is CanvasItem:
		var active: String = node_type.resolve_state(node as CanvasItem)
		if not active.is_empty():
			return active
	return node_type.states.get(0) if not node_type.states.is_empty() else "all"


func _on_node_visibility_changed() -> void:
	if _self_toggle:
		_self_toggle = false
		return
	var node: Control = ref as Control
	if node == null:
		return
	var vis: bool = node.visible
	if vis == _last_visible:
		return
	_last_visible = vis
	if vis:
		_play_show()
	else:
		_play_hide()


func _play_show() -> void:
	_play_event("on_show()")


func _play_event(event_key: String) -> void:
	var node: Node = ref
	if node == null:
		return
	var node_type: GdssNodeType = _resolve_gdss_node()
	if node_type == null or not _resolve_entry().has(event_key):
		return
	_start_transition(event_key, _resting_state(node_type, node), event_key)
	_play_sfx(event_key)
	_apply_overrides(false)


func _play_sfx(state_key: String) -> void:
	if not GDSS.sfx_enabled:
		return
	var state_dict: Variant = _resolve_entry().get(state_key)
	if not state_dict is Dictionary or not (state_dict as Dictionary).has("sfx"):
		return
	var stream: Variant = _get_parsed_val("sfx", state_key, null)
	if stream is AudioStream:
		GDSS.play_sfx(stream as AudioStream)


func _sync_event_signals(node: Node) -> void:
	var entry: Dictionary = _resolve_entry()
	for sig: String in _event_callables.keys():
		if not entry.has(sig + "()"):
			_disconnect_event_signal(node, sig)
	for key: String in entry:
		var sig: String = key.trim_suffix("()")
		if key.ends_with("()") and not _event_callables.has(sig) and node.has_signal(sig):
			var cb: Callable = _play_event.bind(key)
			var arg_count: int = _signal_arg_count(node, sig)
			if arg_count > 0:
				cb = cb.unbind(arg_count)
			node.connect(sig, cb)
			_event_callables.set(sig, cb)


func _clear_event_signals(node: Node) -> void:
	for sig: String in _event_callables.keys():
		_disconnect_event_signal(node, sig)


func _disconnect_event_signal(node: Node, sig: String) -> void:
	var cb: Callable = _event_callables.get(sig)
	if node.is_connected(sig, cb):
		node.disconnect(sig, cb)
	_event_callables.erase(sig)


static func _signal_arg_count(node: Node, sig: String) -> int:
	for info: Dictionary in node.get_signal_list():
		if info.get("name") == sig:
			return (info.get("args") as Array).size()
	return 0


func _play_hide() -> void:
	var node: Control = ref as Control
	if node == null:
		return
	var node_type: GdssNodeType = _resolve_gdss_node()
	if node_type == null or not _resolve_entry().has("on_hide()") or not node.is_inside_tree():
		if node != null and node.visible:
			_self_toggle = true
			node.visible = false
		return
	if not node.visible:
		_self_toggle = true
		node.visible = true
	_start_transition(_resting_state(node_type, node), "on_hide()", "on_hide()", func() -> void:
		if is_instance_valid(node) and node.visible:
			_self_toggle = true
			node.visible = false
	)


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


func _find_class_in_tree(classes: Dictionary, name: String) -> Dictionary:
	if classes.has(name):
		return classes.get(name)
	for key: String in classes:
		var nested: Dictionary = classes.get(key).get("_classes", {})
		if nested.is_empty():
			continue
		var found: Dictionary = _find_class_in_tree(nested, name)
		if not found.is_empty():
			return found
	return {}


func _find_class_path(classes: Dictionary, name: String) -> Array[Dictionary]:
	if classes.has(name):
		return [classes.get(name)] as Array[Dictionary]
	for key: String in classes:
		var nested: Dictionary = classes.get(key).get("_classes", {})
		if nested.is_empty():
			continue
		var found: Array[Dictionary] = _find_class_path(nested, name)
		if not found.is_empty():
			var path: Array[Dictionary] = [classes.get(key)] as Array[Dictionary]
			path.append_array(found)
			return path
	return [] as Array[Dictionary]


func _absorb_vars(source: Dictionary) -> void:
	var declared: Variant = source.get(GdssStylesheet.VARS_KEY)
	if not declared is Dictionary:
		return
	for key: String in declared as Dictionary:
		_scoped_vars.set(key, (declared as Dictionary).get(key))


func _merge_descendants(base: Dictionary, override: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: String in base:
		out.set(key, base.get(key))
	for key: String in override:
		if out.has(key) and out.get(key) is Dictionary and override.get(key) is Dictionary:
			out.set(key, _merge_entries(out.get(key), override.get(key), true))
		else:
			out.set(key, override.get(key))
	return out


func _merge_entries(base: Dictionary, override: Dictionary, keep_ancestor_states: bool = false) -> Dictionary:
	var merged: Dictionary = {}
	for state: String in base:
		if state == "_classes" or state == GdssStylesheet.VARS_KEY:
			continue
		if not keep_ancestor_states and state.begins_with(GdssStylesheet.ANCESTOR_STATE_PREFIX):
			continue
		merged.set(state, base.get(state).duplicate() if base.get(state) is Dictionary else base.get(state))
	for state: String in override:
		if state == "_classes" or state == GdssStylesheet.VARS_KEY:
			continue
		if not keep_ancestor_states and state.begins_with(GdssStylesheet.ANCESTOR_STATE_PREFIX):
			continue
		if state == GdssStylesheet.DESCENDANTS_KEY:
			merged.set(state, _merge_descendants(merged.get(state, {}), override.get(state)))
			continue
		if not merged.has(state):
			merged.set(state, override.get(state).duplicate() if override.get(state) is Dictionary else override.get(state))
			continue
		if override.get(state) is Dictionary:
			for key: String in override.get(state):
				if key == "transition_time":
					merged.get(state).set(key, GdssStylesheet._merge_scoped_time(
						merged.get(state).get(key), override.get(state).get(key)))
					continue
				merged.get(state).set(key, override.get(state).get(key))
		else:
			merged.set(state, override.get(state))
	merged.set("_classes", override.get("_classes", {}))
	return merged


func _entry_styled_props(entry: Dictionary) -> Dictionary:
	if not _styled_props_dirty:
		return _styled_props_cache
	_styled_props_cache.clear()
	for key: String in entry:
		if key == "_classes" or key == "_variations" or key == GdssStylesheet.DESCENDANTS_KEY or key == GdssStylesheet.VARS_KEY:
			continue
		var sd: Variant = entry.get(key)
		if sd is Dictionary:
			for prop_name: String in (sd as Dictionary):
				_styled_props_cache.set(prop_name, true)
	_styled_props_dirty = false
	return _styled_props_cache


func _resolve_entry() -> Dictionary:
	if ref == null:
		return {}
	if GdssStylesheet.parsed.is_empty():
		return {}
	if not _entry_cache_dirty and not Engine.is_editor_hint():
		return _entry_cache
	var current_classes: PackedStringArray = ref.get_meta(GDSS.CLASSES_META, PackedStringArray()) as PackedStringArray
	var variation: String = String((ref as Control).theme_type_variation) if ref is Control else ""
	var override_meta: Variant = ref.get_meta(GDSS.OVERRIDES_META) if ref.has_meta(GDSS.OVERRIDES_META) else null
	var ancestry: String = _ancestry_key()
	if not _entry_cache_dirty and _entry_cache_classes == current_classes and _entry_cache_variation == variation and _entry_cache_overrides == override_meta and _entry_cache_ancestry == ancestry:
		return _entry_cache
	_styled_props_dirty = true
	var parsed: Dictionary[String, Dictionary] = GdssStylesheet.parsed
	var selector: String = ref.get_class()
	var entry: Dictionary = parsed.get(selector, {})
	var variations: Dictionary = entry.get("_variations", {}) if not entry.is_empty() else {}
	var has_variation: bool = not variation.is_empty() and variations.has(variation)
	var override_entry: Dictionary = _build_override_entry(override_meta)
	var descendant_layers: Array[Dictionary] = _collect_descendant_layers()
	_scoped_vars.clear()
	for layer: Dictionary in descendant_layers:
		var inherited: Variant = layer.get("vars")
		if inherited is Dictionary:
			for key: String in inherited as Dictionary:
				_scoped_vars.set(key, (inherited as Dictionary).get(key))
	_absorb_vars(entry)
	for gdss_class_name: String in current_classes:
		for step: Dictionary in _find_class_path((parsed.get(selector, {}) as Dictionary).get("_classes", {}), gdss_class_name):
			_absorb_vars(step)
	if current_classes.is_empty() and not has_variation and override_entry.is_empty() and descendant_layers.is_empty():
		_entry_cache = entry
		_entry_cache_classes = current_classes
		_entry_cache_variation = variation
		_entry_cache_overrides = override_meta
		_entry_cache_ancestry = ancestry
		_entry_cache_dirty = false
		return entry
	if has_variation:
		entry = _merge_entries(entry, _resolve_override_patches(entry, variations.get(variation)))
	for layer: Dictionary in descendant_layers:
		var body: Dictionary = layer.get("entry")
		if not body.is_empty():
			entry = _merge_entries(entry, _resolve_override_patches(entry, body))
	for gdss_class_name: String in current_classes:
		var path: Array[Dictionary] = _find_class_path((parsed.get(selector, {}) as Dictionary).get("_classes", {}), gdss_class_name)
		for step: Dictionary in path:
			var step_rules: Variant = step.get(GdssStylesheet.DESCENDANTS_KEY)
			if step_rules is Dictionary and not (step_rules as Dictionary).is_empty():
				entry = _merge_entries(entry, {GdssStylesheet.DESCENDANTS_KEY: step_rules})
		var override: Dictionary = path.back() if not path.is_empty() else {}
		if not override.is_empty():
			entry = _merge_entries(entry, _resolve_override_patches(entry, override))
	for layer: Dictionary in descendant_layers:
		var anc: Dictionary = layer.get("anc")
		if not anc.is_empty():
			anc = _resolve_override_patches(entry, anc)
			entry = _merge_entries(entry, anc)
			_propagate_all(entry, anc)
	if not override_entry.is_empty():
		override_entry = _resolve_override_patches(entry, override_entry)
		entry = _merge_entries(entry, override_entry)
		_propagate_all(entry, override_entry)
	_entry_cache = entry
	_entry_cache_classes = current_classes
	_entry_cache_variation = variation
	_entry_cache_overrides = override_meta
	_entry_cache_ancestry = ancestry
	_entry_cache_dirty = false
	return entry


func _propagate_all(entry: Dictionary, overlay: Dictionary) -> void:
	var all_overrides: Variant = overlay.get("all")
	if not all_overrides is Dictionary:
		return
	for state_key: String in entry:
		if state_key == "all" or state_key == "_classes" or state_key == "_variations" or state_key == GdssStylesheet.DESCENDANTS_KEY or state_key == GdssStylesheet.VARS_KEY or state_key.ends_with("()"):
			continue
		if overlay.has(state_key):
			continue
		var state_dict: Variant = entry.get(state_key)
		if not state_dict is Dictionary:
			continue
		for prop_name: String in (all_overrides as Dictionary):
			(state_dict as Dictionary).set(prop_name, (all_overrides as Dictionary).get(prop_name))


const MAX_ANCESTOR_WALK: int = 32


func _ancestry_key() -> String:
	if not GdssStylesheet.has_descendant_rules or ref == null:
		return ""
	var parts: PackedStringArray = []
	var node: Node = ref.get_parent()
	var depth: int = 0
	while node != null and depth < MAX_ANCESTOR_WALK:
		depth += 1
		parts.append("%s.%s:%s" % [
			node.get_class(),
			String(",").join(node.get_meta(GDSS.CLASSES_META, PackedStringArray()) as PackedStringArray),
			_ancestor_state(node)])
		node = node.get_parent()
	return String("|").join(parts)


func _ancestor_state(node: Node) -> String:
	var stylebox: GdssStylebox = GdssNodeBinder.get_primary_stylebox(node)
	if stylebox == null or stylebox == self:
		return ""
	return stylebox._get_state()


func _collect_descendant_layers() -> Array[Dictionary]:
	var layers: Array[Dictionary] = []
	if not GdssStylesheet.has_descendant_rules or ref == null:
		return layers
	var self_class: String = ref.get_class()
	var by_depth: Array[Array] = []
	var node: Node = ref.get_parent()
	var depth: int = 0
	while node != null and depth < MAX_ANCESTOR_WALK:
		depth += 1
		var container: Dictionary = _ancestor_descendants(node)
		if not container.is_empty():
			var at_depth: Array[Dictionary] = []
			var keys: PackedStringArray = [">>" + self_class]
			if depth == 1:
				keys.append(">" + self_class)
			for key: String in keys:
				var rule: Variant = container.get(key)
				if not rule is Dictionary or (rule as Dictionary).is_empty():
					continue
				at_depth.append({
					"entry": rule as Dictionary,
					"anc": _ancestor_state_overlay(rule as Dictionary, node),
					"vars": _ancestor_scoped_vars(node)})
			if not at_depth.is_empty():
				by_depth.append(at_depth)
		node = node.get_parent()
	by_depth.reverse()
	for group: Array in by_depth:
		for layer: Dictionary in group:
			layers.append(layer)
	return layers


func _ancestor_descendants(node: Node) -> Dictionary:
	var stylebox: GdssStylebox = GdssNodeBinder.get_primary_stylebox(node)
	if stylebox != null and stylebox != self:
		var resolved: Variant = stylebox._resolve_entry().get(GdssStylesheet.DESCENDANTS_KEY)
		return resolved if resolved is Dictionary else {}
	var entry: Dictionary = GdssStylesheet.parsed.get(node.get_class(), {})
	if entry.is_empty():
		return {}
	var container: Variant = entry.get(GdssStylesheet.DESCENDANTS_KEY)
	var result: Dictionary = container as Dictionary if container is Dictionary else {}
	for gdss_class_name: String in node.get_meta(GDSS.CLASSES_META, PackedStringArray()) as PackedStringArray:
		var override: Dictionary = _find_class_in_tree(entry.get("_classes", {}), gdss_class_name)
		var nested: Variant = override.get(GdssStylesheet.DESCENDANTS_KEY)
		if nested is Dictionary and not (nested as Dictionary).is_empty():
			result = _merge_descendants(result, nested as Dictionary)
	return result


func _ancestor_scoped_vars(node: Node) -> Dictionary:
	var stylebox: GdssStylebox = GdssNodeBinder.get_primary_stylebox(node)
	if stylebox == null or stylebox == self:
		return {}
	stylebox._resolve_entry()
	return stylebox._scoped_vars


func _ancestor_state_overlay(rule: Dictionary, node: Node) -> Dictionary:
	var state: String = _ancestor_state(node)
	if state.is_empty():
		return {}
	var props: Variant = rule.get(GdssStylesheet.ANCESTOR_STATE_PREFIX + state)
	if not props is Dictionary or (props as Dictionary).is_empty():
		return {}
	return {"all": (props as Dictionary).duplicate()}


func _has_ancestor_state_rules() -> bool:
	if not _ancestor_states_dirty:
		return _ancestor_states
	_ancestor_states = false
	_ancestor_states_dirty = false
	var container: Variant = _resolve_entry().get(GdssStylesheet.DESCENDANTS_KEY)
	if not container is Dictionary:
		return false
	for key: String in container as Dictionary:
		var rule: Variant = (container as Dictionary).get(key)
		if not rule is Dictionary:
			continue
		for state_key: String in rule as Dictionary:
			if state_key.begins_with(GdssStylesheet.ANCESTOR_STATE_PREFIX):
				_ancestor_states = true
				return true
	return false


func _notify_descendant_rules() -> void:
	if ref == null or not GdssStylesheet.has_descendant_rules:
		return
	if not _has_ancestor_state_rules():
		return
	_restyle_descendants(ref)


static func _restyle_descendants(node: Node) -> void:
	for child: Node in node.get_children(true):
		var styleboxes: Array[GdssStylebox] = GdssNodeBinder.get_styleboxes(child)
		var outgoing: Array[Dictionary] = []
		for stylebox: GdssStylebox in styleboxes:
			outgoing.append(stylebox._capture_animatable())
		for stylebox: GdssStylebox in styleboxes:
			stylebox._invalidate_entry_cache()
		for i: int in styleboxes.size():
			styleboxes.get(i)._restyle_from_ancestor(outgoing.get(i))
		_restyle_descendants(child)


func _capture_animatable() -> Dictionary:
	var outgoing: Dictionary = {}
	if ref == null or _applying:
		return outgoing
	var state: String = _get_state()
	var animatable: Dictionary = _get_animatable_props()
	for prop_name: String in animatable:
		if _tweened_values.has(prop_name):
			continue
		var prop: GdssProp = animatable.get(prop_name)
		var val: Variant = _get_parsed_val(prop_name, state, prop.get_default_value())
		if val != null:
			outgoing.set(prop_name, val)
	return outgoing


func _restyle_from_ancestor(outgoing: Dictionary) -> void:
	if ref == null or _applying:
		return
	var state: String = _get_state()
	for prop_name: String in outgoing:
		if GDSS.scaled_duration(_resolve_time(prop_name, state)) > 0.0:
			_tweened_values.set(prop_name, outgoing.get(prop_name))
	_start_transition(state, state)
	_apply_overrides(false)
	_safe_redraw()


func _build_override_entry(override_meta: Variant) -> Dictionary:
	if override_meta is String:
		return GdssStylesheet.parse_override_entry(override_meta)
	if override_meta is Dictionary:
		return {"all": (override_meta as Dictionary).duplicate()}
	return {}


func _resolve_override_patches(base: Dictionary, override_entry: Dictionary) -> Dictionary:
	var has_patch: bool = false
	for state_key: String in override_entry:
		var state_dict: Variant = override_entry.get(state_key)
		if not state_dict is Dictionary:
			continue
		for prop_name: String in (state_dict as Dictionary):
			var raw: Variant = (state_dict as Dictionary).get(prop_name)
			if raw is Dictionary and (raw as Dictionary).has("__gdss_composite4_patch__"):
				has_patch = true
	if not has_patch:
		return override_entry
	var resolved: Dictionary = override_entry.duplicate(true)
	for state_key: String in resolved:
		var state_dict: Variant = resolved.get(state_key)
		if not state_dict is Dictionary:
			continue
		for prop_name: String in (state_dict as Dictionary):
			var raw: Variant = (state_dict as Dictionary).get(prop_name)
			if not (raw is Dictionary and (raw as Dictionary).has("__gdss_composite4_patch__")):
				continue
			var patch: Dictionary = (raw as Dictionary).get("__gdss_composite4_patch__")
			var scratch: Dictionary = {prop_name: _base_composite_value(base, state_key, prop_name)}
			for index: Variant in patch:
				GdssStylesheet._fold_composite_component(scratch, prop_name, int(index), patch.get(index))
			(state_dict as Dictionary).set(prop_name, scratch.get(prop_name))
	return resolved


func _base_composite_value(base: Dictionary, state_key: String, prop_name: String) -> Variant:
	var raw: Variant = _raw_entry_val(base, state_key, prop_name)
	if raw != null:
		return raw if not raw is Dictionary else (raw as Dictionary).duplicate(true)
	var prop: GdssProp = GDSS.get_registry().property_list.get(prop_name)
	return prop.get_default_value() if prop != null else Vector4i.ZERO


func _resolve_value(raw: Variant, fallback: Variant, state_key: String = "") -> Variant:
	if raw is Dictionary and (raw as Dictionary).has("__gdss_composite4__"):
		var parts: Array = (raw as Dictionary).get("__gdss_composite4__")
		return Vector4i(_resolve_composite_part(parts.get(0)), _resolve_composite_part(parts.get(1)), _resolve_composite_part(parts.get(2)), _resolve_composite_part(parts.get(3)))
	if raw is Dictionary and (raw as Dictionary).has("__gdss_composite2__"):
		var parts2: Array = (raw as Dictionary).get("__gdss_composite2__")
		return Vector2(_resolve_composite_part_f(parts2.front()), _resolve_composite_part_f(parts2.back()))
	if raw is Dictionary and (raw as Dictionary).has(GdssStylesheet.COLOR4_KEY):
		var sides: Array = (raw as Dictionary).get(GdssStylesheet.COLOR4_KEY)
		var resolved_sides: Array = []
		for side: Variant in sides:
			resolved_sides.append(_resolve_value(side, fallback, state_key))
		return resolved_sides
	if raw is Dictionary and (raw as Dictionary).has("__gdss_calc__"):
		return _eval_calc((raw as Dictionary).get("__gdss_calc__"))
	raw = _resolve_sentinel(raw, fallback)
	if raw is Dictionary:
		var d: Dictionary = raw as Dictionary
		if d.has("__gdss_method__"):
			return _call_method(d, fallback, state_key)
	if raw is String:
		var s: String = raw as String
		if not s.is_empty() and s.unicode_at(0) == 35:
			if Color.html_is_valid(s):
				return Color.html(s)
			return raw
		if not s.begins_with("__gdss_"):
			var named: Color = GdssStylesheet.parse_named_color(s, Color(-1, -1, -1, -1))
			if named.r != -1:
				return named
	return raw


func _apply_font_transform(control: Variant, node_type: GdssNodeType, skew: Vector2, embolden: float) -> void:
	if control == null or node_type == null:
		return
	var neutral: bool = is_zero_approx(skew.x) and is_zero_approx(skew.y) and is_zero_approx(embolden)
	for item: String in node_type.fonts:
		var current: Font = control.get_theme_font(item)
		var marked: bool = current is FontVariation and (current as FontVariation).has_meta(&"gdss_font_transform")
		if neutral:
			if marked and control.has_theme_font_override(item):
				control.remove_theme_font_override(item)
			continue
		var xform: Transform2D = Transform2D(Vector2(1.0, skew.y), Vector2(skew.x, 1.0), Vector2.ZERO)
		if marked and (current as FontVariation).variation_transform == xform \
			and is_equal_approx((current as FontVariation).variation_embolden, embolden):
			continue
		var variation: FontVariation = FontVariation.new()
		variation.base_font = (current as FontVariation).base_font if marked else current
		variation.variation_transform = xform
		variation.variation_embolden = embolden
		variation.set_meta(&"gdss_font_transform", true)
		control.add_theme_font_override(item, variation)


func _refresh_font_transform(control: Variant, node_type: GdssNodeType) -> void:
	if control == null or node_type == null or node_type.fonts.is_empty():
		return
	var entry: Dictionary = _resolve_entry()
	var state: String = _get_state()
	var skew: Variant = _tweened_values.get("char_skew", _get_val_cached("char_skew", entry, state, Vector2.ZERO))
	var embolden: Variant = _tweened_values.get("char_embolden", _get_val_cached("char_embolden", entry, state, 0.0))
	_apply_font_transform(control, node_type,
		skew if skew is Vector2 else Vector2.ZERO,
		float(embolden) if embolden is int or embolden is float else 0.0)

func _splat_shorthand(key: String, value: Variant) -> Variant:
	if not (value is int or value is float):
		return value
	var prop: GdssProp = GDSS.get_registry().property_list.get(key)
	if prop == null:
		return value
	if prop.type == GDSS.Type.COMPOSITE4:
		return Vector4i(int(value), int(value), int(value), int(value))
	if prop.type == GDSS.Type.VECTOR2:
		return Vector2(float(value), float(value))
	return value


func _eval_calc(node: Variant) -> float:
	if not node is Dictionary:
		return 0.0
	var d: Dictionary = node as Dictionary
	if d.has("calc_num"):
		return float(d.get("calc_num"))
	if d.has("calc_ref"):
		return _calc_ref_value(d.get("calc_ref"))
	if d.has("calc_neg"):
		return -_eval_calc(d.get("calc_neg"))
	if d.has("calc_op"):
		var l: float = _eval_calc(d.get("l"))
		var r: float = _eval_calc(d.get("r"))
		match d.get("calc_op"):
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


func _resolve_composite_part_f(part: String) -> float:
	if part.is_valid_float():
		return float(part)
	var resolved: Variant = _resolve_sentinel(part, 0.0)
	if resolved is int or resolved is float:
		return float(resolved)
	if resolved is String and (resolved as String).is_valid_float():
		return float(resolved)
	return 0.0


func _resolve_method_args(descriptor: Dictionary, state_key: String = "") -> Array[Variant]:
	var method_name: String = descriptor.get("__gdss_method__")
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
		if s.begins_with("__gdss_local__") and _scoped_vars.has(s.substr("__gdss_local__".length())):
			has_live_ref = true
			break
	var cache_key: String = ""
	if not has_live_ref:
		cache_key = method_name + "\n" + "\n".join(PackedStringArray(raw_args))
		if _method_args_cache.has(cache_key):
			return _method_args_cache.get(cache_key)
	var method: GdssMethod = GDSS._get_gdss_methods().get(method_name)
	var resolved: Array[Variant] = []
	for arg_index: int in raw_args.size():
		var param: GdssMethod.Param = method.parameters.get(arg_index) if method != null and arg_index < method.parameters.size() else null
		if raw_args.get(arg_index) is Dictionary:
			resolved.append(_resolve_value(raw_args.get(arg_index), null, state_key))
			continue
		var stripped: String = (raw_args.get(arg_index) as String).strip_edges()
		if stripped == "pass":
			resolved.append(method.parameters.get(arg_index).default_value if method != null and arg_index < method.parameters.size() else null)
		elif stripped.begins_with("__gdss_global__"):
			var key: String = stripped.substr("__gdss_global__".length())
			resolved.append(GdssStylesheet.globals.get(key, null))
		elif stripped.begins_with("__gdss_instance__"):
			var key: String = stripped.substr("__gdss_instance__".length())
			if ref != null and GdssStylesheet._instance_vars.has(ref.get_instance_id()):
				resolved.append(GdssStylesheet._instance_vars.get(ref.get_instance_id()).get(key, null))
			else:
				resolved.append(GdssStylesheet._instance_defaults.get(key, null))
		elif stripped.begins_with("__gdss_local__"):
			resolved.append(_resolve_sentinel(stripped, null))
		elif stripped.begins_with("$"):
			var key: String = stripped.substr(1)
			if GdssStylesheet.globals.has(key):
				resolved.append(GdssStylesheet.globals.get(key))
			elif ref != null and GdssStylesheet._instance_vars.has(ref.get_instance_id()):
				resolved.append(GdssStylesheet._instance_vars.get(ref.get_instance_id()).get(key, null))
			else:
				resolved.append(GdssStylesheet._instance_defaults.get(key, null))
		else:
			var unquoted: String = stripped.trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'")
			var resolved_arg: Variant = method._resolve_arg(unquoted) if method != null else unquoted
			if resolved_arg is String and param != null and param.type == GdssMethod.ParamType.COLOR:
				var named: Color = GdssStylesheet.parse_named_color(resolved_arg as String, Color(-1, -1, -1, -1))
				if named.r != -1:
					resolved_arg = named
			resolved.append(resolved_arg)
	if not has_live_ref:
		_method_args_cache.set(cache_key, resolved)
	return resolved


func _call_method(descriptor: Dictionary, fallback: Variant, state_key: String = "") -> Variant:
	var name: String = descriptor.get("__gdss_method__")
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
	if entry.has(state) and (entry.get(state) as Dictionary).has(key):
		raw = entry.get(state).get(key)
	elif entry.has("all") and (entry.get("all") as Dictionary).has(key):
		raw = entry.get("all").get(key)
	else:
		return fallback
	return _splat_shorthand(key, _resolve_value(raw, fallback, state))


func _get_state() -> String:
	if not _slot_state.is_empty():
		return _slot_state
	if ref == null:
		return "all"
	if not current_state.is_empty():
		return current_state
	var node_type: GdssNodeType = _resolve_gdss_node()
	if node_type and not node_type.states.is_empty():
		return node_type.states.get(0)
	return "all"


func _resolve_sentinel(raw: Variant, fallback: Variant) -> Variant:
	if not raw is String:
		return raw
	var s: String = raw as String
	if not s.begins_with("__gdss_"):
		return raw
	if s.begins_with("__gdss_global__"):
		var name: String = s.substr("__gdss_global__".length())
		if GdssStylesheet.globals.has(name):
			return GdssStylesheet.globals.get(name)
		if GdssStylesheet._global_defaults.has(name):
			return GdssStylesheet._global_defaults.get(name)
		return fallback
	if s.begins_with("__gdss_instance__"):
		var name: String = s.substr("__gdss_instance__".length())
		if ref != null:
			var id: int = ref.get_instance_id()
			if GdssStylesheet._instance_vars.has(id) and GdssStylesheet._instance_vars.get(id).has(name):
				return GdssStylesheet._instance_vars.get(id).get(name)
		if GdssStylesheet._instance_defaults.has(name):
			return GdssStylesheet._instance_defaults.get(name)
		return fallback
	if s.begins_with("__gdss_local__"):
		var name: String = s.substr("__gdss_local__".length())
		if _scoped_vars.has(name):
			return _resolve_sentinel(_scoped_vars.get(name), fallback)
		if GdssStylesheet._local_vars.has(name):
			return GdssStylesheet._local_vars.get(name)
		return fallback
	if s.begins_with("__gdss_local_method__"):
		var name: String = s.substr("__gdss_local_method__".length())
		if GdssStylesheet._local_vars.has(name):
			return GdssStylesheet._local_vars.get(name)
		return fallback
	return raw


func _get_val(key: String, fallback: Variant = null) -> Variant:
	if ref == null:
		return fallback
	if _tweened_values.has(key):
		return _tweened_values.get(key)
	return _get_val_cached(key, _resolve_entry(), _get_state(), fallback)


func _get_val_cached(key: String, entry: Dictionary, state: String, fallback: Variant) -> Variant:
	if _tweened_values.has(key):
		return _tweened_values.get(key)
	if entry.is_empty():
		return fallback
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
	return _splat_shorthand(key, _resolve_value(raw, fallback, state))


func _get_raw_parsed_val(key: String, state: String) -> Variant:
	var entry: Dictionary = _resolve_entry()
	if entry.is_empty():
		return null
	var raw: Variant = null
	if entry.has(state) and entry.get(state).has(key):
		raw = entry.get(state).get(key)
	elif entry.has("all") and entry.get("all").has(key):
		raw = entry.get("all").get(key)
	else:
		return null
	raw = _resolve_sentinel(raw, null)
	if raw is String and (raw as String).begins_with("__gdss_local_method__"):
		var local_key: String = (raw as String).substr("__gdss_local_method__".length())
		return GdssStylesheet._local_vars.get(local_key, null)
	return raw


func _build_style_vals(node_type: GdssNodeType, entry: Dictionary, state: String) -> Dictionary:
	if not _tweened_values.is_empty():
		if _style_tween_state != state or _style_tween_session != _tween_session:
			_style_tween_state = state
			_style_tween_session = _tween_session
			_style_vals_tween.clear()
			_style_dynamic_tween.clear()
			for prop: GdssProp in node_type.get_style_props():
				var fv: Variant = _get_val_cached(prop.name, entry, state, prop.get_default_value())
				_style_vals_tween.set(prop.name, fv if fv != null else prop.get_default_value())
				if _is_dynamic_raw(_raw_entry_val(entry, state, prop.name)):
					_style_dynamic_tween.append(prop)
			return _style_vals_tween
		for prop: GdssProp in _style_dynamic_tween:
			var dv: Variant = _get_val_cached(prop.name, entry, state, prop.get_default_value())
			_style_vals_tween.set(prop.name, dv if dv != null else prop.get_default_value())
		for key: String in _tweened_values:
			if _style_vals_tween.has(key):
				_style_vals_tween.set(key, _tweened_values.get(key))
		return _style_vals_tween
	if _style_vals_state != state:
		_style_vals_cache.clear()
		_style_dynamic.clear()
		_style_vals_state = state
		for prop: GdssProp in node_type.get_style_props():
			var rv: Variant = _get_val_cached(prop.name, entry, state, prop.get_default_value())
			_style_vals_cache.set(prop.name, rv if rv != null else prop.get_default_value())
			if _is_dynamic_raw(_raw_entry_val(entry, state, prop.name)):
				_style_dynamic.append(prop)
		return _style_vals_cache
	for prop: GdssProp in _style_dynamic:
		var dv: Variant = _get_val_cached(prop.name, entry, state, prop.get_default_value())
		_style_vals_cache.set(prop.name, dv if dv != null else prop.get_default_value())
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
		if d.has("__gdss_composite4__") or d.has("__gdss_composite2__"):
			for part: Variant in d.get("__gdss_composite4__", d.get("__gdss_composite2__")):
				if part is String and ((part as String).begins_with("__gdss_global__") or (part as String).begins_with("__gdss_instance__")):
					return true
			return false
		if d.has(GdssStylesheet.COLOR4_KEY):
			for side: Variant in d.get(GdssStylesheet.COLOR4_KEY):
				if _is_dynamic_raw(side):
					return true
			return false
		if d.has("__gdss_calc__"):
			return _calc_has_dynamic_ref(d.get("__gdss_calc__"))
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
		var r: String = d.get("calc_ref")
		return r.begins_with("__gdss_global__") or r.begins_with("__gdss_instance__") or r.begins_with("$")
	if d.has("calc_neg"):
		return _calc_has_dynamic_ref(d.get("calc_neg"))
	if d.has("calc_op"):
		return _calc_has_dynamic_ref(d.get("l")) or _calc_has_dynamic_ref(d.get("r"))
	return false


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if ref == null:
		return
	var node_type: GdssNodeType = _resolve_gdss_node()
	if node_type == null:
		return
	if not Engine.is_editor_hint() and ref is CanvasItem and _slot_state.is_empty() and not node_type.is_static and not _state_sync_queued:
		var active: String = node_type.resolve_state(ref as CanvasItem)
		if active != current_state:
			_state_sync_queued = true
			_sync_active_state.call_deferred()
	var entry: Dictionary = _resolve_entry()
	var state: String = _get_state()
	_apply_dynamic_nonstyle(node_type, entry, state)
	var vals: Dictionary = _build_style_vals(node_type, entry, state)
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
	var shadow_src: Variant = vals.get("shadow_color", _DEFAULT_SHADOW_COLOR)
	if _max_side(shadow) > 0.5:
		var shadow_outer: Rect2 = rect.grow_individual(shadow.x, shadow.z, shadow.y, shadow.w)
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
	var border_raw: Variant = vals.get("border_color", Color.TRANSPARENT)
	var border_src: Variant = _border_base(border_raw)
	var border_sides: Array = _border_side_colors(border_raw)
	var has_border: bool = border.x > 0 or border.y > 0 or border.z > 0 or border.w > 0
	if has_border:
		var inner_rect: Rect2 = rect.grow_individual(-border.x, -border.z, -border.y, -border.w)
		if inner_rect.has_area():
			if not border_sides.is_empty():
				_draw_ring_sides(to_canvas_item, inner_rect, rect, corner_radius, border_sides, detail, skew_x, skew_y)
			elif border_src is GdssGradient:
				_draw_linear_gradient_ring(to_canvas_item, border_src as GdssGradient, inner_rect, rect, corner_radius, detail, skew_x, skew_y)
			elif border_src is GdssBlur:
				var border_tint: Color = (border_src as GdssBlur).tint
				if border_tint.a > 0.0:
					_draw_ring(to_canvas_item, inner_rect, rect, corner_radius, border_tint, aa_size, detail, skew_x, skew_y)
			elif border_src is Color and (border_src as Color).a > 0.0:
				_draw_ring(to_canvas_item, inner_rect, rect, corner_radius, border_src as Color, aa_size, detail, skew_x, skew_y)


func _side_colors(src: Variant, fallback: Color) -> Array:
	var sides: Array = src as Array if src is Array else [src, src, src, src]
	var result: Array = []
	for side: Variant in sides:
		result.append(side if side is Color else fallback)
	return result


func _border_side_colors(src: Variant) -> Array:
	if not src is Array:
		return []
	var sides: Array = src as Array
	var uniform: bool = true
	for side: Variant in sides:
		if not side is Color:
			return []
		if side != sides.front():
			uniform = false
	return [] if uniform else sides


func _border_base(src: Variant) -> Variant:
	if not src is Array:
		return src
	var sides: Array = src as Array
	for side: Variant in sides:
		if not side is Color:
			return side
	return sides.front()


static func _max_side(sides: Vector4) -> float:
	return maxf(maxf(sides.x, sides.y), maxf(sides.z, sides.w))


static func _get_shared_shader() -> Shader:
	if _shader == null:
		_shader = load("res://addons/gdss/render/shaders/gdss_panel.gdshader") as Shader
	return _shader


static func _get_blur_shader() -> Shader:
	if _blur_shader == null:
		_blur_shader = load("res://addons/gdss/render/shaders/gdss_blur.gdshader") as Shader
	return _blur_shader


func _ensure_gpu_ci(to_canvas_item: RID, want_blur: bool = false) -> void:
	if not _gpu_ci.is_valid():
		_gpu_ci = RenderingServer.canvas_item_create()
		_gpu_material = ShaderMaterial.new()
		_gpu_is_blur = want_blur
		_gpu_material.shader = _get_blur_shader() if want_blur else _get_shared_shader()
		RenderingServer.canvas_item_set_material(_gpu_ci, _gpu_material.get_rid())
		RenderingServer.canvas_item_set_draw_behind_parent(_gpu_ci, true)
		RenderingServer.canvas_item_set_copy_to_backbuffer(_gpu_ci, want_blur, Rect2())
		_gpu_parent = RID()
	elif _gpu_is_blur != want_blur:
		_gpu_is_blur = want_blur
		_gpu_material.shader = _get_blur_shader() if want_blur else _get_shared_shader()
		RenderingServer.canvas_item_set_copy_to_backbuffer(_gpu_ci, want_blur, Rect2())
		_gpu_last.clear()
	if _gpu_parent != to_canvas_item:
		RenderingServer.canvas_item_set_parent(_gpu_ci, to_canvas_item)
		_gpu_parent = to_canvas_item


func _in_clip_group() -> bool:
	var node: Node = ref
	while node:
		if node is CanvasGroup:
			return true
		if node is CanvasItem and node.clip_children != CanvasItem.CLIP_CHILDREN_DISABLED:
			return true
		node = node.get_parent()
	return false


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
	_gpu_last.set(key, value)
	_gpu_material.set_shader_parameter(key, value)


func _draw_gpu(to_canvas_item: RID, rect: Rect2, vals: Dictionary) -> void:
	var bg: Variant = _at_blur_quality(vals.get("bg_color", Color.TRANSPARENT))
	var border_raw: Variant = vals.get("border_color", Color.TRANSPARENT)
	var border_src: Variant = _at_blur_quality(_border_base(border_raw))
	var border_sides: Array = _border_side_colors(border_raw)
	var want_blur: bool = bg is GdssBlur or border_src is GdssBlur
	if want_blur and _in_clip_group():
		want_blur = false
		if not _gpu_warned_clip:
			_gpu_warned_clip = true
			push_warning("[GDSS] Blur disabled on %s: a clip_children or CanvasGroup ancestor renders its children into the backbuffer, so the engine binds a solid white screen texture and the blur would draw pure white. Mask without a clip group to keep the blur." % ref)
	_ensure_gpu_ci(to_canvas_item, want_blur)
	var shadow: Vector4 = Vector4(vals.get("shadow", Vector4i.ZERO))
	var shadow_offset: Vector2 = vals.get("shadow_offset", Vector2.ZERO)
	var pad: Vector4 = Vector4.ZERO
	if _max_side(shadow) > 0.5:
		var spill_x: float = maxf(shadow.z, shadow.w) * _SHADOW_CORNER_SPILL
		var spill_y: float = maxf(shadow.x, shadow.y) * _SHADOW_CORNER_SPILL
		pad = Vector4(
			maxf(shadow.x, spill_x) + maxf(-shadow_offset.x, 0.0) + 2.0,
			maxf(shadow.y, spill_x) + maxf(shadow_offset.x, 0.0) + 2.0,
			maxf(shadow.z, spill_y) + maxf(-shadow_offset.y, 0.0) + 2.0,
			maxf(shadow.w, spill_y) + maxf(shadow_offset.y, 0.0) + 2.0,
		)
	var quad: Rect2 = rect.grow_individual(pad.x, pad.z, pad.y, pad.w)
	var pad_min: Vector2 = Vector2(pad.x / quad.size.x, pad.z / quad.size.y)
	var pad_max: Vector2 = Vector2(pad.y / quad.size.x, pad.w / quad.size.y)
	var anti_aliasing: bool = vals.get("anti_aliasing", true)
	_set_param(&"u_size", quad.size)
	_set_param(&"u_pad", pad)
	_set_param(&"u_corner_radius", Vector4(vals.get("corner_radius", Vector4i.ZERO)))
	_set_param(&"u_border_widths", Vector4(vals.get("border", Vector4i.ZERO)))
	_set_param(&"u_shadow", shadow)
	_set_param(&"u_aa", 1.0 if anti_aliasing else 0.0)
	var clip_src: Variant = vals.get("clip_path")
	if clip_src is GdssClipPath:
		var clip_path: GdssClipPath = clip_src
		_set_param(&"u_clip_count", clip_path.count())
		_set_param(&"u_clip", clip_path.padded())
	else:
		_set_param(&"u_clip_count", 0)
	_set_param(&"u_shadow_blur", float(vals.get("shadow_blur", -1.0)))
	_set_param(&"u_shadow_offset", shadow_offset)
	var shadow_src: Variant = vals.get("shadow_color", _DEFAULT_SHADOW_COLOR)
	_set_param(&"u_shadow_color", shadow_src if shadow_src is Color else _DEFAULT_SHADOW_COLOR)
	var tint_src: Variant = vals.get("bg_tint", Color.WHITE)
	_fill_tint = tint_src if tint_src is Color else Color.WHITE
	var scroll_src: Variant = vals.get("bg_scroll", Vector2.ZERO)
	_fill_scroll = scroll_src if scroll_src is Vector2 else Vector2.ZERO
	var scale_src: Variant = vals.get("bg_texture_scale", Vector2.ZERO)
	_fill_scale = scale_src if scale_src is Vector2 else Vector2.ZERO
	_resolve_fill_texture(vals.get("bg_texture"), bg, GDSS.scaled_duration(_resolve_time("bg_texture", _get_state())))
	_push_fill(bg, pad_min, pad_max)
	_push_border(border_src, border_sides, pad_min, pad_max)
	var xform: Transform2D = _skew_transform(rect, vals.get("skew_x", 0.0), vals.get("skew_y", 0.0))
	if not _gpu_emitted or quad != _gpu_quad or xform != _gpu_xform:
		_gpu_quad = quad
		_gpu_xform = xform
		_gpu_emitted = true
		RenderingServer.canvas_item_clear(_gpu_ci)
		RenderingServer.canvas_item_set_transform(_gpu_ci, xform)
		RenderingServer.canvas_item_add_rect(_gpu_ci, quad, Color.WHITE)


static func _at_blur_quality(value: Variant) -> Variant:
	if not value is GdssBlur:
		return value
	match GDSS.blur_quality:
		GDSS.BlurQuality.OFF:
			return (value as GdssBlur).tint
		GDSS.BlurQuality.LOW:
			return (value as GdssBlur).to_plain()
	return value


func _resolve_fill_texture(src: Variant, fallback: Variant, duration: float) -> void:
	if not (src is GdssTexture or src is Texture2D):
		src = fallback
	_fill_texture = null
	_fill_aspect = false
	_fill_repeat = false
	_fill_nearest = false
	_fill_natural = false
	if src is GdssTexture:
		var wrapped: GdssTexture = src
		_fill_texture = wrapped.texture
		_fill_aspect = wrapped.preserve_aspect
		_fill_repeat = wrapped.repeat
		_fill_natural = wrapped.repeat
		_fill_nearest = wrapped.is_nearest()
	elif src is Texture2D:
		_fill_texture = src
	if _fill_scroll != Vector2.ZERO or _fill_scale != Vector2.ZERO:
		_fill_repeat = true
	_fill_texture = _fade_to(_fill_texture, duration)


func _fade_to(target: Texture2D, duration: float) -> Texture2D:
	if target == _fade_target:
		return _fade_texture
	_fade_target = target
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	if duration <= 0.0 or ref == null or not ref.is_inside_tree():
		_fade_texture = target
		_fade_value = 1.0
		return _fade_texture
	if target != null and target != _fade_texture:
		_fade_texture = target
		_fade_value = 0.0
	_fade_tween = (Engine.get_main_loop() as SceneTree).create_tween()
	_fade_tween.tween_method(func(v: float) -> void:
		_fade_value = v
		_safe_redraw()
	, _fade_value, 1.0 if target != null else 0.0, duration)
	if target == null:
		_fade_tween.finished.connect(func() -> void:
			if _fade_target == null:
				_fade_texture = null
				_fade_value = 1.0
				_safe_redraw()
		)
	return _fade_texture


func _push_fill(bg: Variant, pad_min: Vector2, pad_max: Vector2) -> void:
	if _fill_texture != null:
		_set_param(&"u_fill_mode", 3)
		_set_param(&"u_tex", null if _fill_nearest else _fill_texture)
		_set_param(&"u_tex_nearest", _fill_texture if _fill_nearest else null)
		_set_param(&"u_fill_nearest", 1.0 if _fill_nearest else 0.0)
		_set_param(&"u_fill_repeat", 1.0 if _fill_repeat else 0.0)
		_set_param(&"u_fill_natural", 1.0 if _fill_natural else 0.0)
		_set_param(&"u_fill_fade", _fade_value)
		_set_param(&"u_fill_tint", _fill_tint)
		_set_param(&"u_fill_scroll", _fill_scroll)
		_set_param(&"u_fill_scale", _fill_scale)
		_set_param(&"u_fill_aspect", 1.0 if _fill_aspect else 0.0)
		_set_param(&"u_fill_a", bg if bg is Color else Color.TRANSPARENT)
		return
	if bg is GdssGradient:
		var grad: GdssGradient = bg as GdssGradient
		_set_param(&"u_fill_a", grad.color_a)
		_set_param(&"u_fill_b", grad.color_b)
		_set_param(&"u_grad_offsets", grad.offsets)
		_set_param(&"u_grad_p0", _remap_uv(grad.p0, pad_min, pad_max))
		_set_param(&"u_grad_p1", _remap_uv(grad.p1, pad_min, pad_max))
		_set_param(&"u_fill_mode", grad.mode)
	elif bg is GdssBlur:
		var blur: GdssBlur = bg as GdssBlur
		_set_param(&"u_fill_a", blur.tint)
		_set_param(&"u_fill_glass", Vector4(blur.strength, blur.refraction, blur.highlight, blur.saturation))
		if blur.strength_end != blur.strength:
			_set_param(&"u_fill_mode", 5)
			_set_param(&"u_fill_glass2", Vector4(blur.strength_end, blur.refraction, blur.highlight, blur.saturation))
			_set_param(&"u_grad_offsets", blur.grad_offsets)
			_set_param(&"u_grad_p0", _remap_uv(blur.grad_p0, pad_min, pad_max))
			_set_param(&"u_grad_p1", _remap_uv(blur.grad_p1, pad_min, pad_max))
		else:
			_set_param(&"u_fill_mode", 4)
	elif bg is Color:
		_set_param(&"u_fill_mode", 0)
		_set_param(&"u_fill_a", bg as Color)
	else:
		_set_param(&"u_fill_mode", 0)
		_set_param(&"u_fill_a", Color.TRANSPARENT)


func _push_border(border_src: Variant, border_sides: Array, pad_min: Vector2, pad_max: Vector2) -> void:
	if not border_sides.is_empty():
		_set_param(&"u_border_mode", 4)
		_set_param(&"u_border_left", border_sides.get(0))
		_set_param(&"u_border_right", border_sides.get(1))
		_set_param(&"u_border_top", border_sides.get(2))
		_set_param(&"u_border_bottom", border_sides.get(3))
		return
	if border_src is GdssGradient:
		var grad: GdssGradient = border_src as GdssGradient
		_set_param(&"u_border_mode", 1)
		_set_param(&"u_border_a", grad.color_a)
		_set_param(&"u_border_b", grad.color_b)
		_set_param(&"u_border_p0", _remap_uv(grad.p0, pad_min, pad_max))
		_set_param(&"u_border_p1", _remap_uv(grad.p1, pad_min, pad_max))
	elif border_src is GdssBlur:
		var blur: GdssBlur = border_src as GdssBlur
		_set_param(&"u_border_a", blur.tint)
		_set_param(&"u_border_glass", Vector4(blur.strength, blur.refraction, blur.highlight, blur.saturation))
		if blur.strength_end != blur.strength:
			_set_param(&"u_border_mode", 3)
			_set_param(&"u_border_glass2", Vector4(blur.strength_end, blur.refraction, blur.highlight, blur.saturation))
			_set_param(&"u_border_p0", _remap_uv(blur.grad_p0, pad_min, pad_max))
			_set_param(&"u_border_p1", _remap_uv(blur.grad_p1, pad_min, pad_max))
		else:
			_set_param(&"u_border_mode", 2)
	elif border_src is Color:
		_set_param(&"u_border_mode", 0)
		_set_param(&"u_border_a", border_src as Color)
	else:
		_set_param(&"u_border_mode", 0)
		_set_param(&"u_border_a", Color.TRANSPARENT)


func _remap_uv(uv: Vector2, pad_min: Vector2, pad_max: Vector2) -> Vector2:
	return pad_min + uv * (Vector2.ONE - pad_min - pad_max)


func _skew_transform(rect: Rect2, skew_x: float, skew_y: float) -> Transform2D:
	if skew_x == 0.0 and skew_y == 0.0:
		return Transform2D.IDENTITY
	var center: Vector2 = rect.position + rect.size * 0.5
	var bx: Vector2 = Vector2(1.0, skew_y)
	var by: Vector2 = Vector2(skew_x, 1.0)
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
		var local: Vector2 = (points.get(i) - rect.position) / rect.size
		uvs.set(i, uv_offset + local * uv_scale)
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
		var p0: Vector2 = inner_points.get(i0)
		var p1: Vector2 = outer_points.get(o0)
		var p2: Vector2 = outer_points.get(o1)
		var p3: Vector2 = inner_points.get(i1)
		if p0.is_equal_approx(p1) or p0.is_equal_approx(p3) or p1.is_equal_approx(p2) or p2.is_equal_approx(p3) or p0.is_equal_approx(p2) or p1.is_equal_approx(p3):
			continue
		var quad: PackedVector2Array = PackedVector2Array([p0, p1, p2, p3])
		var uvs: PackedVector2Array
		uvs.resize(4)
		var colors: PackedColorArray
		colors.resize(4)
		for j: int in 4:
			uvs.set(j, (quad.get(j) - outer_rect.position) / outer_rect.size)
			var is_outer: bool = j == 1 or j == 2
			colors.set(j, Color(1, 1, 1, 0.0 if (fade and is_outer) else 1.0))
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
		var p: Vector2 = points.get(i)
		var t: float = ((p - rect.position) / rect.size).dot(dir) * 0.5 + 0.5
		colors.set(i, _sample_grad(c1, c2, grad.offsets, t))
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
	verts.set(0, center)
	cols.set(0, _sample_grad(grad.color_a, grad.color_b, grad.offsets, 0.0))
	for i: int in n:
		verts.set(i + 1, perimeter.get(i))
		var uv: Vector2 = (perimeter.get(i) - rect.position) / rect.size
		cols.set(i + 1, _sample_grad(grad.color_a, grad.color_b, grad.offsets, (uv - grad.p0).length() / radius))
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
		var p0: Vector2 = inner_points.get(i0)
		var p1: Vector2 = outer_points.get(o0)
		var p2: Vector2 = outer_points.get(o1)
		var p3: Vector2 = inner_points.get(i1)
		var quad: PackedVector2Array = PackedVector2Array([p0, p1, p2, p3])
		var quad_colors: PackedColorArray
		quad_colors.resize(4)
		for j: int in 4:
			var p: Vector2 = quad.get(j)
			var t: float = ((p - outer_rect.position) / outer_rect.size).dot(dir) * 0.5 + 0.5
			var col: Color = _sample_grad(c1, c2, grad.offsets, t)
			var is_outer: bool = j == 1 or j == 2
			if fade and is_outer:
				col.a = 0.0
			quad_colors.set(j, col)
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
			colors.set(i, color)
		for i: int in outer_points.size():
			colors.set(inner_points.size() + i, Color(color.r, color.g, color.b, 0.0))
	else:
		colors = [color]
	
	RenderingServer.canvas_item_add_triangle_array(to_canvas_item, indices, all_points, colors)


func _draw_ring_sides(to_canvas_item: RID, inner_rect: Rect2, outer_rect: Rect2, corner_radii: Vector4, colors: Array, detail: int, skew_x: float, skew_y: float) -> void:
	var outer_fitted: Vector4 = _fit_corners(corner_radii, outer_rect)
	var inner_fitted: Vector4 = _match_corner_counts(_fit_corners(corner_radii, inner_rect), outer_fitted)
	var inner_points: PackedVector2Array = _apply_skew(_get_rounded_rect(inner_rect, inner_fitted, detail), inner_rect, skew_x, skew_y)
	var outer_points: PackedVector2Array = _apply_skew(_get_rounded_rect(outer_rect, outer_fitted, detail), outer_rect, skew_x, skew_y)
	var count: int = outer_points.size()
	if inner_points.size() != count:
		return
	var splits: PackedInt32Array = _corner_splits(outer_fitted, detail)
	var spans: Array[Vector2i] = [
		Vector2i(splits.get(3), splits.get(0)),
		Vector2i(splits.get(1), splits.get(2)),
		Vector2i(splits.get(0), splits.get(1)),
		Vector2i(splits.get(2), splits.get(3)),
	]
	for side: int in 4:
		var color: Color = colors.get(side)
		if color.a <= 0.0:
			continue
		_draw_ring_span(to_canvas_item, inner_points, outer_points, spans.get(side), count, color)


func _draw_ring_span(to_canvas_item: RID, inner_points: PackedVector2Array, outer_points: PackedVector2Array, span: Vector2i, count: int, color: Color) -> void:
	var quads: int = posmod(span.y - span.x, count)
	var verts: PackedVector2Array
	var indices: PackedInt32Array
	for i: int in quads:
		var near: int = (span.x + i) % count
		var far: int = (span.x + i + 1) % count
		var base: int = verts.size()
		verts.append_array(PackedVector2Array([inner_points.get(near), outer_points.get(near), outer_points.get(far), inner_points.get(far)]))
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	if indices.is_empty():
		return
	RenderingServer.canvas_item_add_triangle_array(to_canvas_item, indices, verts, PackedColorArray([color]))


func _corner_splits(radii: Vector4, detail: int) -> PackedInt32Array:
	var splits: PackedInt32Array
	var index: int = 0
	for corner: int in 4:
		var points: int = 1 if radii[corner] == 0.0 else detail + 1
		splits.append(index + points / 2)
		index += points
	return splits


func _match_corner_counts(inner: Vector4, outer: Vector4) -> Vector4:
	return Vector4(
		maxf(inner.x, 0.001) if outer.x > 0.0 else 0.0,
		maxf(inner.y, 0.001) if outer.y > 0.0 else 0.0,
		maxf(inner.z, 0.001) if outer.z > 0.0 else 0.0,
		maxf(inner.w, 0.001) if outer.w > 0.0 else 0.0,
	)


func _triangulate_ring(inner_size: int, outer_size: int) -> PackedInt32Array:
	var key: int = inner_size * 100003 + outer_size
	if _tri_cache.has(key):
		return _tri_cache.get(key)
	var indices: PackedInt32Array
	var total: int = max(inner_size, outer_size)
	for i: int in total:
		var i0: int = i % inner_size
		var i1: int = (i + 1) % inner_size
		var o0: int = i % outer_size + inner_size
		var o1: int = (i + 1) % outer_size + inner_size
		indices.append_array([i0, o0, o1, i0, o1, i1])
	_tri_cache.set(key, indices)
	return indices


func _get_rounded_rect(rect: Rect2, corner_radii: Vector4, detail: int = 8) -> PackedVector2Array:
	var key: int = int(rect.position.x * 100.0)
	key = key * 92821 + int(rect.position.y * 100.0)
	key = key * 92821 + int(rect.size.x * 100.0)
	key = key * 92821 + int(rect.size.y * 100.0)
	key = key * 92821 + int(corner_radii.x * 100.0)
	key = key * 92821 + int(corner_radii.y * 100.0)
	key = key * 92821 + int(corner_radii.z * 100.0)
	key = key * 92821 + int(corner_radii.w * 100.0)
	key = key * 92821 + detail
	if _rr_cache.has(key):
		return _rr_cache.get(key)
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
				var theta: float = _corner_start_angles.get(corner_idx) + (PI * 0.5) * i / detail
				points.append(corner_centers.get(corner_idx) + Vector2(cos(theta), sin(theta)) * radius)
	if _rr_cache.size() > 2048:
		_rr_cache.clear()
	_rr_cache.set(key, points)
	return points


func _apply_skew(points: PackedVector2Array, rect: Rect2, skew_x: float, skew_y: float) -> PackedVector2Array:
	if skew_x == 0.0 and skew_y == 0.0:
		return points
	var result: PackedVector2Array = points
	for i: int in result.size():
		var p: Vector2 = result.get(i)
		var t: Vector2 = (p - rect.position) / rect.size
		result.set(i, Vector2(
			p.x + skew_x * (t.y - 0.5) * rect.size.y,
			p.y + skew_y * (t.x - 0.5) * rect.size.x
		))
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
