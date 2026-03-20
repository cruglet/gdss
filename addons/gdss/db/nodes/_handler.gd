@tool
class_name GdssNodeHandler
extends Object

static var _registry: Dictionary = {}


static func _key(canvas_item: CanvasItem, state: String = "") -> String:
	return "%d:%s" % [canvas_item.get_instance_id(), state]


static func get_handler(canvas_item: CanvasItem, state: String = "") -> GdssPropHandler:
	return _registry.get(_key(canvas_item, state))


static func bind(canvas_item: CanvasItem) -> void:
	var gdss_node: GdssNode = GDSS._get_gdss_nodes().get(canvas_item.get_class())
	if gdss_node == null:
		return
	var control: Control = canvas_item as Control
	if control == null:
		return
	if gdss_node.is_static:
		for state: String in gdss_node.states:
			var k: String = _key(canvas_item, state)
			var box: GdssPropHandler = _registry.get(k)
			if box == null:
				box = GdssPropHandler.new()
				_registry[k] = box
			box._slot_state = state
			box.ref = canvas_item
			canvas_item.set_meta("gdss_handler_" + state, true)
			control.add_theme_stylebox_override(state, box)
			box._apply_overrides(false)
			if Engine.is_editor_hint():
				var interp: GdssInterpreter = GdssInterpreter.get_instance()
				if is_instance_valid(interp) and not interp.parsed_changed.is_connected(box._on_parsed_changed):
					interp.parsed_changed.connect(box._on_parsed_changed)
		gdss_node.bind_canvas_item(canvas_item)
		return
	var k: String = _key(canvas_item)
	var box: GdssPropHandler = _registry.get(k)
	if box == null:
		box = GdssPropHandler.new()
		_registry[k] = box
	box.ref = canvas_item
	canvas_item.set_meta(&"gdss_handler", true)
	for state: String in gdss_node.states:
		control.remove_theme_stylebox_override(state)
		control.add_theme_stylebox_override(state, box)
	box._apply_overrides()
	gdss_node.bind_canvas_item(canvas_item)


static func unbind(canvas_item: CanvasItem) -> void:
	var gdss_node: GdssNode = GDSS._get_gdss_nodes().get(canvas_item.get_class())
	if gdss_node == null:
		printerr("Could not unbind %s of type \"%s\"" % [canvas_item, canvas_item.get_class()])
		return
	var control: Control = canvas_item as Control
	if control == null:
		return
	_clear_overrides_for(control, gdss_node)
	if Engine.is_editor_hint():
		var interp: GdssInterpreter = GdssInterpreter.get_instance()
		for state: String in gdss_node.states:
			var box: GdssPropHandler = _registry.get(_key(canvas_item, state))
			if box != null and is_instance_valid(interp) and interp.parsed_changed.is_connected(box._on_parsed_changed):
				interp.parsed_changed.disconnect(box._on_parsed_changed)
	for state: String in gdss_node.states:
		control.remove_theme_stylebox_override(state)
		var meta_key: StringName = "gdss_handler_" + state
		if canvas_item.has_meta(meta_key):
			canvas_item.remove_meta(meta_key)
		_registry.erase(_key(canvas_item, state))
	if canvas_item.has_meta(&"gdss_handler"):
		canvas_item.remove_meta(&"gdss_handler")
	_registry.erase(_key(canvas_item))
	gdss_node.unbind_canvas_item(canvas_item)
	GDSS.clear_instance_vars(canvas_item)
	if Engine.is_editor_hint():
		var edited_scene: Node = EditorInterface.get_edited_scene_root()
		if edited_scene != null:
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
