@tool
class_name GdssStylebox
extends StyleBox

const _NONE: Dictionary = {}
const _NO_PROPS: Array[GdssProp] = []


func _resolve_time(prop_name: String, state: String) -> float:
	var seconds: float = GdssTransition.time_for(_get_parsed_val("transition_time", state, 0.0), prop_name)
	if seconds >= 0.0:
		return seconds
	return maxf(GdssTransition.time_for(_get_parsed_val("transition_time", _default_state(), 0.0), prop_name), 0.0)


func _default_state() -> String:
	var node_type: GdssNodeType = _resolve_gdss_node()
	return node_type.states.get(0) if node_type and not node_type.states.is_empty() else "all"


func _transition_candidates(from_state: String, to_state: String) -> PackedStringArray:
	var animatable: Dictionary = _get_animatable_props()
	var entry: Dictionary = _resolve_entry()
	var names: Dictionary[String, bool] = {}
	for source: Variant in [entry.get(from_state), entry.get(to_state), _tweened_values, _tweened_args]:
		if not source is Dictionary:
			continue
		for prop_name: String in source as Dictionary:
			if animatable.has(prop_name):
				names.set(prop_name, true)
	return PackedStringArray(names.keys())


var _slot_state: String = ""

var _ref_path: NodePath = NodePath()
var _ref_node: Node = null
var _ref_node_rt: Node = null
var _applying: bool = false

var _entry_cache: Dictionary = _NONE
var _entry_cache_dirty: bool = true
var _entry_cache_classes: PackedStringArray = []
var _entry_cache_variation: String = ""
var _entry_cache_overrides: Variant = null
var _entry_cache_ancestry: String = ""
var _scoped_vars: Dictionary = _NONE
var _ancestor_states_dirty: bool = true
var _ancestor_states: bool = false
var _styled_props_cache: Dictionary = _NONE
var _styled_props_dirty: bool = true
var _shared: GdssSharedEntry = null

var _method_args_cache: Dictionary = _NONE

var _gdss_node: GdssNodeType = null

var _gpu: GdssGpuRenderer = null
var _style_vals_cache: Dictionary = _NONE
var _style_dynamic: Array[GdssProp] = _NO_PROPS
var _style_vals_state: String = "￿"
var _style_vals_tween: Dictionary = _NONE
var _style_dynamic_tween: Array[GdssProp] = _NO_PROPS
var _style_tween_state: String = "￿"
var _style_tween_session: int = -1
var _tween_session: int = 0
var _nonstyle_dynamic: Array[GdssProp] = _NO_PROPS
var _nonstyle_state: String = "￿"
var _event_callables: Dictionary = _NONE

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
		_events_synced_for = null
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
var _first_drawn_frame: int = -1
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
		if not previous.is_empty() and _was_rendered():
			_start_transition(previous, s)
			_play_sfx(s)
		current_state = s
		_apply_overrides(not previous.is_empty())
		_notify_descendant_rules()
		if ref != null:
			_safe_redraw()


var _tweened_values: Dictionary = _NONE
var _tweened_args: Dictionary = _NONE
var _tween: Tween = null
var _state_sync_queued: bool = false
var _applied_node_props: Dictionary = _NONE
var _applied_overrides: Dictionary = _NONE
var _live_applied: Dictionary = _NONE
var _style_revision: int = 0

var _self_toggle: bool = false
var _events_synced_for: Variant = null
var _last_visible: bool = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _tween != null:
			_tween.kill()
			_tween = null
		if not Engine.is_editor_hint():
			return
		var interp: GdssStylesheet = GdssStylesheet.get_instance()
		if not is_instance_valid(interp):
			return
		var cb: Callable = Callable(self, &"_on_parsed_changed")
		if interp.parsed_changed.is_connected(cb):
			interp.parsed_changed.disconnect(cb)


func _connect_ref_signals(v: Node) -> void:
	if not Engine.is_editor_hint():
		return
	if not v.is_connected("renamed", _on_ref_renamed):
		v.connect("renamed", _on_ref_renamed)
	if not v.is_connected("tree_entered", _on_ref_tree_entered):
		v.connect("tree_entered", _on_ref_tree_entered)
	if not v.is_connected("tree_exiting", _on_ref_tree_exiting):
		v.connect("tree_exiting", _on_ref_tree_exiting)
	var interp: GdssStylesheet = GdssStylesheet.get_instance()
	if is_instance_valid(interp) and not interp.parsed_changed.is_connected(_on_parsed_changed):
		interp.parsed_changed.connect(_on_parsed_changed)


