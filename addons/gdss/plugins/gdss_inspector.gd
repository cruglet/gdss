@tool
class_name GdssInspectorPlugin
extends EditorInspectorPlugin


class GdssEnabledProperty extends EditorProperty:
	var checkbox: CheckBox
	var _updating: bool = false

	func _init() -> void:
		checkbox = CheckBox.new()
		checkbox.text = "On"
		add_child(checkbox)
		add_focusable(checkbox)
		checkbox.toggled.connect(_on_toggled)

	func _update_property() -> void:
		_updating = true
		checkbox.set_pressed_no_signal(get_edited_object().get_meta("gdss_enabled", false))
		_updating = false

	func _on_toggled(value: bool) -> void:
		if _updating:
			return
		var obj: Object = get_edited_object()
		var undo_redo: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
		undo_redo.create_action("Toggle GDSS Enabled")
		undo_redo.add_do_method(obj, &"set_meta", &"gdss_enabled", value)
		undo_redo.add_undo_method(obj, &"set_meta", &"gdss_enabled", not value)
		undo_redo.add_do_method(GdssNodeHandler, &"bind" if value else &"unbind", obj)
		undo_redo.add_undo_method(GdssNodeHandler, &"unbind" if value else &"bind", obj)
		undo_redo.add_do_method(obj, &"notify_property_list_changed")
		undo_redo.add_undo_method(obj, &"notify_property_list_changed")
		undo_redo.commit_action()

	func _set_enabled(obj: Object, value: bool) -> void:
		obj.set_meta("gdss_enabled", value)
		if value:
			GdssNodeHandler.bind(obj as CanvasItem)
		else:
			GdssNodeHandler.unbind(obj as CanvasItem)
		emit_changed("gdss_enabled", value)
		obj.call_deferred(&"notify_property_list_changed")


class GdssClassesProperty extends EditorProperty:
	var edit: LineEdit
	var _updating: bool = false

	func _init() -> void:
		edit = LineEdit.new()
		add_child(edit)
		add_focusable(edit)
		edit.text_submitted.connect(_on_submitted)

	func _update_property() -> void:
		_updating = true
		var obj: Object = get_edited_object()
		var arr: PackedStringArray = obj.get_meta("gdss_classes", PackedStringArray())
		edit.text = " ".join(arr)
		_updating = false

	func _on_submitted(text: String) -> void:
		if _updating:
			return
		var obj: Object = get_edited_object()
		var old_val: PackedStringArray = obj.get_meta("gdss_classes", PackedStringArray())
		var new_val: PackedStringArray = PackedStringArray(text.split(" ", false))
		if new_val == old_val:
			return
		var undo_redo: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
		undo_redo.create_action("Set GDSS Classes")
		undo_redo.add_do_method(self, &"_set_classes", obj, new_val)
		undo_redo.add_undo_method(self, &"_set_classes", obj, old_val)
		undo_redo.commit_action()

	func _set_classes(obj: Object, value: PackedStringArray) -> void:
		obj.set_meta("gdss_classes", value)
		if obj is CanvasItem:
			var canvas_item: CanvasItem = obj as CanvasItem
			var gdss_node: GdssNode = GDSS._get_gdss_nodes().get(obj.get_class())
			if gdss_node != null and gdss_node.is_static:
				for state: String in gdss_node.states:
					if canvas_item.has_meta("gdss_handler_" + state):
						var box: GdssPropHandler = GdssNodeHandler.get_handler(canvas_item, state)
						if box == null:
							continue
						box._apply_overrides()
						box.emit_changed()
			elif canvas_item.has_meta(&"gdss_handler"):
				var box: GdssPropHandler = GdssNodeHandler.get_handler(canvas_item)
				if box != null:
					box._apply_overrides()
					box.emit_changed()
			canvas_item.queue_redraw()


func _can_handle(object: Object) -> bool:
	return object is Control


func _parse_property(object: Object, type: Variant.Type, name: String, hint_type: PropertyHint, hint_string: String, usage_flags: int, wide: bool) -> bool:
	var is_enabled: bool = object.get_meta("gdss_enabled", false)

	if name == "theme":
		var enabled_prop: GdssEnabledProperty = GdssEnabledProperty.new()
		enabled_prop.set_label("Use GDSS")
		add_custom_control(enabled_prop)

		if is_enabled:
			var classes_prop: GdssClassesProperty = GdssClassesProperty.new()
			classes_prop.set_label("Classes")
			add_custom_control(classes_prop)
			return true

	if is_enabled:
		if name == "theme_type_variation":
			return true
		if name.begins_with("theme_override") and not GDSS.DEBUG_MODE:
			return true

	return false
