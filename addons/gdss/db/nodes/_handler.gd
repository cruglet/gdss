@tool
class_name GdssNodeHandler
extends Object


static func bind(canvas_item: CanvasItem) -> void:
	var gdss_node: GdssNode = GDSS._get_gdss_nodes().get(canvas_item.get_class())
	if gdss_node == null:
		return
	var control: Control = canvas_item as Control
	if control == null:
		return
	if gdss_node.is_static:
		for state: String in gdss_node.states:
			var meta_key: StringName = "gdss_handler_" + state
			if not canvas_item.has_meta(meta_key):
				var new_box: GdssPropHandler = GdssPropHandler.new()
				canvas_item.set_meta(meta_key, new_box)
				new_box._slot_state = state
				control.add_theme_stylebox_override(state, new_box)
			var box: GdssPropHandler = canvas_item.get_meta(meta_key) as GdssPropHandler
			box.ref = canvas_item
			box._slot_state = state
			box._apply_overrides()
		gdss_node.bind_canvas_item(canvas_item)
		return
	var box: GdssPropHandler = GdssPropHandler.new()
	canvas_item.set_meta("gdss_handler", box)
	box.ref = canvas_item
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
	for state: String in gdss_node.states:
		control.remove_theme_stylebox_override(state)
		var meta_key: StringName = "gdss_handler_" + state
		if canvas_item.has_meta(meta_key):
			canvas_item.remove_meta(meta_key)
	if canvas_item.has_meta("gdss_handler"):
		canvas_item.remove_meta("gdss_handler")
	gdss_node.unbind_canvas_item(canvas_item)
	GDSS.clear_instance_vars(canvas_item)
	if Engine.is_editor_hint():
		EditorInterface.get_edited_scene_root().get_tree().get_edited_scene_root()
		var edited_scene: Node = EditorInterface.get_edited_scene_root()
		if edited_scene != null:
			EditorInterface.mark_scene_as_unsaved()
