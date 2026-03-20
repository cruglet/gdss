@tool
class_name GdssPropHandler
extends StyleBox

static var _texture_cache: Dictionary = {}
var _slot_state: String = ""

@export_storage var _ref_path: NodePath = NodePath()
var _ref_node: CanvasItem = null
var _ref_node_rt: CanvasItem = null

var ref: CanvasItem:
	get:
		if Engine.is_editor_hint():
			if is_instance_valid(_ref_node):
				return _ref_node
			if _ref_path.is_empty():
				return null
			var tree: SceneTree = Engine.get_main_loop() as SceneTree
			if tree == null:
				return null
			var resolved: CanvasItem = tree.root.get_node_or_null(_ref_path) as CanvasItem
			if is_instance_valid(resolved):
				_ref_node = resolved
				_connect_ref_signals(_ref_node)
			return resolved
		else:
			return _ref_node_rt if is_instance_valid(_ref_node_rt) else null
	set(v):
		if v == null:
			_ref_node = null
			_ref_node_rt = null
			_ref_path = NodePath()
			return
		if Engine.is_editor_hint():
			_ref_node = v
			if v.is_inside_tree():
				_ref_path = v.get_path()
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
			_ref_node_rt = v
			if v.is_inside_tree():
				_ref_path = v.get_path()
			if not v.is_connected("tree_entered", _on_ref_tree_entered_rt):
				v.connect("tree_entered", _on_ref_tree_entered_rt)
			if not v.is_connected("tree_exiting", _on_ref_tree_exiting_rt):
				v.connect("tree_exiting", _on_ref_tree_exiting_rt)


var current_state: String = "":
	set(s):
		if s == current_state:
			return
		_start_transition(current_state, s)
		current_state = s
		_apply_overrides()
		if ref != null:
			ref.queue_redraw()


var _tweened_values: Dictionary[String, Variant] = {}
var _tween: Tween = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and Engine.is_editor_hint():
		var interp: GdssInterpreter = GdssInterpreter.get_instance()
		if not is_instance_valid(interp):
			return
		var cb: Callable = Callable(self, &"_on_parsed_changed")
		if interp.parsed_changed.is_connected(cb):
			interp.parsed_changed.disconnect(cb)


func _connect_ref_signals(v: CanvasItem) -> void:
	if Engine.is_editor_hint():
		if not v.is_connected("renamed", _on_ref_renamed):
			v.connect("renamed", _on_ref_renamed)
		if not v.is_connected("tree_entered", _on_ref_tree_entered):
			v.connect("tree_entered", _on_ref_tree_entered)
		if not v.is_connected("tree_exiting", _on_ref_tree_exiting):
			v.connect("tree_exiting", _on_ref_tree_exiting)
		
		var interp = GdssInterpreter.get_instance()
		if is_instance_valid(interp) and not interp.parsed_changed.is_connected(_on_parsed_changed):
			interp.parsed_changed.connect(_on_parsed_changed)
	else:
		if not v.is_connected("tree_entered", _on_ref_tree_entered_rt):
			v.connect("tree_entered", _on_ref_tree_entered_rt)
		if not v.is_connected("tree_exiting", _on_ref_tree_exiting_rt):
			v.connect("tree_exiting", _on_ref_tree_exiting_rt)


func _on_ref_renamed() -> void:
	if is_instance_valid(_ref_node) and _ref_node.is_inside_tree():
		_ref_path = _ref_node.get_path()


func _on_ref_tree_entered() -> void:
	if is_instance_valid(_ref_node):
		_ref_path = _ref_node.get_path()


func _on_ref_tree_exiting() -> void:
	if is_instance_valid(_ref_node) and _ref_node.is_inside_tree():
		_ref_path = _ref_node.get_path()


func _on_ref_tree_entered_rt() -> void:
	if is_instance_valid(_ref_node_rt):
		_ref_path = _ref_node_rt.get_path()


func _on_ref_tree_exiting_rt() -> void:
	if is_instance_valid(_ref_node_rt) and _ref_node_rt.is_inside_tree():
		_ref_path = _ref_node_rt.get_path()
	_ref_node_rt = null


