extends Node

signal scheme_changed(scheme_name: String)
signal globals_changed
signal parsed_reloaded

# How many frames an ambiguous tree-exit is re-checked before the node is assumed to
# be deliberately detached rather than on its way out.
const PURGE_GRACE_FRAMES: int = 4

var _last_modified: int = 0
# Nodes whose tree-exit was ambiguous, mapped to how many frames they have been waited
# on. See _on_styled_node_exited.
var _pending_purge: Dictionary[int, int] = {}


func _process(_delta: float) -> void:
	if _pending_purge.is_empty():
		return
	for id: int in _pending_purge.keys():
		if not is_instance_valid(instance_from_id(id)):
			GdssNodeBinder.purge(id)
			_pending_purge.erase(id)
			continue
		var waited: int = _pending_purge.get(id) + 1
		if waited >= PURGE_GRACE_FRAMES:
			_pending_purge.erase(id)
		else:
			_pending_purge.set(id, waited)


func _ready() -> void:
	GDSS._runtime = self
	_ensure_parsed()
	if not Engine.is_editor_hint():
		var default_scheme: String = GDSS.get_default_scheme()
		if not default_scheme.is_empty() and GdssStylesheet.schemes.has(default_scheme):
			GDSS.set_scheme(default_scheme)
	_last_modified = GdssStorage.get_latest_modified()
	get_tree().node_added.connect(_on_node_added)
	_bind_tree.bind(get_tree().root).call_deferred()
	if Engine.is_editor_hint() and OS.is_debug_build() and Engine.has_singleton(&"EditorInterface"):
		var fs: Object = Engine.get_singleton(&"EditorInterface").call(&"get_resource_filesystem")
		if fs != null and not fs.is_connected(&"filesystem_changed", _on_editor_saved):
			fs.connect(&"filesystem_changed", _on_editor_saved)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and not Engine.is_editor_hint() and OS.is_debug_build():
		if not is_node_ready():
			return
		var modified: int = GdssStorage.get_latest_modified()
		if modified == _last_modified:
			return
		_last_modified = modified
		_reload_parsed()


func _on_editor_saved() -> void:
	var modified: int = GdssStorage.get_latest_modified()
	if modified == _last_modified:
		return
	_last_modified = modified
	_reload_parsed()


func _load_bundle() -> Dictionary:
	var compiled: Dictionary = GdssStorage.load_compiled()
	if compiled.has("data") and compiled.get("data") is Dictionary and not (compiled.get("data") as Dictionary).is_empty():
		var source_modified: int = GdssStorage.get_latest_modified()
		var compiled_modified: int = compiled.get("source_modified", 0)
		if source_modified == 0 or compiled_modified >= source_modified:
			return compiled.get("data")
	var data: Dictionary = GdssStorage.load_data()
	if data.get("parsed") is Dictionary and not (data.get("parsed") as Dictionary).is_empty():
		return data
	return _parse_sources()


func _parse_sources() -> Dictionary:
	var sources: PackedStringArray = GdssStorage.load_sources()
	var has_content: bool = false
	for source: String in sources:
		if not source.strip_edges().is_empty():
			has_content = true
			break
	if not has_content:
		return {}
	var parsed_data: Dictionary = GdssStylesheet.parse_paths(GdssStorage.get_save_paths())
	if OS.is_debug_build() and not Engine.is_editor_hint():
		GdssStorage.write_cache(parsed_data, GdssStylesheet._global_defaults, GdssStylesheet._instance_defaults, GdssStylesheet._local_vars, GdssStylesheet.schemes, GdssStylesheet.meta)
	return {
		"parsed": parsed_data,
		"global_defaults": GdssStylesheet._global_defaults.duplicate(true),
		"instance_defaults": GdssStylesheet._instance_defaults.duplicate(true),
		"local_vars": GdssStylesheet._local_vars.duplicate(true),
		"schemes": GdssStylesheet.schemes.duplicate(true),
		"meta": GdssStylesheet.meta.duplicate(true),
	}


func _apply_scheme_meta(data: Dictionary) -> void:
	if data.has("schemes") and data["schemes"] is Dictionary:
		GdssStylesheet.schemes.clear()
		for key: String in (data["schemes"] as Dictionary):
			GdssStylesheet.schemes[key] = (data["schemes"] as Dictionary)[key]
	if data.has("meta") and data["meta"] is Dictionary:
		GdssStylesheet.meta.clear()
		for key: String in (data["meta"] as Dictionary):
			GdssStylesheet.meta[key] = (data["meta"] as Dictionary)[key]


