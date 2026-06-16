extends Node

var _last_modified: int = 0


func _ready() -> void:
	_ensure_parsed()
	_last_modified = GdssStorage.get_latest_modified()
	get_tree().node_added.connect(_on_node_added)
	_bind_tree.bind(get_tree().root).call_deferred()

	if Engine.is_editor_hint() and OS.is_debug_build():
		EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_editor_saved)


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


func _reload_parsed() -> void:
	var data: Dictionary = GdssStorage.load_data()
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
	for method: GdssMethod in GDSS._get_gdss_methods().values():
		if method.returns_texture:
			method.clear_live_textures()
	_refresh_all_handlers()


func _refresh_all_handlers() -> void:
	for handler: GdssPropHandler in GdssNodeHandler.get_all_handlers():
		var item: CanvasItem = handler.ref
		if item == null:
			continue
		handler.reapply()
		item.queue_redraw()


func _ensure_parsed() -> void:
	if not GdssInterpreter.parsed.is_empty():
		return
	var data: Dictionary = GdssStorage.load_data()
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
	if data.has("local_vars") and data["local_vars"] is Dictionary:
		for key: String in (data["local_vars"] as Dictionary):
			GdssInterpreter._local_vars[key] = (data["local_vars"] as Dictionary)[key]


func _bind_tree(node: Node) -> void:
	if node is CanvasItem:
		_try_bind(node as CanvasItem)
	for child: Node in node.get_children():
		_bind_tree(child)


func _on_node_added(node: Node) -> void:
	if node is CanvasItem:
		_try_bind(node as CanvasItem)


func _try_bind(canvas_item: CanvasItem) -> void:
	var in_group: bool = canvas_item.is_in_group(GdssNodeHandler.GROUP)
	if not in_group and not canvas_item.get_meta("gdss_enabled", false):
		return
	var gdss_node: GdssNode = GDSS._get_gdss_nodes().get(canvas_item.get_class())
	if not gdss_node:
		return
	if not in_group:
		canvas_item.add_to_group(GdssNodeHandler.GROUP)
	GdssNodeHandler.bind(canvas_item)
	gdss_node.update_state(canvas_item)