func _on_parsed_changed() -> void:
	if ref == null:
		return
	for method: GdssMethod in GDSS._get_gdss_methods().values():
		if method.returns_texture:
			method.clear_live_textures()
	_apply_overrides()
	emit_changed()
	ref.queue_redraw()
	if Engine.is_editor_hint():
		ref.notify_property_list_changed()
		var parent: Node = ref.get_parent()
		if is_instance_valid(parent) and parent is CanvasItem:
			(parent as CanvasItem).queue_redraw()


func _apply_overrides() -> void:
	if ref == null:
		return
	if not ref.has_meta("gdss_handler"):
		return
	var gdss_node: GdssNode = GDSS._get_gdss_nodes().get(ref.get_class())
	if gdss_node == null:
		return
	var control: Control = ref as Control
	for prop: GdssProp in gdss_node.get_enabled_props():
		var val: Variant = _get_val(prop.name, prop.get_default_value())
		if val == null:
			val = prop.get_default_value()
		match prop.category:
			GdssProp.Category.STYLE:
				if prop.name == "padding":
					var padding: Vector4 = Vector4(val)
					set_content_margin(SIDE_LEFT, padding.x)
					set_content_margin(SIDE_RIGHT, padding.y)
					set_content_margin(SIDE_TOP, padding.z)
					set_content_margin(SIDE_BOTTOM, padding.w)
			GdssProp.Category.COLOR:
				if val is Color:
					if prop.category_subproperties.is_empty():
						control.add_theme_color_override(prop.name, val)
					else:
						if gdss_node.colors.has(prop.name):
							control.add_theme_color_override(prop.name, val)
						for subprop: String in prop.category_subproperties:
							if gdss_node.colors.has(subprop):
								control.add_theme_color_override(subprop, val)
			GdssProp.Category.CONST:
				if val is int or val is float:
					control.add_theme_constant_override(prop.name, int(val))
			GdssProp.Category.FONT_SIZE:
				if val is int or val is float:
					control.add_theme_font_size_override(prop.name, int(val))
			GdssProp.Category.FONT:
				if val is Font:
					control.add_theme_font_override(prop.name, val as Font)
			GdssProp.Category.ICON:
				if val is Texture2D:
					control.add_theme_icon_override(prop.name, val)
			GdssProp.Category.NODE_PROPERTY:
				if prop.type == GDSS.Type.CURSOR:
					control.set("mouse_default_cursor_shape", _get_cursor_shape(str(val)))
				else:
					control.set(prop.name, val)


func _get_cursor_shape(type: String) -> Control.CursorShape:
	match type:
		"ARROW": return Control.CursorShape.CURSOR_ARROW
		"IBEAM": return Control.CursorShape.CURSOR_IBEAM
		"POINTING": return Control.CursorShape.CURSOR_POINTING_HAND
		"DISABLED": return Control.CursorShape.CURSOR_FORBIDDEN
	return Control.CursorShape.CURSOR_ARROW


func _get_animatable_props() -> Dictionary:
	var result: Dictionary = {}
	if ref == null:
		return result
	var gdss_node: GdssNode = GDSS._get_gdss_nodes().get(ref.get_class())
	if gdss_node == null:
		return result
	for prop: GdssProp in gdss_node.get_enabled_props():
		match prop.type:
			GDSS.Type.COLOR, GDSS.Type.COMPOSITE4, GDSS.Type.FLOAT, GDSS.Type.INT:
				result[prop.name] = prop
	return result


