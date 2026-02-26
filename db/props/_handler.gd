@tool
class_name GdssPropHandler
extends StyleBox

@export_storage var _ref_path: NodePath = NodePath()

var ref: CanvasItem:
	get:
		if _ref_path.is_empty():
			return null
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree == null:
			return null
		var result: CanvasItem = tree.root.get_node_or_null(_ref_path) as CanvasItem
		if result != null:
			return result
		var path_str: String = str(_ref_path)
		var marker: String = "SubViewport/"
		var marker_idx: int = path_str.rfind(marker)
		if marker_idx != -1:
			var relative: String = path_str.substr(marker_idx + marker.length())
			for child: Node in tree.root.get_children():
				result = child.get_node_or_null(relative) as CanvasItem
				if result != null:
					return result
		return null
	set(v):
		if v == null:
			_ref_path = NodePath()
			return
		if v.is_inside_tree():
			_ref_path = v.get_path()
		else:
			v.tree_entered.connect(func() -> void:
				_ref_path = v.get_path()
			, CONNECT_ONE_SHOT)
		if Engine.is_editor_hint():
			var interp: GdssInterpreter = GdssInterpreter.get_instance()
			if is_instance_valid(interp) and not interp.parsed_changed.is_connected(_on_parsed_changed):
				interp.parsed_changed.connect(_on_parsed_changed)


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


func _on_parsed_changed() -> void:
	if ref == null:
		return
	_apply_overrides()
	emit_changed()


func _apply_overrides() -> void:
	if ref == null:
		return
	var gdss_node: GdssNode = GDSS.get_gdss_nodes().get(ref.get_class())
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
					control.add_theme_color_override(prop.name, val)
			GdssProp.Category.CONST:
				if val is int or val is float:
					control.add_theme_constant_override(prop.name, int(val))
			GdssProp.Category.FONT_SIZE:
				if val is int or val is float:
					control.add_theme_font_size_override(prop.name, int(val))


func _get_animatable_props() -> Dictionary:
	var result: Dictionary = {}
	if ref == null:
		return result
	var gdss_node: GdssNode = GDSS.get_gdss_nodes().get(ref.get_class())
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

	var gdss_node: GdssNode = GDSS.get_gdss_nodes().get(ref.get_class())
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
		match prop.type:
			GDSS.Type.COLOR:
				var fallback: Color = prop.get_default_value() if prop.get_default_value() is Color else Color.TRANSPARENT
				var from: Color = _tweened_values.get(prop_name, _get_parsed_val(prop_name, resolved_from, fallback)) as Color
				var to: Color = _get_parsed_val(prop_name, to_state, fallback) as Color
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
				var from_raw: Variant = _tweened_values.get(prop_name, _get_parsed_val(prop_name, resolved_from, fallback))
				var from: Vector4 = Vector4(from_raw) if from_raw is Vector4 else Vector4(from_raw as Vector4i)
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


func _get_parsed_val(key: String, state: String, fallback: Variant) -> Variant:
	var entry: Dictionary = _resolve_entry()
	if entry.is_empty():
		return fallback
	if entry.has(state) and entry[state].has(key):
		return entry[state][key]
	if entry.has("all") and entry["all"].has(key):
		return entry["all"][key]
	return fallback


func _get_state() -> String:
	if ref == null:
		return "all"
	if not current_state.is_empty():
		return current_state
	var gdss_node: GdssNode = GDSS.get_gdss_nodes().get(ref.get_class())
	if gdss_node and not gdss_node.states.is_empty():
		return gdss_node.states[0]
	return "all"


func _get_val(key: String, fallback: Variant) -> Variant:
	if ref == null:
		return fallback
	if _tweened_values.has(key):
		return _tweened_values[key]
	var entry: Dictionary = _resolve_entry()
	if entry.is_empty():
		return fallback
	var state: String = _get_state()
	if entry.has(state) and entry[state].has(key):
		return entry[state][key]
	if entry.has("all") and entry["all"].has(key):
		return entry["all"][key]
	return fallback


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if ref == null:
		return
	var gdss_node: GdssNode = GDSS.get_gdss_nodes().get(ref.get_class())
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
	var corner_radii: Vector4 = corner_radius

	var anti_aliasing: bool = vals.get("anti_aliasing", true)
	var aa_size: float = 1.0 if anti_aliasing else 0.0
	var detail: int = max(1, int(vals.get("corner_detail", 8)))
	var skew_x: float = vals.get("skew_x", 0.0)
	var skew_y: float = vals.get("skew_y", 0.0)

	# Shadow
	var shadow: Vector4 = Vector4(vals.get("shadow", Vector4i.ZERO))
	var shadow_color: Color = vals.get("shadow_color", Color(0, 0, 0, 0.4))
	var shadow_size: float = float(shadow.x + shadow.y + shadow.z + shadow.w) * 0.25
	if shadow_size > 0.0:
		var shadow_outer: Rect2 = rect.grow(shadow_size)
		_draw_ring_raw(to_canvas_item, rect, shadow_outer, _fit_corners(corner_radii, rect), _fit_corners(corner_radii, shadow_outer), shadow_color, true, detail, skew_x, skew_y)

	var bg_color: Color = vals.get("bg_color", Color.TRANSPARENT)
	if bg_color.a > 0.0:
		_draw_rect(to_canvas_item, rect, bg_color, corner_radii, aa_size, detail, skew_x, skew_y)

	var border: Vector4 = Vector4(vals.get("border", Vector4i.ZERO))
	var border_color: Color = vals.get("border_color", Color.TRANSPARENT)
	var has_border: bool = border.x > 0 or border.y > 0 or border.z > 0 or border.w > 0
	if has_border and border_color.a > 0.0:
		var inner_rect: Rect2 = rect.grow_individual(-border.x, -border.z, -border.y, -border.w)
		if inner_rect.has_area():
			_draw_ring(to_canvas_item, inner_rect, rect, corner_radii, border_color, aa_size, detail, skew_x, skew_y)


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