func _disconnect_ref_signals(v: Node) -> void:
	if not Engine.is_editor_hint() or not is_instance_valid(v):
		return
	if v.is_connected("renamed", _on_ref_renamed):
		v.disconnect("renamed", _on_ref_renamed)
	if v.is_connected("tree_entered", _on_ref_tree_entered):
		v.disconnect("tree_entered", _on_ref_tree_entered)
	if v.is_connected("tree_exiting", _on_ref_tree_exiting):
		v.disconnect("tree_exiting", _on_ref_tree_exiting)


func _classify_nonstyle(node_type: GdssNodeType, entry: Dictionary, state: String) -> void:
	_nonstyle_state = state
	if _shared != null and _shared.nonstyle_live.has(state):
		_nonstyle_dynamic = _shared.nonstyle_live.get(state)
		return
	var dynamic: Array[GdssProp] = []
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
			var raw: Variant = GdssCascade.raw_value(entry, state, prop_name)
			if not GdssValue.is_live(raw):
				continue
			dynamic.append(prop)
			if _shared != null and GdssValue.is_shareable_live(raw):
				_shared.mark_global_only(state, prop_name)
	_nonstyle_dynamic = dynamic
	if _shared != null:
		_shared.nonstyle_live.set(state, dynamic)


func _on_ref_renamed() -> void:
	if is_instance_valid(_ref_node) and _ref_node.is_inside_tree():
		_ref_path = _ref_node.get_path()


func _on_ref_tree_entered() -> void:
	if is_instance_valid(_ref_node):
		_ref_path = _ref_node.get_path()
		_repositioned()
		GdssNodeBinder.apply_mode_tree.call_deferred(_ref_node)


func _repositioned() -> void:
	if ref == null or not GdssStylesheet.has_descendant_rules:
		return
	GdssNodeBinder.reposition(ref)


func _on_ref_tree_exiting() -> void:
	_free_gpu_ci()
	if is_instance_valid(_ref_node) and _ref_node.is_inside_tree():
		_ref_path = _ref_node.get_path()


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
	_entry_cache = _NONE
	_entry_cache_ancestry = ""
	_ancestor_states_dirty = true
	_shared = null
	_method_args_cache = _NONE
	_gdss_node = null
	_style_vals_state = "￿"
	_style_vals_cache = _NONE
	_style_dynamic = _NO_PROPS
	_style_tween_state = "￿"
	_style_tween_session = -1
	_style_vals_tween = _NONE
	_style_dynamic_tween = _NO_PROPS
	_nonstyle_state = "￿"
	_nonstyle_dynamic = _NO_PROPS


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
	if prop.category == GdssProp.Category.NODE_PROPERTY:
		_applied_node_props = _writable(_applied_node_props)
	else:
		_applied_overrides = _writable(_applied_overrides)
	if _live_applied.has(prop.name):
		_live_applied.erase(prop.name)
	if GdssThemeApplier.apply(prop, control, node_type, val, _applied_overrides, _applied_node_props):
		_refresh_font_transform(control, node_type)


func remove_applied_overrides(control: Variant) -> void:
	_live_applied = _NONE
	if _applied_overrides.is_empty():
		return
	GdssThemeApplier.remove_overrides(control, _applied_overrides)


func _override_slot_color(control: Variant, node_type: GdssNodeType, key: String, value: Color) -> void:
	_applied_overrides = _writable(_applied_overrides)
	GdssThemeApplier.override_color(control, node_type, key, value, _applied_overrides)


static func _writable(source: Dictionary) -> Dictionary:
	return {} if source.is_read_only() else source


func _set_tweened(prop_name: String, value: Variant) -> void:
	_tweened_values = _writable(_tweened_values)
	_tweened_values.set(prop_name, value)


