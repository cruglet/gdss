@tool
class_name GdssNodeBinder
extends Object

const GROUP: StringName = &"gdss"

static var _registry: Dictionary[int, Dictionary] = {}
static var _all_cache: Array[GdssStylebox] = []
static var _all_dirty: bool = true


static func get_stylebox(canvas_item: Node, state: String = "") -> GdssStylebox:
	var id: int = canvas_item.get_instance_id()
	if not _registry.has(id):
		return null
	return _registry.get(id).get(state)


static func get_all_styleboxes() -> Array[GdssStylebox]:
	if not _all_dirty:
		return _all_cache
	_all_cache.clear()
	var dead: Array[int] = []
	for id: int in _registry:
		if not is_instance_valid(instance_from_id(id)):
			dead.append(id)
			continue
		var slots: Dictionary = _registry.get(id)
		for state: String in slots:
			var stylebox: GdssStylebox = slots.get(state)
			if stylebox != null:
				_all_cache.append(stylebox)
	for id: int in dead:
		purge(id)
	_all_dirty = false
	return _all_cache


static func mark_dirty() -> void:
	_all_dirty = true


static func purge(id: int) -> void:
	if _registry.has(id):
		for stylebox: GdssStylebox in (_registry.get(id) as Dictionary).values():
			if stylebox != null:
				stylebox._kill_tween()
				stylebox._free_gpu_ci()
		_registry.erase(id)
		_all_dirty = true
	for method: GdssMethod in GDSS._get_gdss_methods().values():
		if method.returns_texture:
			method.purge_node(id)
	GdssStylesheet._instance_vars.erase(id)


static func _check_purge(id: int) -> void:
	if is_instance_valid(instance_from_id(id)):
		return
	purge(id)


static func get_styleboxes(canvas_item: Node) -> Array[GdssStylebox]:
	var result: Array[GdssStylebox] = []
	if canvas_item == null:
		return result
	var slots: Dictionary = _registry.get(canvas_item.get_instance_id(), {})
	for stylebox: GdssStylebox in slots.values():
		if stylebox != null:
			result.append(stylebox)
	return result


static func get_slots(canvas_item: Node) -> Dictionary:
	if canvas_item == null:
		return {}
	return _registry.get(canvas_item.get_instance_id(), {})


static func get_primary_stylebox(canvas_item: Node) -> GdssStylebox:
	if canvas_item == null:
		return null
	var slots: Dictionary = _registry.get(canvas_item.get_instance_id(), {})
	if slots.has(""):
		return slots.get("")
	for state: String in slots:
		return slots.get(state)
	return null


static func is_enabled(canvas_item: Node) -> bool:
	return GDSS.resolve_mode(canvas_item)


static func is_bound(canvas_item: Node) -> bool:
	return _registry.has(canvas_item.get_instance_id())


static func refresh(canvas_item: Node) -> void:
	if canvas_item == null:
		return
	var slots: Dictionary = get_slots(canvas_item)
	for state: String in slots:
		var stylebox: GdssStylebox = slots.get(state)
		if stylebox != null:
			stylebox.reapply()
	if canvas_item is CanvasItem:
		(canvas_item as CanvasItem).queue_redraw()
	if GdssStylesheet.has_descendant_rules and not _refreshing_descendants:
		_refreshing_descendants = true
		_refresh_descendants(canvas_item)
		_refreshing_descendants = false


static var _refreshing_descendants: bool = false


static func reposition(node: Node) -> void:
	var styleboxes: Array[GdssStylebox] = get_styleboxes(node)
	for stylebox: GdssStylebox in styleboxes:
		stylebox._invalidate_entry_cache()
	for stylebox: GdssStylebox in styleboxes:
		stylebox._apply_overrides(false)
	if node is CanvasItem:
		(node as CanvasItem).queue_redraw()


static func _refresh_descendants(node: Node) -> void:
	for child: Node in node.get_children(true):
		var styleboxes: Array[GdssStylebox] = get_styleboxes(child)
		for stylebox: GdssStylebox in styleboxes:
			stylebox._kill_tween()
			stylebox._invalidate_entry_cache()
		for stylebox: GdssStylebox in styleboxes:
			stylebox._apply_overrides()
			stylebox.emit_changed()
		if child is CanvasItem:
			(child as CanvasItem).queue_redraw()
		_refresh_descendants(child)


static func refresh_vars(canvas_item: Node) -> void:
	if canvas_item == null:
		return
	var slots: Dictionary = get_slots(canvas_item)
	for state: String in slots:
		var stylebox: GdssStylebox = slots.get(state)
		if stylebox != null:
			stylebox.refresh_globals()
	if canvas_item is CanvasItem:
		(canvas_item as CanvasItem).queue_redraw()
	else:
		for state: String in slots:
			var stylebox: GdssStylebox = slots.get(state)
			if stylebox != null:
				stylebox.emit_changed()