func _start_transition(from_state: String, to_state: String) -> void:
	var transition_time: float = _get_parsed_val("transition_time", to_state, 0.0)
	if transition_time <= 0.0 or ref == null or not ref.is_inside_tree():
		_tweened_values.clear()
		return

	var gdss_node: GdssNode = GDSS._get_gdss_nodes().get(ref.get_class())
	var default_state: String = gdss_node.states[0] if gdss_node and not gdss_node.states.is_empty() else "all"
	var resolved_from: String = from_state if not from_state.is_empty() else default_state

	var trans: Tween.TransitionType
	var ease: Tween.EaseType

	match _get_parsed_val("transition_func", to_state, "LINEAR"):
		"LINEAR": trans = Tween.TRANS_LINEAR
		"SINE": trans = Tween.TRANS_SINE
		"QUINT": trans = Tween.TRANS_QUINT
		"QUART": trans = Tween.TRANS_QUART
		"QUAD": trans = Tween.TRANS_QUAD
		"EXPO": trans = Tween.TRANS_EXPO
		"ELASTIC": trans = Tween.TRANS_ELASTIC
		"CUBIC": trans = Tween.TRANS_CUBIC
		"CIRC": trans = Tween.TRANS_CIRC
		"BOUNCE": trans = Tween.TRANS_BOUNCE
		"BACK": trans = Tween.TRANS_BACK
		"SPRING": trans = Tween.TRANS_SPRING
		_: trans = Tween.TRANS_LINEAR

	match _get_parsed_val("transition_type", to_state, "EASE_IN_OUT"):
		"EASE_IN": ease = Tween.EASE_IN
		"EASE_OUT": ease = Tween.EASE_OUT
		"EASE_IN_OUT": ease = Tween.EASE_IN_OUT
		"EASE_OUT_IN": ease = Tween.EASE_OUT_IN
		_: ease = Tween.EASE_IN_OUT

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
					ref.queue_redraw()
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
				_tweened_values[captured] = from
				pending_tween.tween_method(func(v: Color) -> void:
					_tweened_values[captured] = v
					if is_style:
						ref.queue_redraw()
					else:
						_apply_overrides()
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
				_tweened_values[captured] = from
				pending_tween.tween_method(func(v: Vector4) -> void:
					_tweened_values[captured] = v
					if is_style:
						ref.queue_redraw()
					else:
						_apply_overrides()
				, from, to, transition_time)
				tweener_count += 1

			GDSS.Type.FLOAT:
				var fallback: float = float(prop.get_default_value())
				var from: float = float(_tweened_values.get(prop_name, _get_parsed_val(prop_name, resolved_from, fallback)))
				var to: float = float(_get_parsed_val(prop_name, to_state, fallback))
				if from == to:
					continue
				var captured: String = prop_name
				_tweened_values[captured] = from
				pending_tween.tween_method(func(v: float) -> void:
					_tweened_values[captured] = v
					if is_style:
						ref.queue_redraw()
					else:
						_apply_overrides()
				, from, to, transition_time)
				tweener_count += 1

			GDSS.Type.INT:
				var fallback: int = int(prop.get_default_value())
				var from: int = int(_tweened_values.get(prop_name, _get_parsed_val(prop_name, resolved_from, fallback)))
				var to: int = int(_get_parsed_val(prop_name, to_state, fallback))
				if from == to:
					continue
				var captured: String = prop_name
				_tweened_values[captured] = from
				pending_tween.tween_method(func(v: float) -> void:
					_tweened_values[captured] = int(v)
					if is_style:
						ref.queue_redraw()
					else:
						_apply_overrides()
				, float(from), float(to), transition_time)
				tweener_count += 1


	if tweener_count == 0:
		pending_tween.kill()
		return

	if _tween:
		_tween.kill()
	_tween = pending_tween
	_tween.finished.connect(func() -> void:
		_tweened_values.clear()
		_apply_overrides()
		ref.queue_redraw()
	)


# Builds a merged entry dict by starting from parsed[ref.get_class()] and then
# layering each gdss_class in order (lowest to highest priority).
# Each name is looked up in the current entry's "_classes", allowing nesting.
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


func _resolve_entry() -> Dictionary:
	if ref == null:
		return {}
	var parsed: Dictionary[String, Dictionary] = GdssInterpreter.parsed
	var selector: String = ref.get_class()
	if not parsed.has(selector):
		return {}

	var entry: Dictionary = parsed[selector]

	if not ref.has_meta("gdss_classes"):
		return entry

	var gdss_classes: PackedStringArray = ref.get_meta("gdss_classes") as PackedStringArray
	for gdss_class_name: String in gdss_classes:
		var override: Dictionary = _find_class_in_tree(parsed[selector].get("_classes", {}), gdss_class_name)
		if override.is_empty():
			continue
		entry = _merge_entries(entry, override)

	return entry


func _resolve_value(raw: Variant, fallback: Variant, state_key: String = "") -> Variant:
	raw = _resolve_sentinel(raw, fallback)
	if raw is Dictionary:
		var d: Dictionary = raw as Dictionary
		if d.has("__resolved__"):
			return d["__resolved__"]
		if d.has("__gdss_method__"):
			return _call_method(d, fallback, state_key)
	if raw is String:
		var s: String = raw as String
		if s.begins_with("#") and Color.html_is_valid(s):
			return Color.html(s)
		if not s.begins_with("__gdss_"):
			var named: Color = Color.from_string(s, Color(-1, -1, -1, -1))
			if named.r != -1:
				return named
	return raw


func _resolve_method_args(descriptor: Dictionary) -> Array[Variant]:
	var method_name: String = descriptor["__gdss_method__"]
	var raw_args: Array = descriptor.get("args", [])
	var method: GdssMethod = GDSS._get_gdss_methods().get(method_name)
	var resolved: Array[Variant] = []
	for raw: String in raw_args:
		var stripped: String = (raw as String).strip_edges()
		if stripped.begins_with("__gdss_global__"):
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
			resolved.append(method._resolve_arg(unquoted) if method != null else unquoted)
	return resolved


func _call_method(descriptor: Dictionary, fallback: Variant, state_key: String = "") -> Variant:
	if descriptor.has("__resolved__"):
		return descriptor["__resolved__"]
	var name: String = descriptor["__gdss_method__"]
	var method: GdssMethod = GDSS._get_gdss_methods().get(name)
	if method == null:
		return fallback
	var resolved_args: Array[Variant] = _resolve_method_args(descriptor)
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
	if entry.has(state) and entry[state].has(key):
		raw = entry[state][key]
	elif entry.has("all") and entry["all"].has(key):
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
	var gdss_node: GdssNode = GDSS._get_gdss_nodes().get(ref.get_class())
	if gdss_node and not gdss_node.states.is_empty():
		return gdss_node.states[0]
	return "all"


func _resolve_sentinel(raw: Variant, fallback: Variant) -> Variant:
	if not raw is String:
		return raw
	var s: String = raw as String
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
	var entry: Dictionary = _resolve_entry()
	if entry.is_empty():
		return fallback
	var state: String = _get_state()
	var raw: Variant = null
	if entry.has(state) and entry[state].has(key):
		raw = entry[state][key]
	elif entry.has("all") and entry["all"].has(key):
		raw = entry["all"][key]
	else:
		return fallback
	if raw is Dictionary and (raw as Dictionary).has("__gdss_method__"):
		var mn: String = (raw as Dictionary)["__gdss_method__"]
		var method: GdssMethod = GDSS._get_gdss_methods().get(mn)
		if method != null and method.returns_texture:
			var node_id: int = ref.get_instance_id()
			var tween_tex: Texture2D = method.get_live_texture(node_id, "tween:" + key)
			if tween_tex != null:
				return tween_tex
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


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if ref == null:
		return
	var gdss_node: GdssNode = GDSS._get_gdss_nodes().get(ref.get_class())
	if gdss_node == null:
		return

	var vals: Dictionary = {}
	for prop: GdssProp in gdss_node.get_enabled_props():
		var v: Variant = _get_val(prop.name, prop.get_default_value())
		vals[prop.name] = v if v != null else prop.get_default_value()

	var expand: Vector4 = Vector4(vals.get("expand", Vector4i.ZERO))
	rect = rect.grow_individual(expand.x, expand.z, expand.y, expand.w)
	if not rect.has_area():
		return
	
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
		if shadow_src is GradientTexture2D:
			_draw_linear_gradient_ring(to_canvas_item, shadow_src as GradientTexture2D, rect, shadow_outer, _fit_corners(corner_radius, rect), detail, skew_x, skew_y, true)
		elif shadow_src is Texture2D:
			_draw_textured_ring(to_canvas_item, rect, shadow_outer, _fit_corners(corner_radius, rect), shadow_src as Texture2D, detail, skew_x, skew_y, true)
		elif shadow_src is Color:
			_draw_ring_raw(to_canvas_item, rect, shadow_outer, _fit_corners(corner_radius, rect), _fit_corners(corner_radius, shadow_outer), shadow_src as Color, true, detail, skew_x, skew_y)

	var bg: Variant = vals.get("bg_color", Color.TRANSPARENT)
	if bg is GradientTexture2D:
		_draw_linear_gradient_rect(to_canvas_item, bg as GradientTexture2D, rect, corner_radius, detail, skew_x, skew_y)
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
			if border_src is GradientTexture2D:
				_draw_linear_gradient_ring(to_canvas_item, border_src as GradientTexture2D, inner_rect, rect, corner_radius, detail, skew_x, skew_y)
			elif border_src is Color and (border_src as Color).a > 0.0:
				_draw_ring(to_canvas_item, inner_rect, rect, corner_radius, border_src as Color, aa_size, detail, skew_x, skew_y)


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


func _draw_linear_gradient_rect(to_canvas_item: RID, tex: GradientTexture2D, rect: Rect2, corner_radii: Vector4, detail: int, skew_x: float, skew_y: float) -> void:
	var grad: Gradient = tex.gradient
	var angle: float = tex.fill_from.angle_to_point(tex.fill_to)
	var points: PackedVector2Array = _apply_skew(_get_rounded_rect(rect, _fit_corners(corner_radii, rect), detail), rect, skew_x, skew_y)
	var colors: PackedColorArray
	colors.resize(points.size())
	for i: int in points.size():
		var p: Vector2 = points[i]
		var t: float = ((p - rect.position) / rect.size).dot(Vector2(cos(angle), sin(angle))) * 0.5 + 0.5
		colors[i] = grad.sample(clampf(t, 0.0, 1.0))
	RenderingServer.canvas_item_add_polygon(to_canvas_item, points, colors)


func _draw_linear_gradient_ring(to_canvas_item: RID, tex: GradientTexture2D, inner_rect: Rect2, outer_rect: Rect2, corner_radii: Vector4, detail: int, skew_x: float, skew_y: float, fade: bool = false) -> void:
	var grad: Gradient = tex.gradient
	var c1: Color = grad.get_color(0)
	var c2: Color = grad.get_color(1)
	var angle: float = tex.fill_from.angle_to_point(tex.fill_to)
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
		var quad: PackedVector2Array = PackedVector2Array([p0, p1, p2, p3])
		var quad_colors: PackedColorArray
		quad_colors.resize(4)
		for j: int in 4:
			var p: Vector2 = quad[j]
			var t: float = ((p - outer_rect.position) / outer_rect.size).dot(Vector2(cos(angle), sin(angle))) * 0.5 + 0.5
			var col: Color = c1.lerp(c2, clampf(t, 0.0, 1.0))
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
	var indices: PackedInt32Array
	var total: int = max(inner_size, outer_size)
	for i: int in total:
		var i0: int = i % inner_size
		var i1: int = (i + 1) % inner_size
		var o0: int = i % outer_size + inner_size
		var o1: int = (i + 1) % outer_size + inner_size
		indices.append_array([i0, o0, o1, i0, o1, i1])
	return indices


func _get_rounded_rect(rect: Rect2, corner_radii: Vector4, detail: int = 8) -> PackedVector2Array:
	var corner_centers: Array[Vector2] = [
		rect.position + Vector2(corner_radii[0], corner_radii[0]),
		Vector2(rect.end.x, rect.position.y) + Vector2(-corner_radii[1], corner_radii[1]),
		rect.end + Vector2(-corner_radii[2], -corner_radii[2]),
		Vector2(rect.position.x, rect.end.y) + Vector2(corner_radii[3], -corner_radii[3]),
	]
	var start_angles: Array[float] = [PI, PI * 1.5, 0.0, PI * 0.5]

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
				var theta: float = start_angles[corner_idx] + (PI * 0.5) * i / detail
				points.append(corner_centers[corner_idx] + Vector2(cos(theta), sin(theta)) * radius)
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
