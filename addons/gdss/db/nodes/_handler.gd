@tool
class_name GdssNodeHandler
extends Object

const GROUP: StringName = &"gdss"

static var _registry: Dictionary = {}


static func _key(canvas_item: CanvasItem, state: String = "") -> String:
	return "%d:%s" % [canvas_item.get_instance_id(), state]


static func get_handler(canvas_item: CanvasItem, state: String = "") -> GdssPropHandler:
	return _registry.get(_key(canvas_item, state))


static func get_handlers(canvas_item: CanvasItem) -> Array[GdssPropHandler]:
	var result: Array[GdssPropHandler] = []
	if canvas_item == null:
		return result
	var gdss_node: GdssNode = GDSS._get_gdss_nodes().get(canvas_item.get_class())
	if gdss_node == null:
		return result
	if gdss_node.is_static:
		for state: String in gdss_node.states:
			var box: GdssPropHandler = _registry.get(_key(canvas_item, state))
			if box != null:
				result.append(box)
	else:
		var box: GdssPropHandler = _registry.get(_key(canvas_item))
		if box != null:
			result.append(box)
	return result


static func is_enabled(canvas_item: CanvasItem) -> bool:
	return canvas_item.is_in_group(GROUP)


static func refresh(canvas_item: CanvasItem) -> void:
	if canvas_item == null:
		return
	for box: GdssPropHandler in get_handlers(canvas_item):
		box._tweened_values.clear()
		box._invalidate_entry_cache()
		box._apply_overrides()
		box.emit_changed()
	canvas_item.queue_redraw()


static func rebind_tree(node: Node) -> void:
	if node == null:
		return
	if node is CanvasItem:
		var canvas_item: CanvasItem = node as CanvasItem
		_migrate_legacy(canvas_item)
		if canvas_item.is_in_group(GROUP) and GDSS._get_gdss_nodes().has(canvas_item.get_class()):
			bind(canvas_item)
	for child: Node in node.get_children():
		rebind_tree(child)


static func _migrate_legacy(canvas_item: CanvasItem) -> void:
	if canvas_item.is_in_group(GROUP):
		return
	if not canvas_item.has_meta(&"gdss_enabled"):
		return
	var was_enabled: bool = canvas_item.get_meta(&"gdss_enabled", false)
	for meta_key: StringName in [&"gdss_enabled", &"gdss_handler"]:
		if canvas_item.has_meta(meta_key):
			canvas_item.remove_meta(meta_key)
	var gdss_node: GdssNode = GDSS._get_gdss_nodes().get(canvas_item.get_class())
	if gdss_node != null:
		for state: String in gdss_node.states:
			var meta_key: StringName = "gdss_handler_" + state
			if canvas_item.has_meta(meta_key):
				canvas_item.remove_meta(meta_key)
	if was_enabled:
		canvas_item.add_to_group(GROUP, true)


static func bind(canvas_item: CanvasItem) -> void:
	var gdss_node: GdssNode = GDSS._get_gdss_nodes().get(canvas_item.get_class())
	if gdss_node == null:
		return
	var control: Control = canvas_item as Control
	if control == null:
		return
	if gdss_node.is_static:
		for state: String in gdss_node.states:
			var box: GdssPropHandler = _obtain(canvas_item, control, state, state)
			box._slot_state = state
			box._apply_overrides(false)
	else:
		var states: PackedStringArray = gdss_node.states
		var first_slot: String = states[0] if not states.is_empty() else ""
		var box: GdssPropHandler = _obtain(canvas_item, control, "", first_slot)
		for state: String in states:
			if control.get_theme_stylebox(state) != box:
				control.add_theme_stylebox_override(state, box)
		box._apply_overrides()
	gdss_node.bind_canvas_item(canvas_item)


static func _obtain(canvas_item: CanvasItem, control: Control, state: String, slot: String) -> GdssPropHandler:
	var key: String = _key(canvas_item, state)
	var box: GdssPropHandler = _registry.get(key)
	if box == null and not slot.is_empty():
		var existing: StyleBox = control.get_theme_stylebox(slot) if control.has_theme_stylebox_override(slot) else null
		if existing is GdssPropHandler:
			box = existing as GdssPropHandler
	if box == null:
		box = GdssPropHandler.new()
	_registry[key] = box
	box.ref = canvas_item
	if not slot.is_empty() and control.get_theme_stylebox(slot) != box:
		control.add_theme_stylebox_override(slot, box)
	_connect_editor(box)
	return box


static func _connect_editor(box: GdssPropHandler) -> void:
	if not Engine.is_editor_hint():
		return
	var interp: GdssInterpreter = GdssInterpreter.get_instance()
	if is_instance_valid(interp) and not interp.parsed_changed.is_connected(box._on_parsed_changed):
		interp.parsed_changed.connect(box._on_parsed_changed)


static func unbind(canvas_item: CanvasItem) -> void:
	var gdss_node: GdssNode = GDSS._get_gdss_nodes().get(canvas_item.get_class())
	if gdss_node == null:
		printerr("Could not unbind %s of type \"%s\"" % [canvas_item, canvas_item.get_class()])
		return
	var control: Control = canvas_item as Control
	if control == null:
		return
	_clear_overrides_for(control, gdss_node)
	var interp: GdssInterpreter = GdssInterpreter.get_instance() if Engine.is_editor_hint() else null
	for state: String in gdss_node.states:
		var box: GdssPropHandler = _registry.get(_key(canvas_item, state))
		if box != null and is_instance_valid(interp) and interp.parsed_changed.is_connected(box._on_parsed_changed):
			interp.parsed_changed.disconnect(box._on_parsed_changed)
		control.remove_theme_stylebox_override(state)
		_registry.erase(_key(canvas_item, state))
	var single: GdssPropHandler = _registry.get(_key(canvas_item))
	if single != null and is_instance_valid(interp) and interp.parsed_changed.is_connected(single._on_parsed_changed):
		interp.parsed_changed.disconnect(single._on_parsed_changed)
	_registry.erase(_key(canvas_item))
	gdss_node.unbind_canvas_item(canvas_item)
	GDSS.clear_instance_vars(canvas_item)
	if Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() != null:
		EditorInterface.mark_scene_as_unsaved()


static func _clear_overrides_for(control: Control, gdss_node: GdssNode) -> void:
	for prop: GdssProp in gdss_node.get_enabled_props():
		match prop.category:
			GdssProp.Category.COLOR:
				if prop.category_subproperties.is_empty():
					control.remove_theme_color_override(prop.name)
				else:
					if gdss_node.colors.has(prop.name):
						control.remove_theme_color_override(prop.name)
					for subprop: String in prop.category_subproperties:
						if gdss_node.colors.has(subprop):
							control.remove_theme_color_override(subprop)
			GdssProp.Category.CONST:
				control.remove_theme_constant_override(prop.name)
			GdssProp.Category.FONT_SIZE:
				control.remove_theme_font_size_override(prop.name)
			GdssProp.Category.FONT:
				control.remove_theme_font_override(prop.name)
			GdssProp.Category.ICON:
				control.remove_theme_icon_override(prop.name)