func _set_tweened_args(prop_name: String, args: Array[Variant]) -> void:
	_tweened_args = _writable(_tweened_args)
	_tweened_args.set(prop_name, args)


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
					_override_slot_color(control, node_type, slot_color, slot_val)
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
	_tweened_values = _NONE
	_tweened_args = _NONE


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
	var values: Array = []
	var changed: bool = false
	for prop: GdssProp in _nonstyle_dynamic:
		var val: Variant = _live_value(prop, entry, state)
		if val == null:
			val = prop.get_default_value()
		values.append(val)
		if not changed and (not _live_applied.has(prop.name) or _live_applied.get(prop.name) != val):
			changed = true
	if not changed:
		return
	_applying = true
	var control: Variant = node
	control.begin_bulk_theme_override()
	for i: int in _nonstyle_dynamic.size():
		var prop: GdssProp = _nonstyle_dynamic.get(i)
		_apply_theme_prop(prop, control, node_type, values.get(i))
		_live_applied = _writable(_live_applied)
		_live_applied.set(prop.name, values.get(i))
	var styled: Dictionary = _entry_styled_props(entry)
	if styled.has("char_skew") or styled.has("char_embolden"):
		_refresh_font_transform(control, node_type)
	control.end_bulk_theme_override()
	_applying = false


func _get_animatable_props() -> Dictionary:
	var node_type: GdssNodeType = _resolve_gdss_node() if ref != null else null
	return node_type.get_animatable_props() if node_type != null else {}


func _safe_redraw() -> void:
	var node: Node = ref
	if node == null:
		return
	if node is CanvasItem:
		(node as CanvasItem).queue_redraw()
	else:
		emit_changed()


func _was_rendered() -> bool:
	return _first_drawn_frame != -1 and Engine.get_process_frames() > _first_drawn_frame


func queue_state_sync(node_type: GdssNodeType) -> void:
	if _state_sync_queued or not ref is CanvasItem:
		return
	if node_type.resolve_state(ref as CanvasItem) != current_state:
		_state_sync_queued = true
		_sync_active_state.call_deferred()


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
	var default_state: String = _default_state()
	var time_raw: Variant = _get_parsed_val("transition_time", ts, 0.0)
	var base_time_raw: Variant = _get_parsed_val("transition_time", default_state, 0.0)
	var transition_time: float = GDSS.scaled_duration(maxf(
		GdssTransition.longest_time(time_raw),
		GdssTransition.time_in(time_raw, base_time_raw, GdssValue.SCOPED_TIME_ANY)))
	if transition_time <= 0.0 or ref == null or not ref.is_inside_tree():
		_kill_tween()
		if on_finished.is_valid():
			on_finished.call()
		return
	
	var resolved_from: String = from_state if not from_state.is_empty() else default_state
	
	var trans: Tween.TransitionType = GdssTransition.resolve_trans(_get_parsed_val("transition_func", ts, "LINEAR"))
	var ease: Tween.EaseType = GdssTransition.resolve_ease(_get_parsed_val("transition_type", ts, "EASE_OUT"))
	
	var tweener_count: int = 0
	var pending_tween: Tween = (Engine.get_main_loop() as SceneTree).create_tween()
	pending_tween.set_parallel(true)
	pending_tween.set_trans(trans)
	pending_tween.set_ease(ease)
	
	var animatable: Dictionary = _get_animatable_props()
	for prop_name: String in _transition_candidates(resolved_from, to_state):
		var prop: GdssProp = animatable.get(prop_name)
		var prop_time: float = GDSS.scaled_duration(GdssTransition.time_in(time_raw, base_time_raw, prop_name))
		if prop_time <= 0.0:
			continue
		if _tween_method_args(pending_tween, prop, resolved_from, to_state, prop_time) or _tween_value(pending_tween, prop, resolved_from, to_state, prop_time):
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
		_tweened_values = _NONE
		_tweened_args = _NONE
		if ref != null:
			_apply_overrides()
			_safe_redraw()
		if on_finished.is_valid():
			on_finished.call()
	)


func _tween_method_args(tween: Tween, prop: GdssProp, from_state: String, to_state: String, duration: float) -> bool:
	var from_raw: Variant = _get_raw_parsed_val(prop.name, from_state)
	var to_raw: Variant = _get_raw_parsed_val(prop.name, to_state)
	if not (from_raw is Dictionary and to_raw is Dictionary):
		return false
	var method_name: Variant = (from_raw as Dictionary).get(GdssValue.METHOD_KEY)
	if method_name == null or method_name != (to_raw as Dictionary).get(GdssValue.METHOD_KEY):
		return false
	var method: GdssMethod = GDSS._get_gdss_methods().get(method_name)
	if method == null or method.get_tweenable_args().is_empty():
		return false
	var from_args: Array[Variant] = _tweened_args.get(prop.name, _resolve_method_args(from_raw as Dictionary))
	var to_args: Array[Variant] = _resolve_method_args(to_raw as Dictionary)
	tween.tween_method(_step_method_tween.bind(prop.name, method, from_args, to_args), 0.0, 1.0, duration)
	return true