func _reload_parsed() -> void:
	var data: Dictionary = _load_bundle()
	if not data.has("parsed"):
		return
	GdssStylesheet._override_entry_cache.clear()
	var raw: Variant = data["parsed"]
	if not raw is Dictionary:
		return
	var parsed_data: Dictionary = raw
	GdssStylesheet.parsed.clear()
	for key: String in parsed_data:
		var val: Variant = parsed_data[key]
		if val is Dictionary:
			GdssStylesheet.parsed[key] = val
	if data.has("local_vars") and data["local_vars"] is Dictionary:
		var local_vars: Dictionary = data["local_vars"]
		GdssStylesheet._local_vars.clear()
		for key: String in local_vars:
			GdssStylesheet._local_vars[key] = local_vars[key]
	_apply_scheme_meta(data)
	if data.has("global_defaults") and data["global_defaults"] is Dictionary:
		var global_defaults: Dictionary = data["global_defaults"]
		GdssStylesheet._global_defaults.clear()
		for key: String in global_defaults:
			GdssStylesheet._global_defaults[key] = global_defaults[key]
			if not GdssStylesheet.globals.has(key):
				GdssStylesheet.globals[key] = global_defaults[key]
	if data.has("instance_defaults") and data["instance_defaults"] is Dictionary:
		var instance_defaults: Dictionary = data["instance_defaults"]
		GdssStylesheet._instance_defaults.clear()
		for key: String in instance_defaults:
			GdssStylesheet._instance_defaults[key] = instance_defaults[key]
		GdssStylesheet._instance_scheme_base = GdssStylesheet._instance_defaults.duplicate(true)
	for method: GdssMethod in GDSS._get_gdss_methods().values():
		if method.returns_texture:
			method.clear_live_textures()
	if not GdssStylesheet.current_scheme.is_empty() and GdssStylesheet.schemes.has(GdssStylesheet.current_scheme):
		GDSS.set_scheme(GdssStylesheet.current_scheme)
	_refresh_all_styleboxes()
	parsed_reloaded.emit()


func _refresh_all_styleboxes() -> void:
	for stylebox: GdssStylebox in GdssNodeBinder.get_all_styleboxes():
		var item: Node = stylebox.ref
		if item == null:
			continue
		stylebox.reapply() # reapply() emits changed, which repaints Window-derived nodes
		if stylebox == GdssNodeBinder.get_primary_stylebox(item):
			_connect_event_signals(item)
		if item is CanvasItem:
			(item as CanvasItem).queue_redraw()


func _ensure_parsed() -> void:
	if not GdssStylesheet.parsed.is_empty():
		return
	var data: Dictionary = _load_bundle()
	if not data.has("parsed"):
		return
	var raw: Variant = data["parsed"]
	if not raw is Dictionary:
		return
	for key: String in (raw as Dictionary):
		var val: Variant = (raw as Dictionary)[key]
		if val is Dictionary:
			GdssStylesheet.parsed[key] = val
	if data.has("global_defaults") and data["global_defaults"] is Dictionary:
		for key: String in (data["global_defaults"] as Dictionary):
			var val: Variant = (data["global_defaults"] as Dictionary)[key]
			GdssStylesheet._global_defaults[key] = val
			if not GdssStylesheet.globals.has(key):
				GdssStylesheet.globals[key] = val
	if data.has("instance_defaults") and data["instance_defaults"] is Dictionary:
		for key: String in (data["instance_defaults"] as Dictionary):
			GdssStylesheet._instance_defaults[key] = (data["instance_defaults"] as Dictionary)[key]
		GdssStylesheet._instance_scheme_base = GdssStylesheet._instance_defaults.duplicate(true)
	if data.has("local_vars") and data["local_vars"] is Dictionary:
		for key: String in (data["local_vars"] as Dictionary):
			GdssStylesheet._local_vars[key] = (data["local_vars"] as Dictionary)[key]
	_apply_scheme_meta(data)


func _bind_tree(node: Node) -> void:
	if node is CanvasItem or node is Window:
		_try_bind(node)
	for child: Node in node.get_children():
		_bind_tree(child)


func _on_node_added(node: Node) -> void:
	if node is CanvasItem or node is Window:
		_try_bind(node)