static func rebind_tree(node: Node) -> void:
	if node == null:
		return
	if node is CanvasItem:
		_migrate_legacy(node as CanvasItem)
		apply_mode(node)
	elif node is Window:
		apply_mode(node)
	for child: Node in node.get_children():
		rebind_tree(child)


static func apply_mode_tree(node: Node) -> void:
	if node == null:
		return
	if node is CanvasItem or node is Window:
		apply_mode(node)
	for child: Node in node.get_children():
		apply_mode_tree(child)


static func apply_mode(canvas_item: Node) -> void:
	if not GDSS._get_node_types().has(canvas_item.get_class()):
		return
	if GDSS.resolve_mode(canvas_item):
		bind(canvas_item)
	elif _registry.has(canvas_item.get_instance_id()):
		unbind(canvas_item)


static func detach_foreign_styleboxes(node: Node, node_type: GdssNodeType = null) -> void:
	if not (node is Control or node is Window):
		return
	if node_type == null:
		node_type = GDSS._get_node_types().get(node.get_class())
	if node_type == null or node_type.states.is_empty():
		return
	var control: Variant = node
	var removed: bool = false
	for state: String in node_type.states:
		if not control.has_theme_stylebox_override(state):
			continue
		var sb: StyleBox = control.get_theme_stylebox(state)
		if not sb is GdssStylebox:
			continue
		var owner_node: Node = (sb as GdssStylebox).ref
		if owner_node != null and owner_node != node:
			if not removed:
				control.begin_bulk_theme_override()
				removed = true
			control.remove_theme_stylebox_override(state)
	if removed:
		control.end_bulk_theme_override()


static func set_mode_state(node: Node, mode: GDSS.GdssMode, in_legacy_group: bool) -> void:
	if mode == GDSS.GdssMode.INHERIT:
		if node.has_meta(GDSS.MODE_META):
			node.remove_meta(GDSS.MODE_META)
	else:
		node.set_meta(GDSS.MODE_META, mode)
	if in_legacy_group and not node.is_in_group(GROUP):
		node.add_to_group(GROUP, true)
	elif not in_legacy_group and node.is_in_group(GROUP):
		node.remove_from_group(GROUP)
	apply_mode_tree(node)
	if Engine.is_editor_hint():
		node.notify_property_list_changed()


static func _migrate_legacy(canvas_item: CanvasItem) -> void:
	if canvas_item.is_in_group(GROUP):
		return
	if not canvas_item.has_meta(&"gdss_enabled"):
		return
	var was_enabled: bool = canvas_item.get_meta(&"gdss_enabled", false)
	for meta_key: StringName in [&"gdss_enabled", &"gdss_handler"]:
		if canvas_item.has_meta(meta_key):
			canvas_item.remove_meta(meta_key)
	var node_type: GdssNodeType = GDSS._get_node_types().get(canvas_item.get_class())
	if node_type != null:
		for state: String in node_type.states:
			var meta_key: StringName = "gdss_handler_" + state
			if canvas_item.has_meta(meta_key):
				canvas_item.remove_meta(meta_key)
	if was_enabled:
		canvas_item.set_meta(GDSS.MODE_META, GDSS.GdssMode.ENABLE)


static func bind(canvas_item: Node, apply: bool = true, node_type: GdssNodeType = null) -> void:
	if node_type == null:
		node_type = GDSS._get_node_types().get(canvas_item.get_class())
	if node_type == null:
		return
	if not (canvas_item is Control or canvas_item is Window):
		return
	var control: Variant = canvas_item
	control.begin_bulk_theme_override()
	var styleboxes: Array[GdssStylebox] = []
	if node_type.is_static:
		if node_type.states.is_empty():
			styleboxes.append(_obtain(canvas_item, control, "", ""))
		else:
			for state: String in node_type.states:
				var stylebox: GdssStylebox = _obtain(canvas_item, control, state, state)
				stylebox._slot_state = state
				styleboxes.append(stylebox)
	else:
		var states: PackedStringArray = node_type.states
		var first_slot: String = states.get(0) if not states.is_empty() else ""
		var stylebox: GdssStylebox = _obtain(canvas_item, control, "", first_slot)
		for state: String in states:
			if not control.has_theme_stylebox_override(state) or control.get_theme_stylebox(state) != stylebox:
				control.add_theme_stylebox_override(state, stylebox)
		styleboxes.append(stylebox)
		if apply and canvas_item is CanvasItem:
			var active: String = node_type.resolve_state(canvas_item as CanvasItem)
			if stylebox.current_state != active:
				var clear: bool = not stylebox.current_state.is_empty()
				stylebox._seeding = true
				stylebox.current_state = active
				stylebox._seeding = false
				stylebox._apply_overrides_unwrapped(node_type, control, clear)
				(canvas_item as CanvasItem).queue_redraw()
	control.end_bulk_theme_override()
	if apply and node_type.is_static:
		for stylebox: GdssStylebox in styleboxes:
			stylebox._apply_overrides(false)
	node_type.bind_canvas_item(canvas_item)