func _step_method_tween(t: float, prop_name: String, method: GdssMethod, from_args: Array[Variant], to_args: Array[Variant]) -> void:
	var args: Array[Variant] = method.interpolate_args(from_args, to_args, t)
	_set_tweened_args(prop_name, args)
	var result: Variant = method.call_method(args, ref.get_instance_id() if ref != null else -1, "tween:" + prop_name)
	if result != null:
		_set_tweened(prop_name, result)
	_safe_redraw()


func _tween_value(tween: Tween, prop: GdssProp, from_state: String, to_state: String, duration: float) -> bool:
	var fallback: Variant = GdssTransition.tween_fallback(prop)
	var from_value: Variant = _tweened_values.get(prop.name, _get_parsed_val(prop.name, from_state, fallback))
	var pair: Array = GdssTransition.tween_pair(prop.type, from_value, _get_parsed_val(prop.name, to_state, fallback), fallback)
	if pair.is_empty():
		return false
	var from: Variant = pair.front()
	var to: Variant = pair.back()
	_set_tweened(prop.name, from)
	if from is Array:
		tween.tween_method(_step_sides_tween.bind(prop.name, from, to), 0.0, 1.0, duration)
	elif from is int:
		tween.tween_method(_step_value_tween.bind(prop, true), float(from), float(to), duration)
	else:
		tween.tween_method(_step_value_tween.bind(prop, false), from, to, duration)
	return true


func _step_value_tween(value: Variant, prop: GdssProp, as_int: bool) -> void:
	if as_int:
		value = int(round(value))
	_set_tweened(prop.name, value)
	if prop.name == "padding":
		_apply_padding(value)
	if prop.category == GdssProp.Category.STYLE:
		_safe_redraw()
	else:
		_apply_single_override(prop, value)


func _step_sides_tween(t: float, prop_name: String, from: Array, to: Array) -> void:
	_set_tweened(prop_name, GdssTransition.lerp_value(from, to, t))
	_safe_redraw()


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
	if is_same(entry, _events_synced_for):
		return
	_events_synced_for = entry
	if not _event_callables.is_empty():
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
			_event_callables = _writable(_event_callables)
			_event_callables.set(sig, cb)
	_sync_visibility_signal(node, entry.has("on_show()") or entry.has("on_hide()"))


func _clear_event_signals(node: Node) -> void:
	_events_synced_for = null
	for sig: String in _event_callables.keys():
		_disconnect_event_signal(node, sig)
	_sync_visibility_signal(node, false)


func _sync_visibility_signal(node: Node, wanted: bool) -> void:
	if not node is Control or node.is_connected(&"visibility_changed", _on_node_visibility_changed) == wanted:
		return
	if not wanted:
		node.disconnect(&"visibility_changed", _on_node_visibility_changed)
		return
	_self_toggle = false
	_last_visible = (node as Control).visible
	node.connect(&"visibility_changed", _on_node_visibility_changed)


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
	var declared: Variant = source.get(GdssValue.VARS_KEY)
	if not declared is Dictionary:
		return
	for key: String in declared as Dictionary:
		_scoped_vars = _writable(_scoped_vars)
		_scoped_vars.set(key, (declared as Dictionary).get(key))


func _entry_styled_props(entry: Dictionary) -> Dictionary:
	if _shared != null:
		return _shared.styled_props()
	if _styled_props_dirty:
		_styled_props_cache = GdssCascade.styled_props(entry)
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
	var selector: String = ref.get_class()
	var override_entry: Dictionary = GdssCascade.build_override_entry(override_meta)
	var descendant_layers: Array[Dictionary] = _collect_descendant_layers()
	var shareable: bool = override_entry.is_empty() and descendant_layers.is_empty()
	var share_key: String = ",".join(current_classes) + "|" + variation
	_shared = GdssSharedEntry.find(selector, share_key) if shareable else null
	if _shared != null:
		_scoped_vars = _shared.scoped_vars
		return _cache_entry(_shared.data, current_classes, variation, override_meta, ancestry)
	var entry: Dictionary = _merge_entry(selector, current_classes, variation, override_entry, descendant_layers)
	if shareable:
		_shared = GdssSharedEntry.new(entry, _scoped_vars)
		GdssSharedEntry.store(selector, share_key, _shared)
	return _cache_entry(entry, current_classes, variation, override_meta, ancestry)


