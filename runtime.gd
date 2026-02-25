extends Node

const POLL_INTERVAL: float = 1.0

var _last_modified: int = 0
var _poll_timer: SceneTreeTimer = null


func _ready() -> void:
	_ensure_parsed()
	_last_modified = _get_file_modified_time()
	get_tree().node_added.connect(_on_node_added)
	_bind_tree.call_deferred(get_tree().root)
	if OS.is_debug_build():
		_schedule_poll()


func _get_file_modified_time() -> int:
	return FileAccess.get_modified_time(GdssStorage.get_save_path())


func _schedule_poll() -> void:
	_poll_timer = get_tree().create_timer(POLL_INTERVAL)
	_poll_timer.timeout.connect(_on_poll)


func _on_poll() -> void:
	var modified: int = _get_file_modified_time()
	if modified != _last_modified:
		_last_modified = modified
		_reload_parsed()
	_schedule_poll()


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
	_refresh_all_handlers()


func _refresh_all_handlers() -> void:
	_refresh_tree(get_tree().root)


func _refresh_tree(node: Node) -> void:
	if node.has_meta("gdss_handler"):
		var box: GdssPropHandler = node.get_meta("gdss_handler") as GdssPropHandler
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


func _bind_tree(node: Node) -> void:
	#print("[GDSS] _bind_tree visiting: %s | is CanvasItem: %s" % [node.get_class(), str(node is CanvasItem)])
	if node is CanvasItem:
		_try_bind(node as CanvasItem)
	for child: Node in node.get_children():
		_bind_tree(child)


func _on_node_added(node: Node) -> void:
	if node is CanvasItem:
		_try_bind(node as CanvasItem)


func _try_bind(canvas_item: CanvasItem) -> void:
	var gdss_node: GdssNode = GDSS.get_gdss_nodes().get(canvas_item.get_class())
	if not canvas_item.get_meta("gdss_enabled", false):
		return
	if canvas_item.has_meta("gdss_handler"):
		var box: GdssPropHandler = canvas_item.get_meta("gdss_handler") as GdssPropHandler
		box.ref = canvas_item
		if canvas_item.is_inside_tree():
			_rt_bind_ci(canvas_item)
			gdss_node.update_state(canvas_item)
		else:
			canvas_item.tree_entered.connect(func() -> void:
				gdss_node.update_state.call_deferred(canvas_item)
				_rt_bind_ci(canvas_item)
			, CONNECT_ONE_SHOT)
		return


func _rt_bind_ci(canvas_item: CanvasItem) -> void:
	if GDSS.get_gdss_nodes().has(canvas_item.get_class()):
		GdssNodeHandler.bind(canvas_item)
