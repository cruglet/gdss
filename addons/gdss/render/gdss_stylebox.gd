@tool
class_name GdssStylebox
extends StyleBox


func _resolve_time(prop_name: String, state: String) -> float:
	var seconds: float = GdssTransition.time_for(_get_parsed_val("transition_time", state, 0.0), prop_name)
	if seconds >= 0.0:
		return seconds
	var node_type: GdssNodeType = _resolve_gdss_node()
	var base: String = node_type.states.get(0) if node_type and not node_type.states.is_empty() else "all"
	return maxf(GdssTransition.time_for(_get_parsed_val("transition_time", base, 0.0), prop_name), 0.0)


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

var _gpu: GdssGpuRenderer = null
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
		if _gpu != null:
			_gpu.release()
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
			if _is_dynamic_raw(GdssCascade.raw_value(entry, state, prop_name)):
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


func _apply_theme_prop(prop: GdssProp, control: Variant, node_type: GdssNodeType, val: Variant) -> void:
	if GdssThemeApplier.apply(prop, control, node_type, val, _applied_overrides, _applied_node_props):
		_refresh_font_transform(control, node_type)


func remove_applied_overrides(control: Variant) -> void:
	GdssThemeApplier.remove_overrides(control, _applied_overrides)


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
	var slot_states: PackedStringArray = node_type.states if node_type.is_static and not _slot_state.is_empty() else PackedStringArray()
	var is_secondary_slot: bool = not slot_states.is_empty() and _slot_state != slot_states.get(0)
	for prop: GdssProp in node_type.get_enabled_props():
		if prop.category == GdssProp.Category.STYLE:
			if prop.name == "padding":
				var pad_raw: Variant = _tweened_values.get(prop.name,
					_get_val_cached(prop.name, entry, state, prop.get_default_value()))
				_apply_padding(Vector4(pad_raw if pad_raw != null else prop.get_default_value()))
			continue
		if is_secondary_slot or not styled.has(prop.name):
			continue
		var val: Variant = _get_val_cached(prop.name, entry, state, prop.get_default_value())
		if val == null:
			val = prop.get_default_value()
		_apply_theme_prop(prop, control, node_type, val)
		if prop.category == GdssProp.Category.COLOR:
			for slot: String in slot_states.slice(1):
				var slot_color: String = prop.name.trim_suffix("color") + slot + "_color"
				var slot_val: Variant = _get_val_cached(prop.name, entry, slot, val)
				if node_type.colors.has(slot_color) and slot_val is Color:
					GdssThemeApplier.override_color(control, node_type, slot_color, slot_val, _applied_overrides)
	_refresh_font_transform(control, node_type)
	_applying = false


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
		GdssTransition.longest_time(_get_parsed_val("transition_time", ts, 0.0)),
		_resolve_time(GdssValue.SCOPED_TIME_ANY, ts)))
	if transition_time <= 0.0 or ref == null or not ref.is_inside_tree():
		_kill_tween()
		if on_finished.is_valid():
			on_finished.call()
		return
	
	var node_type: GdssNodeType = _resolve_gdss_node()
	var default_state: String = node_type.states.get(0) if node_type and not node_type.states.is_empty() else "all"
	var resolved_from: String = from_state if not from_state.is_empty() else default_state
	
	var trans: Tween.TransitionType = GdssTransition.resolve_trans(_get_parsed_val("transition_func", ts, "LINEAR"))
	var ease: Tween.EaseType = GdssTransition.resolve_ease(_get_parsed_val("transition_type", ts, "EASE_OUT"))
	
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
					var sides_from: Array = GdssRenderer.side_colors(from_val, fallback)
					var sides_to: Array = GdssRenderer.side_colors(to_val, fallback)
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
				var composite_to_raw: Variant = _get_parsed_val(prop_name, to_state, fallback)
				var to: Vector4 = Vector4(composite_to_raw) if composite_to_raw is Vector4 else Vector4(composite_to_raw as Vector4i)
				if from == to:
					continue
				var captured: String = prop_name
				var captured_prop: GdssProp = prop
				_tweened_values.set(captured, from)
				pending_tween.tween_method(func(v: Vector4) -> void:
					_tweened_values.set(captured, v)
					if captured == "padding":
						_apply_padding(v)
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
				var float_from: Variant = _tweened_values.get(prop_name, _get_parsed_val(prop_name, resolved_from, fallback))
				var float_to: Variant = _get_parsed_val(prop_name, to_state, fallback)
				if not (float_from is int or float_from is float) or not (float_to is int or float_to is float):
					continue
				var from: float = float(float_from)
				var to: float = float(float_to)
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
				var int_from: Variant = _tweened_values.get(prop_name, _get_parsed_val(prop_name, resolved_from, fallback))
				var int_to: Variant = _get_parsed_val(prop_name, to_state, fallback)
				if not (int_from is int or int_from is float) or not (int_to is int or int_to is float):
					continue
				var from: int = int(int_from)
				var to: int = int(int_to)
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


func _absorb_vars(source: Dictionary) -> void:
	var declared: Variant = source.get(GdssStylesheet.VARS_KEY)
	if not declared is Dictionary:
		return
	for key: String in declared as Dictionary:
		_scoped_vars.set(key, (declared as Dictionary).get(key))


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
	var override_entry: Dictionary = GdssCascade.build_override_entry(override_meta)
	var descendant_layers: Array[Dictionary] = _collect_descendant_layers()
	_scoped_vars.clear()
	for layer: Dictionary in descendant_layers:
		var inherited: Variant = layer.get("vars")
		if inherited is Dictionary:
			for key: String in inherited as Dictionary:
				_scoped_vars.set(key, (inherited as Dictionary).get(key))
	_absorb_vars(entry)
	for gdss_class_name: String in current_classes:
		for step: Dictionary in GdssCascade.find_class_path((parsed.get(selector, {}) as Dictionary).get("_classes", {}), gdss_class_name):
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
		entry = GdssCascade.merge_entries(entry, GdssCascade.resolve_override_patches(entry, variations.get(variation)))
	for layer: Dictionary in descendant_layers:
		var body: Dictionary = layer.get("entry")
		if not body.is_empty():
			entry = GdssCascade.merge_entries(entry, GdssCascade.resolve_override_patches(entry, body))
	for gdss_class_name: String in current_classes:
		var path: Array[Dictionary] = GdssCascade.find_class_path((parsed.get(selector, {}) as Dictionary).get("_classes", {}), gdss_class_name)
		for step: Dictionary in path:
			var step_rules: Variant = step.get(GdssStylesheet.DESCENDANTS_KEY)
			if step_rules is Dictionary and not (step_rules as Dictionary).is_empty():
				entry = GdssCascade.merge_entries(entry, {GdssStylesheet.DESCENDANTS_KEY: step_rules})
		var override: Dictionary = path.back() if not path.is_empty() else {}
		if not override.is_empty():
			entry = GdssCascade.merge_entries(entry, GdssCascade.resolve_override_patches(entry, override))
	for layer: Dictionary in descendant_layers:
		var anc: Dictionary = layer.get("anc")
		if not anc.is_empty():
			anc = GdssCascade.resolve_override_patches(entry, anc)
			entry = GdssCascade.merge_entries(entry, anc)
			GdssCascade.propagate_all(entry, anc)
	if not override_entry.is_empty():
		override_entry = GdssCascade.resolve_override_patches(entry, override_entry)
		entry = GdssCascade.merge_entries(entry, override_entry)
		GdssCascade.propagate_all(entry, override_entry)
	_entry_cache = entry
	_entry_cache_classes = current_classes
	_entry_cache_variation = variation
	_entry_cache_overrides = override_meta
	_entry_cache_ancestry = ancestry
	_entry_cache_dirty = false
	return entry


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
		var override: Dictionary = GdssCascade.find_class(entry.get("_classes", {}), gdss_class_name)
		var nested: Variant = override.get(GdssStylesheet.DESCENDANTS_KEY)
		if nested is Dictionary and not (nested as Dictionary).is_empty():
			result = GdssCascade.merge_descendants(result, nested as Dictionary)
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


func _resolve_value(raw: Variant, fallback: Variant, state_key: String = "") -> Variant:
	if raw is Dictionary and (raw as Dictionary).has("__gdss_composite4__"):
		var parts: Array = (raw as Dictionary).get("__gdss_composite4__")
		return Vector4i(_resolve_composite_part(parts.get(0)), _resolve_composite_part(parts.get(1)), _resolve_composite_part(parts.get(2)), _resolve_composite_part(parts.get(3)))
	if raw is Dictionary and (raw as Dictionary).has("__gdss_composite2__"):
		var parts2: Array = (raw as Dictionary).get("__gdss_composite2__")
		return Vector2(_resolve_composite_part_f(parts2.front()), _resolve_composite_part_f(parts2.back()))
	if raw is Dictionary and (raw as Dictionary).has(GdssValue.COLOR4_KEY):
		var sides: Array = (raw as Dictionary).get(GdssValue.COLOR4_KEY)
		var resolved_sides: Array = []
		for side: Variant in sides:
			resolved_sides.append(_resolve_value(side, fallback, state_key))
		return resolved_sides
	if raw is Dictionary and (raw as Dictionary).has("__gdss_calc__"):
		return GdssCalc.evaluate((raw as Dictionary).get("__gdss_calc__"), _calc_ref_value)
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
			var named: Color = GdssColors.named(s, GdssColors.MISSING)
			if named != GdssColors.MISSING:
				return named
	return raw


func _refresh_font_transform(control: Variant, node_type: GdssNodeType) -> void:
	if control == null or node_type == null or node_type.fonts.is_empty():
		return
	var entry: Dictionary = _resolve_entry()
	var state: String = _get_state()
	var skew: Variant = _tweened_values.get("char_skew", _get_val_cached("char_skew", entry, state, Vector2.ZERO))
	var embolden: Variant = _tweened_values.get("char_embolden", _get_val_cached("char_embolden", entry, state, 0.0))
	GdssThemeApplier.apply_font_transform(control, node_type,
		skew if skew is Vector2 else Vector2.ZERO,
		float(embolden) if embolden is int or embolden is float else 0.0)


func _apply_padding(padding: Vector4) -> void:
	set_content_margin(SIDE_LEFT, padding.x)
	set_content_margin(SIDE_RIGHT, padding.y)
	set_content_margin(SIDE_TOP, padding.z)
	set_content_margin(SIDE_BOTTOM, padding.w)


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
				var named: Color = GdssColors.named(resolved_arg as String, GdssColors.MISSING)
				if named != GdssColors.MISSING:
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
				if _is_dynamic_raw(GdssCascade.raw_value(entry, state, prop.name)):
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
			if _is_dynamic_raw(GdssCascade.raw_value(entry, state, prop.name)):
				_style_dynamic.append(prop)
		return _style_vals_cache
	for prop: GdssProp in _style_dynamic:
		var dv: Variant = _get_val_cached(prop.name, entry, state, prop.get_default_value())
		_style_vals_cache.set(prop.name, dv if dv != null else prop.get_default_value())
	return _style_vals_cache


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
		if d.has(GdssValue.COLOR4_KEY):
			for side: Variant in d.get(GdssValue.COLOR4_KEY):
				if _is_dynamic_raw(side):
					return true
			return false
		if d.has("__gdss_calc__"):
			return GdssCalc.has_dynamic_ref(d.get("__gdss_calc__"))
		if not d.has("__gdss_method__"):
			return false
		for arg: Variant in d.get("args", []):
			if not arg is String:
				continue
			var a: String = (arg as String).strip_edges()
			if a.begins_with("__gdss_global__") or a.begins_with("__gdss_instance__") or a.begins_with("$"):
				return true
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
		if _gpu == null:
			_gpu = GdssGpuRenderer.new(_safe_redraw)
		_gpu.draw(to_canvas_item, rect, vals, ref, GDSS.scaled_duration(_resolve_time("bg_texture", _get_state())))
		return
	_free_gpu_ci()
	GdssCpuRenderer.draw(to_canvas_item, rect, vals)


func _free_gpu_ci() -> void:
	if _gpu != null:
		_gpu.release()