func _cache_entry(entry: Dictionary, classes: PackedStringArray, variation: String, override_meta: Variant, ancestry: String) -> Dictionary:
	_entry_cache = entry
	_entry_cache_classes = classes
	_entry_cache_variation = variation
	_entry_cache_overrides = override_meta
	_entry_cache_ancestry = ancestry
	_entry_cache_dirty = false
	return entry


func _merge_entry(selector: String, current_classes: PackedStringArray, variation: String, override_entry: Dictionary, descendant_layers: Array[Dictionary]) -> Dictionary:
	var parsed: Dictionary[String, Dictionary] = GdssStylesheet.parsed
	var entry: Dictionary = parsed.get(selector, {})
	var variations: Dictionary = entry.get(GdssValue.VARIATIONS_KEY, {}) if not entry.is_empty() else {}
	var has_variation: bool = not variation.is_empty() and variations.has(variation)
	_scoped_vars = _NONE
	for layer: Dictionary in descendant_layers:
		var inherited: Variant = layer.get("vars")
		if inherited is Dictionary:
			for key: String in inherited as Dictionary:
				_scoped_vars = _writable(_scoped_vars)
				_scoped_vars.set(key, (inherited as Dictionary).get(key))
	_absorb_vars(entry)
	for gdss_class_name: String in current_classes:
		for step: Dictionary in GdssCascade.find_class_path((parsed.get(selector, {}) as Dictionary).get(GdssValue.CLASSES_KEY, {}), gdss_class_name):
			_absorb_vars(step)
	if current_classes.is_empty() and not has_variation and override_entry.is_empty() and descendant_layers.is_empty():
		return entry
	if has_variation:
		entry = GdssCascade.merge_entries(entry, GdssCascade.resolve_override_patches(entry, variations.get(variation)))
	for layer: Dictionary in descendant_layers:
		var body: Dictionary = layer.get("entry")
		if not body.is_empty():
			entry = GdssCascade.merge_entries(entry, GdssCascade.resolve_override_patches(entry, body))
	for gdss_class_name: String in current_classes:
		var path: Array[Dictionary] = GdssCascade.find_class_path((parsed.get(selector, {}) as Dictionary).get(GdssValue.CLASSES_KEY, {}), gdss_class_name)
		for step: Dictionary in path:
			var step_rules: Variant = step.get(GdssValue.DESCENDANTS_KEY)
			if step_rules is Dictionary and not (step_rules as Dictionary).is_empty():
				entry = GdssCascade.merge_entries(entry, {GdssValue.DESCENDANTS_KEY: step_rules})
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
		var resolved: Variant = stylebox._resolve_entry().get(GdssValue.DESCENDANTS_KEY)
		return resolved if resolved is Dictionary else {}
	var entry: Dictionary = GdssStylesheet.parsed.get(node.get_class(), {})
	if entry.is_empty():
		return {}
	var container: Variant = entry.get(GdssValue.DESCENDANTS_KEY)
	var result: Dictionary = container as Dictionary if container is Dictionary else {}
	for gdss_class_name: String in node.get_meta(GDSS.CLASSES_META, PackedStringArray()) as PackedStringArray:
		var override: Dictionary = GdssCascade.find_class(entry.get(GdssValue.CLASSES_KEY, {}), gdss_class_name)
		var nested: Variant = override.get(GdssValue.DESCENDANTS_KEY)
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
	var props: Variant = rule.get(GdssValue.ANCESTOR_STATE_PREFIX + state)
	if not props is Dictionary or (props as Dictionary).is_empty():
		return {}
	return {"all": (props as Dictionary).duplicate()}