static func _obtain(canvas_item: Node, control: Variant, state: String, slot: String) -> GdssStylebox:
	var slots: Dictionary = _registry.get_or_add(canvas_item.get_instance_id(), {})
	var stylebox: GdssStylebox = slots.get(state)
	if stylebox == null and not slot.is_empty():
		var existing: StyleBox = control.get_theme_stylebox(slot) if control.has_theme_stylebox_override(slot) else null
		if existing is GdssStylebox:
			var candidate: GdssStylebox = existing as GdssStylebox
			var bound: Node = candidate.ref
			if bound == null or bound == canvas_item:
				stylebox = candidate
	if stylebox == null:
		stylebox = GdssStylebox.new()
	if slots.get(state) != stylebox:
		_all_dirty = true
	slots.set(state, stylebox)
	stylebox.ref = canvas_item
	if not slot.is_empty() and (not control.has_theme_stylebox_override(slot) or control.get_theme_stylebox(slot) != stylebox):
		control.add_theme_stylebox_override(slot, stylebox)
	_connect_editor(stylebox)
	return stylebox


static func _connect_editor(stylebox: GdssStylebox) -> void:
	if not Engine.is_editor_hint():
		return
	var interp: GdssStylesheet = GdssStylesheet.get_instance()
	if is_instance_valid(interp) and not interp.parsed_changed.is_connected(stylebox._on_parsed_changed):
		interp.parsed_changed.connect(stylebox._on_parsed_changed)


static func unbind(canvas_item: Node) -> void:
	var node_type: GdssNodeType = GDSS._get_node_types().get(canvas_item.get_class())
	if node_type == null:
		printerr("Could not unbind %s of type \"%s\"" % [canvas_item, canvas_item.get_class()])
		return
	if not (canvas_item is Control or canvas_item is Window):
		return
	var control: Variant = canvas_item
	node_type.unbind_canvas_item(canvas_item)
	var interp: GdssStylesheet = GdssStylesheet.get_instance() if Engine.is_editor_hint() else null
	var slots: Dictionary = _registry.get(canvas_item.get_instance_id(), {})
	for stylebox: GdssStylebox in slots.values():
		if stylebox == null:
			continue
		stylebox._kill_tween()
		stylebox._reset_node_props(node_type, control, false)
		stylebox._free_gpu_ci()
		if is_instance_valid(interp) and interp.parsed_changed.is_connected(stylebox._on_parsed_changed):
			interp.parsed_changed.disconnect(stylebox._on_parsed_changed)
	control.begin_bulk_theme_override()
	for stylebox: GdssStylebox in slots.values():
		if stylebox != null:
			stylebox.remove_applied_overrides(control)
	for state: String in node_type.states:
		control.remove_theme_stylebox_override(state)
	control.end_bulk_theme_override()
	_registry.erase(canvas_item.get_instance_id())
	_all_dirty = true
	GDSS.clear_instance_vars(canvas_item)
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		var ei: Object = Engine.get_singleton(&"EditorInterface")
		if ei.call(&"get_edited_scene_root") != null:
			ei.call(&"mark_scene_as_unsaved")


static func strip_overrides() -> void:
	for id: int in _registry.keys():
		var canvas_item: Node = instance_from_id(id) as Node
		if not is_instance_valid(canvas_item):
			continue
		var node_type: GdssNodeType = GDSS._get_node_types().get(canvas_item.get_class())
		if node_type == null:
			continue
		if not (canvas_item is Control or canvas_item is Window):
			continue
		var control: Variant = canvas_item
		for stylebox: GdssStylebox in _registry.get(id, {}).values():
			if stylebox != null:
				stylebox.remove_applied_overrides(control)
				stylebox._reset_node_props(node_type, control, false)
		for state: String in node_type.states:
			control.remove_theme_stylebox_override(state)


static func reapply_overrides() -> void:
	for id: int in _registry.keys():
		var canvas_item: Node = instance_from_id(id) as Node
		if not is_instance_valid(canvas_item):
			continue
		var node_type: GdssNodeType = GDSS._get_node_types().get(canvas_item.get_class())
		if node_type == null:
			continue
		if not (canvas_item is Control or canvas_item is Window):
			continue
		var control: Variant = canvas_item
		for stylebox: GdssStylebox in _registry.get(id, {}).values():
			if stylebox == null:
				continue
			if node_type.is_static:
				if not stylebox._slot_state.is_empty():
					control.add_theme_stylebox_override(stylebox._slot_state, stylebox)
			else:
				for state: String in node_type.states:
					control.add_theme_stylebox_override(state, stylebox)
			stylebox._apply_overrides(false)
