extends Node

signal scheme_changed(scheme_name: String)
signal globals_changed
signal parsed_reloaded

var _last_modified: int = 0


func _ready() -> void:
	GDSS._runtime = self
	_ensure_parsed()
	if not Engine.is_editor_hint():
		var default_scheme: String = GDSS.get_default_scheme()
		if not default_scheme.is_empty() and GdssInterpreter.schemes.has(default_scheme):
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
	if compiled.has("data") and compiled["data"] is Dictionary and not (compiled["data"] as Dictionary).is_empty():
		var source_modified: int = GdssStorage.get_latest_modified()
		var compiled_modified: int = compiled.get("source_modified", 0)
		if source_modified == 0 or compiled_modified >= source_modified:
			return compiled["data"]
	return GdssStorage.load_data()


func _apply_scheme_meta(data: Dictionary) -> void:
	if data.has("schemes") and data["schemes"] is Dictionary:
		GdssInterpreter.schemes.clear()
		for key: String in (data["schemes"] as Dictionary):
			GdssInterpreter.schemes[key] = (data["schemes"] as Dictionary)[key]
	if data.has("meta") and data["meta"] is Dictionary:
		GdssInterpreter.meta.clear()
		for key: String in (data["meta"] as Dictionary):
			GdssInterpreter.meta[key] = (data["meta"] as Dictionary)[key]


func _reload_parsed() -> void:
	var data: Dictionary = _load_bundle()
	if not data.has("parsed"):
		return
	var raw: Variant = data["parsed"]
	if not raw is Dictionary:
		return
	GdssInterpreter.parsed.clear()
	for key: String in (raw as Dictionary):
		var val: Variant = (raw as Dictionary)[key]
		if val is Dictionary:
			GdssInterpreter.parsed[key] = val
	if data.has("local_vars") and data["local_vars"] is Dictionary:
		GdssInterpreter._local_vars.clear()
		for key: String in (data["local_vars"] as Dictionary):
			GdssInterpreter._local_vars[key] = (data["local_vars"] as Dictionary)[key]
	_apply_scheme_meta(data)
	if data.has("global_defaults") and data["global_defaults"] is Dictionary:
		GdssInterpreter._global_defaults.clear()
		for key: String in (data["global_defaults"] as Dictionary):
			GdssInterpreter._global_defaults[key] = (data["global_defaults"] as Dictionary)[key]
	if data.has("instance_defaults") and data["instance_defaults"] is Dictionary:
		GdssInterpreter._instance_defaults.clear()
		for key: String in (data["instance_defaults"] as Dictionary):
			GdssInterpreter._instance_defaults[key] = (data["instance_defaults"] as Dictionary)[key]
		GdssInterpreter._instance_scheme_base = GdssInterpreter._instance_defaults.duplicate(true)
	for method: GdssMethod in GDSS._get_gdss_methods().values():
		if method.returns_texture:
			method.clear_live_textures()
	if not GdssInterpreter.current_scheme.is_empty() and GdssInterpreter.schemes.has(GdssInterpreter.current_scheme):
		GDSS.set_scheme(GdssInterpreter.current_scheme)
	_refresh_all_handlers()
	parsed_reloaded.emit()


func _refresh_all_handlers() -> void:
	for handler: GdssPropHandler in GdssNodeHandler.get_all_handlers():
		var item: Node = handler.ref
		if item == null:
			continue
		handler.reapply() # reapply() emits changed, which repaints Window-derived nodes
		if item is CanvasItem:
			(item as CanvasItem).queue_redraw()


func _ensure_parsed() -> void:
	if not GdssInterpreter.parsed.is_empty():
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
			GdssInterpreter.parsed[key] = val
	if data.has("global_defaults") and data["global_defaults"] is Dictionary:
		for key: String in (data["global_defaults"] as Dictionary):
			var val: Variant = (data["global_defaults"] as Dictionary)[key]
			GdssInterpreter._global_defaults[key] = val
			if not GdssInterpreter.globals.has(key):
				GdssInterpreter.globals[key] = val
	if data.has("instance_defaults") and data["instance_defaults"] is Dictionary:
		for key: String in (data["instance_defaults"] as Dictionary):
			GdssInterpreter._instance_defaults[key] = (data["instance_defaults"] as Dictionary)[key]
		GdssInterpreter._instance_scheme_base = GdssInterpreter._instance_defaults.duplicate(true)
	if data.has("local_vars") and data["local_vars"] is Dictionary:
		for key: String in (data["local_vars"] as Dictionary):
			GdssInterpreter._local_vars[key] = (data["local_vars"] as Dictionary)[key]
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
	if not GDSS.resolve_mode(canvas_item):
		if GdssNodeHandler.is_bound(canvas_item):
			GdssNodeHandler.unbind(canvas_item)
		return
	var gdss_node: GdssNode = GDSS._get_gdss_nodes().get(canvas_item.get_class())
	if not gdss_node:
		return
	GdssNodeHandler.bind(canvas_item)
	gdss_node.update_state(canvas_item)
	var exit_cb: Callable = _on_styled_node_exited.bind(canvas_item.get_instance_id())
	if not canvas_item.tree_exited.is_connected(exit_cb):
		canvas_item.tree_exited.connect(exit_cb)
	# on_show/on_hide events drive off visibility_changed (CanvasItem; not all Windows
	# expose it). has_signal keeps the connect safe for Window-derived nodes.
	if canvas_item.has_signal(&"visibility_changed"):
		var vis_cb: Callable = _on_styled_visibility_changed.bind(canvas_item)
		if not canvas_item.visibility_changed.is_connected(vis_cb):
			canvas_item.visibility_changed.connect(vis_cb)
			var primary: GdssPropHandler = GdssNodeHandler.get_primary_handler(canvas_item)
			if primary != null:
				primary._last_visible = canvas_item.visible


# Runtime teardown counterpart to _on_node_added: a styled node that leaves the
# tree for good must drop its registry slot, or GdssNodeHandler._registry (and
# every handler StyleBox it holds) grows without bound. tree_exited also fires on
# a plain remove or a reparent, so we only purge when the node is actually being
# destroyed; an ambiguous removal is re-checked deferred, by which point a
# reparented node is valid again and a freed one is gone.
func _on_styled_node_exited(id: int) -> void:
	var obj: Object = instance_from_id(id)
	if not is_instance_valid(obj):
		GdssNodeHandler.purge(id)
		return
	if (obj as Node).is_queued_for_deletion():
		GdssNodeHandler.purge(id)
		return
	GdssNodeHandler._check_purge.call_deferred(id)


# Drives on_show()/on_hide() one-shot transitions off the node's own visibility.
func _on_styled_visibility_changed(canvas_item: Node) -> void:
	if not is_instance_valid(canvas_item):
		return
	var handler: GdssPropHandler = GdssNodeHandler.get_primary_handler(canvas_item)
	if handler != null:
		handler._on_node_visibility_changed()
