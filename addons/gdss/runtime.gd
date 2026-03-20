extends Node

var _last_modified: int = 0


func _ready() -> void:
	_ensure_parsed()
	_last_modified = FileAccess.get_modified_time(GdssStorage.get_save_path())
	get_tree().node_added.connect(_on_node_added)
	_bind_tree(get_tree().root)
	_bind_tree.bind(get_tree().root).call_deferred()

	if Engine.is_editor_hint() and OS.is_debug_build():
		EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_editor_saved)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and not Engine.is_editor_hint() and OS.is_debug_build():
		var modified: int = FileAccess.get_modified_time(GdssStorage.get_save_path())
		if modified == _last_modified:
			return
		_last_modified = modified
		_reload_parsed()


func _on_editor_saved() -> void:
	var modified: int = FileAccess.get_modified_time(GdssStorage.get_save_path())
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
	for key: String in (raw as Dictionary):
		var val: Variant = (raw as Dictionary)[key]
		if val is Dictionary:
			GdssInterpreter.parsed[key] = val
	if data.has("local_vars") and data["local_vars"] is Dictionary:
		for key: String in (data["local_vars"] as Dictionary):
			GdssInterpreter._local_vars[key] = (data["local_vars"] as Dictionary)[key]
	for method: GdssMethod in GDSS._get_gdss_methods().values():
		if method.returns_texture:
			method.clear_live_textures()
	_refresh_all_handlers()


func _refresh_all_handlers() -> void:
	_refresh_tree(get_tree().root)


func _refresh_tree(node: Node) -> void:
	var gdss_node: GdssNode = GDSS._get_gdss_nodes().get(node.get_class())
	if gdss_node != null:
		if gdss_node.is_static:
			for state: String in gdss_node.states:
				if node.has_meta("gdss_handler_" + state):
					var box: GdssPropHandler = GdssNodeHandler.get_handler(node as CanvasItem, state)
					if box == null:
						continue
					box._tweened_values.clear()
					box._apply_overrides()
					box.emit_changed()
			if node is CanvasItem:
				(node as CanvasItem).queue_redraw()
		elif node.has_meta(&"gdss_handler"):
			var box: GdssPropHandler = GdssNodeHandler.get_handler(node as CanvasItem)
			if box != null:
				box._tweened_values.clear()
				box._apply_overrides()
				box.emit_changed()
				if node is CanvasItem:
					(node as CanvasItem).queue_redraw()
	for child: Node in node.get_children():
		_refresh_tree(child)


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
	var gdss_node: GdssNode = GDSS._get_gdss_nodes().get(canvas_item.get_class())
	if not gdss_node:
		return
	if not canvas_item.get_meta("gdss_enabled", false):
		return
	_rt_bind_ci(canvas_item)
	gdss_node.update_state(canvas_item)


func _rt_bind_ci(canvas_item: CanvasItem) -> void:
	if GDSS._get_gdss_nodes().has(canvas_item.get_class()):
		GdssNodeHandler.bind(canvas_item)