func _try_bind(canvas_item: Node) -> void:
	var node_type: GdssNodeType = GDSS._get_node_types().get(canvas_item.get_class())
	if not node_type:
		return
	if not GDSS.resolve_mode(canvas_item):
		if GdssNodeBinder.is_bound(canvas_item):
			_disconnect_node_signals(canvas_item)
			GdssNodeBinder.unbind(canvas_item)
		else:
			GdssNodeBinder.detach_foreign_styleboxes(canvas_item, node_type)
		return
	GdssNodeBinder.bind(canvas_item, true, node_type)
	node_type.update_state(canvas_item)
	var exit_cb: Callable = _on_styled_node_exited.bind(canvas_item.get_instance_id())
	if not canvas_item.tree_exited.is_connected(exit_cb):
		canvas_item.tree_exited.connect(exit_cb)
	# Not all Windows expose visibility_changed, so has_signal keeps the connect safe.
	if canvas_item.has_signal(&"visibility_changed"):
		var vis_cb: Callable = _on_styled_visibility_changed.bind(canvas_item)
		if not canvas_item.visibility_changed.is_connected(vis_cb):
			canvas_item.visibility_changed.connect(vis_cb)
			var primary: GdssStylebox = GdssNodeBinder.get_primary_stylebox(canvas_item)
			if primary != null:
				primary._last_visible = canvas_item.visible
	_connect_event_signals(canvas_item)


const _EVENT_SIGNALS: Dictionary = {
	"pressed": ["on_pressed", "_ev_pressed"],
	"focus_entered": ["on_focus", "_ev_focus"],
	"focus_exited": ["on_blur", "_ev_blur"],
	"mouse_entered": ["on_mouse_entered", "_ev_mouse_entered"],
	"mouse_exited": ["on_mouse_exited", "_ev_mouse_exited"],
	"toggled": ["on_toggled", "_ev_toggled"],
}


func _connect_event_signals(canvas_item: Node) -> void:
	var primary: GdssStylebox = GdssNodeBinder.get_primary_stylebox(canvas_item)
	if primary == null:
		return
	var entry: Dictionary = primary._resolve_entry()
	for sig: String in _EVENT_SIGNALS:
		if not canvas_item.has_signal(sig):
			continue
		var info: Array = _EVENT_SIGNALS.get(sig)
		var cb: Callable = Callable(primary, info.get(1))
		var want: bool = not entry.is_empty() and entry.has(info.get(0))
		var connected: bool = canvas_item.is_connected(sig, cb)
		if want and not connected:
			canvas_item.connect(sig, cb)
		elif connected and not want:
			canvas_item.disconnect(sig, cb)


func _disconnect_node_signals(canvas_item: Node) -> void:
	if canvas_item.has_signal(&"visibility_changed"):
		var vis_cb: Callable = _on_styled_visibility_changed.bind(canvas_item)
		if canvas_item.visibility_changed.is_connected(vis_cb):
			canvas_item.visibility_changed.disconnect(vis_cb)
	var primary: GdssStylebox = GdssNodeBinder.get_primary_stylebox(canvas_item)
	if primary == null:
		return
	for sig: String in _EVENT_SIGNALS:
		if not canvas_item.has_signal(sig):
			continue
		var info: Array = _EVENT_SIGNALS.get(sig)
		var cb: Callable = Callable(primary, info.get(1))
		if canvas_item.is_connected(sig, cb):
			canvas_item.disconnect(sig, cb)


# A styled node that leaves the tree for good must drop its registry slot, or
# GdssNodeBinder._registry grows without bound. tree_exited also fires on a plain remove
# or a reparent, so purge only when the node is really being destroyed; an ambiguous
# removal is re-checked over the next few frames. One call_deferred check is not enough:
# change_scene_to_file emits tree_exited while the outgoing nodes are still valid.
func _on_styled_node_exited(id: int) -> void:
	var obj: Object = instance_from_id(id)
	if not is_instance_valid(obj):
		GdssNodeBinder.purge(id)
		return
	if (obj as Node).is_queued_for_deletion():
		GdssNodeBinder.purge(id)
		return
	_pending_purge.set(id, 0)


# Drives on_show()/on_hide() one-shot transitions off the node's own visibility.
func _on_styled_visibility_changed(canvas_item: Node) -> void:
	if not is_instance_valid(canvas_item):
		return
	var stylebox: GdssStylebox = GdssNodeBinder.get_primary_stylebox(canvas_item)
	if stylebox != null:
		stylebox._on_node_visibility_changed()