func _has_ancestor_state_rules() -> bool:
	if not _ancestor_states_dirty:
		return _ancestor_states
	_ancestor_states = false
	_ancestor_states_dirty = false
	var container: Variant = _resolve_entry().get(GdssValue.DESCENDANTS_KEY)
	if not container is Dictionary:
		return false
	for key: String in container as Dictionary:
		var rule: Variant = (container as Dictionary).get(key)
		if not rule is Dictionary:
			continue
		for state_key: String in rule as Dictionary:
			if state_key.begins_with(GdssValue.ANCESTOR_STATE_PREFIX):
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
			_set_tweened(prop_name, outgoing.get(prop_name))
	_start_transition(state, state)
	_apply_overrides(false)
	_safe_redraw()


func _resolve_value(raw: Variant, fallback: Variant, state_key: String = "") -> Variant:
	if raw is Dictionary and (raw as Dictionary).has(GdssValue.COMPOSITE4_KEY):
		var parts: Array = (raw as Dictionary).get(GdssValue.COMPOSITE4_KEY)
		return Vector4i(_resolve_composite_part(parts.get(0)), _resolve_composite_part(parts.get(1)), _resolve_composite_part(parts.get(2)), _resolve_composite_part(parts.get(3)))
	if raw is Dictionary and (raw as Dictionary).has(GdssValue.COMPOSITE2_KEY):
		var parts2: Array = (raw as Dictionary).get(GdssValue.COMPOSITE2_KEY)
		return Vector2(_resolve_composite_part_f(parts2.front()), _resolve_composite_part_f(parts2.back()))
	if raw is Dictionary and (raw as Dictionary).has(GdssValue.COLOR4_KEY):
		var sides: Array = (raw as Dictionary).get(GdssValue.COLOR4_KEY)
		var resolved_sides: Array = []
		for side: Variant in sides:
			resolved_sides.append(_resolve_value(side, fallback, state_key))
		return resolved_sides
	if raw is Dictionary and (raw as Dictionary).has(GdssValue.CALC_KEY):
		return GdssCalc.evaluate((raw as Dictionary).get(GdssValue.CALC_KEY), _calc_ref_value)
	raw = _resolve_sentinel(raw, fallback)
	if raw is Dictionary:
		var d: Dictionary = raw as Dictionary
		if d.has(GdssValue.METHOD_KEY):
			return _call_method(d, fallback, state_key)
	if raw is String:
		var s: String = raw as String
		if not s.is_empty() and s.unicode_at(0) == 35:
			if Color.html_is_valid(s):
				return Color.html(s)
			return raw
		if not s.begins_with(GdssValue.REF_PREFIX):
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


func _calc_ref_value(token: String) -> float:
	var t: String = token
	if t.begins_with("$"):
		t = GdssValue.GLOBAL_REF + t.substr(1)
	var resolved: Variant = _resolve_sentinel(t, null)
	if resolved == null and token.begins_with("$"):
		resolved = _resolve_sentinel(GdssValue.INSTANCE_REF + token.substr(1), null)
		if resolved == null:
			resolved = _resolve_sentinel(GdssValue.LOCAL_REF + token.substr(1), null)
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
	var method_name: String = descriptor.get(GdssValue.METHOD_KEY)
	var raw_args: Array = descriptor.get("args", [])
	var has_live_ref: bool = false
	for raw: Variant in raw_args:
		if raw is Dictionary:
			has_live_ref = true
			break
		var s: String = (raw as String).strip_edges()
		if s.begins_with("$") or s.begins_with(GdssValue.GLOBAL_REF) or s.begins_with(GdssValue.INSTANCE_REF):
			has_live_ref = true
			break
		if s.begins_with(GdssValue.LOCAL_REF) and _scoped_vars.has(s.substr(GdssValue.LOCAL_REF.length())):
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
		elif stripped.begins_with(GdssValue.GLOBAL_REF):
			var key: String = stripped.substr(GdssValue.GLOBAL_REF.length())
			resolved.append(GdssStylesheet.globals.get(key, null))
		elif stripped.begins_with(GdssValue.INSTANCE_REF):
			var key: String = stripped.substr(GdssValue.INSTANCE_REF.length())
			if ref != null and GdssStylesheet._instance_vars.has(ref.get_instance_id()):
				resolved.append(GdssStylesheet._instance_vars.get(ref.get_instance_id()).get(key, null))
			else:
				resolved.append(GdssStylesheet._instance_defaults.get(key, null))
		elif stripped.begins_with(GdssValue.LOCAL_REF):
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
		_method_args_cache = _writable(_method_args_cache)
		_method_args_cache.set(cache_key, resolved)
	return resolved


func _call_method(descriptor: Dictionary, fallback: Variant, state_key: String = "") -> Variant:
	var name: String = descriptor.get(GdssValue.METHOD_KEY)
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
	return GdssValue.splat_shorthand(key, _resolve_value(raw, fallback, state))


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
	if not s.begins_with(GdssValue.REF_PREFIX):
		return raw
	if s.begins_with(GdssValue.GLOBAL_REF):
		var name: String = s.substr(GdssValue.GLOBAL_REF.length())
		if GdssStylesheet.globals.has(name):
			return GdssStylesheet.globals.get(name)
		if GdssStylesheet._global_defaults.has(name):
			return GdssStylesheet._global_defaults.get(name)
		return fallback
	if s.begins_with(GdssValue.INSTANCE_REF):
		var name: String = s.substr(GdssValue.INSTANCE_REF.length())
		if ref != null:
			var id: int = ref.get_instance_id()
			if GdssStylesheet._instance_vars.has(id) and GdssStylesheet._instance_vars.get(id).has(name):
				return GdssStylesheet._instance_vars.get(id).get(name)
		if GdssStylesheet._instance_defaults.has(name):
			return GdssStylesheet._instance_defaults.get(name)
		return fallback
	if s.begins_with(GdssValue.LOCAL_REF):
		var name: String = s.substr(GdssValue.LOCAL_REF.length())
		if _scoped_vars.has(name):
			return _resolve_sentinel(_scoped_vars.get(name), fallback)
		if GdssStylesheet._local_vars.has(name):
			return GdssStylesheet._local_vars.get(name)
		return fallback
	if s.begins_with(GdssValue.LOCAL_METHOD_REF):
		var name: String = s.substr(GdssValue.LOCAL_METHOD_REF.length())
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
	return GdssValue.splat_shorthand(key, _resolve_value(raw, fallback, state))


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
	if raw is String and (raw as String).begins_with(GdssValue.LOCAL_METHOD_REF):
		var local_key: String = (raw as String).substr(GdssValue.LOCAL_METHOD_REF.length())
		return GdssStylesheet._local_vars.get(local_key, null)
	return raw


func _build_style_vals(node_type: GdssNodeType, entry: Dictionary, state: String) -> Dictionary:
	if not _tweened_values.is_empty():
		_style_revision += 1
		if _style_tween_state != state or _style_tween_session != _tween_session:
			_style_tween_state = state
			_style_tween_session = _tween_session
			_style_vals_tween = {}
			_style_dynamic_tween = []
			for prop: GdssProp in node_type.get_style_props():
				var fv: Variant = _get_val_cached(prop.name, entry, state, prop.get_default_value())
				_style_vals_tween.set(prop.name, fv if fv != null else prop.get_default_value())
				if GdssValue.is_live(GdssCascade.raw_value(entry, state, prop.name)):
					_style_dynamic_tween.append(prop)
			return _style_vals_tween
		for prop: GdssProp in _style_dynamic_tween:
			var dv: Variant = _get_val_cached(prop.name, entry, state, prop.get_default_value())
			_style_vals_tween.set(prop.name, dv if dv != null else prop.get_default_value())
		for key: String in _tweened_values:
			if _style_vals_tween.has(key):
				_style_vals_tween.set(key, _tweened_values.get(key))
		return _style_vals_tween
	if _shared != null:
		if not _shared.style_static.has(state):
			_share_style_vals(node_type, entry, state)
		if _shared.fully_shared.get(state):
			return _adopt_shared_vals(entry, state)
	if _style_vals_state != state:
		_style_vals_state = state
		_style_revision += 1
		if _shared == null:
			_style_vals_cache = {}
			_style_dynamic = []
			for prop: GdssProp in node_type.get_style_props():
				var rv: Variant = _get_val_cached(prop.name, entry, state, prop.get_default_value())
				_style_vals_cache.set(prop.name, rv if rv != null else prop.get_default_value())
				if GdssValue.is_live(GdssCascade.raw_value(entry, state, prop.name)):
					_style_dynamic.append(prop)
			return _style_vals_cache
		_style_dynamic = _shared.style_live.get(state)
		_style_vals_cache = _shared.style_static.get(state).duplicate()
		for prop: GdssProp in _shared.style_per_node.get(state):
			var nv: Variant = _get_val_cached(prop.name, entry, state, prop.get_default_value())
			_style_vals_cache.set(prop.name, nv if nv != null else prop.get_default_value())
	for prop: GdssProp in _style_dynamic:
		var dv: Variant = _live_value(prop, entry, state)
		if dv == null:
			dv = prop.get_default_value()
		var previous: Variant = _style_vals_cache.get(prop.name)
		if typeof(previous) != typeof(dv) or previous != dv:
			_style_vals_cache.set(prop.name, dv)
			_style_revision += 1
	return _style_vals_cache


func _adopt_shared_vals(entry: Dictionary, state: String) -> Dictionary:
	var live: Array = _shared.style_live.get(state)
	var values: Variant = _shared.style_static.get(state)
	if not live.is_empty():
		values = _shared.full_values(state, GDSS._globals_generation)
		if values == null:
			var built: Dictionary = (_shared.style_static.get(state) as Dictionary).duplicate()
			for prop: GdssProp in live:
				var value: Variant = _live_value(prop, entry, state)
				built.set(prop.name, value if value != null else prop.get_default_value())
			values = _shared.store_full_values(state, GDSS._globals_generation, built)
	if not is_same(values, _style_vals_cache):
		_style_vals_cache = values
		_style_revision += 1
	_style_vals_state = state
	_style_dynamic = live
	return _style_vals_cache


func _share_style_vals(node_type: GdssNodeType, entry: Dictionary, state: String) -> void:
	var static_vals: Dictionary = {}
	var live: Array[GdssProp] = []
	var per_node: Array[GdssProp] = []
	var all_shareable: bool = true
	for prop: GdssProp in node_type.get_style_props():
		var raw: Variant = GdssCascade.raw_value(entry, state, prop.name)
		if GdssValue.is_live(raw):
			live.append(prop)
			if GdssValue.is_shareable_live(raw):
				_shared.mark_global_only(state, prop.name)
			else:
				all_shareable = false
			continue
		if GdssValue.is_node_specific(raw):
			per_node.append(prop)
			continue
		var rv: Variant = _get_val_cached(prop.name, entry, state, prop.get_default_value())
		static_vals.set(prop.name, rv if rv != null else prop.get_default_value())
	static_vals.make_read_only()
	_shared.fully_shared.set(state, all_shareable and per_node.is_empty())
	_shared.style_static.set(state, static_vals)
	_shared.style_live.set(state, live)
	_shared.style_per_node.set(state, per_node)


func _live_value(prop: GdssProp, entry: Dictionary, state: String) -> Variant:
	if _tweened_values.has(prop.name) or _shared == null or not _shared.is_global_only(state, prop.name):
		return _get_val_cached(prop.name, entry, state, prop.get_default_value())
	var shared_values: Dictionary = _shared.global_values(state, GDSS._globals_generation)
	if shared_values.has(prop.name):
		return shared_values.get(prop.name)
	var value: Variant = _get_val_cached(prop.name, entry, state, prop.get_default_value())
	shared_values.set(prop.name, value)
	return value


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if ref == null:
		return
	var node_type: GdssNodeType = _resolve_gdss_node()
	if node_type == null:
		return
	if _first_drawn_frame == -1:
		_first_drawn_frame = Engine.get_process_frames()
	var entry: Dictionary = _resolve_entry()
	var state: String = _get_state()
	var vals: Dictionary = _build_style_vals(node_type, entry, state)
	var expand: Vector4 = Vector4(vals.get("expand", Vector4i.ZERO))
	rect = rect.grow_individual(expand.x, expand.z, expand.y, expand.w)
	if not rect.has_area():
		return
	if GDSS.gpu_panels_enabled():
		if _gpu == null:
			_gpu = GdssGpuRenderer.new(_safe_redraw)
		if not _gpu.is_current(to_canvas_item, rect, _style_revision):
			_gpu.draw(to_canvas_item, rect, vals, ref, GDSS.scaled_duration(_resolve_time("bg_texture", _get_state())), _style_revision, not _tweened_values.is_empty())
		return
	_free_gpu_ci()
	GdssCpuRenderer.draw(to_canvas_item, rect, vals)


func _free_gpu_ci() -> void:
	if _gpu != null:
		_gpu.release()
