@tool
class_name GdssInspectorPlugin
extends EditorInspectorPlugin


class GdssModeProperty extends EditorProperty:
	var _option: OptionButton
	var _updating: bool = false

	func _init() -> void:
		_option = OptionButton.new()
		_option.size_flags_horizontal = SIZE_EXPAND_FILL
		_option.add_item("Inherit", GDSS.GdssMode.INHERIT)
		_option.add_item("Enable", GDSS.GdssMode.ENABLE)
		_option.add_item("Disable", GDSS.GdssMode.DISABLE)
		add_child(_option)
		add_focusable(_option)
		_option.item_selected.connect(_on_selected)

	func _ready() -> void:
		_update_property.call_deferred()

	func _update_property() -> void:
		var obj: Object = get_edited_object()
		if obj == null:
			return
		var node: Node = obj as Node
		_updating = true
		var mode: int = GDSS.GdssMode.INHERIT
		if node.has_meta(GDSS.MODE_META):
			mode = int(node.get_meta(GDSS.MODE_META))
		elif node.is_in_group(GdssNodeHandler.GROUP):
			mode = GDSS.GdssMode.ENABLE
		_option.select(_option.get_item_index(mode))
		_option.tooltip_text = _effective_text(node)
		_updating = false

	func _effective_text(node: Node) -> String:
		var enabled: bool = GDSS.resolve_mode(node)
		return "Effective: %s%s" % ["Enabled" if enabled else "Disabled", _resolve_source(node)]

	func _resolve_source(node: Node) -> String:
		if node.is_in_group(GdssNodeHandler.GROUP) and GDSS.get_gdss_mode(node) == GDSS.GdssMode.INHERIT:
			return ""
		var current: Node = node
		while current != null:
			if current.has_meta(GDSS.MODE_META):
				var mode: int = int(current.get_meta(GDSS.MODE_META))
				if mode == GDSS.GdssMode.ENABLE or mode == GDSS.GdssMode.DISABLE:
					return "" if current == node else "  (from %s)" % current.name
			current = current.get_parent()
		return "  (project default)"

	func _on_selected(index: int) -> void:
		if _updating:
			return
		var obj: Object = get_edited_object()
		if obj == null:
			return
		var node: Node = obj as Node
		var new_mode: int = _option.get_item_id(index)
		var old_mode: int = int(node.get_meta(GDSS.MODE_META)) if node.has_meta(GDSS.MODE_META) else GDSS.GdssMode.INHERIT
		var was_in_group: bool = node.is_in_group(GdssNodeHandler.GROUP)
		var undo_redo: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
		undo_redo.create_action("Set GDSS Mode")
		undo_redo.add_do_method(GdssNodeHandler, &"set_mode_state", node, new_mode, false)
		undo_redo.add_undo_method(GdssNodeHandler, &"set_mode_state", node, old_mode, was_in_group)
		undo_redo.commit_action()


class GdssClassesProperty extends EditorProperty:
	const PAGE_SIZE: int = 10
	const CUSTOM_ID: int = -1

	var _rows: VBoxContainer
	var _pager: HBoxContainer
	var _page_label: Label
	var _empty_label: Label
	var _node_type: String = ""
	var _values: PackedStringArray = []
	var _page: int = 0
	var _updating: bool = false

	func _init() -> void:
		var root: VBoxContainer = VBoxContainer.new()
		root.size_flags_horizontal = SIZE_EXPAND_FILL
		add_child(root)
		_empty_label = Label.new()
		_empty_label.text = "No classes assigned."
		_empty_label.modulate = Color(1, 1, 1, 0.5)
		root.add_child(_empty_label)
		_rows = VBoxContainer.new()
		_rows.size_flags_horizontal = SIZE_EXPAND_FILL
		root.add_child(_rows)
		_pager = HBoxContainer.new()
		var prev_button: Button = Button.new()
		_apply_icon(prev_button, &"Back", "<")
		prev_button.pressed.connect(_change_page.bind(-1))
		_pager.add_child(prev_button)
		_page_label = Label.new()
		_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_page_label.size_flags_horizontal = SIZE_EXPAND_FILL
		_pager.add_child(_page_label)
		var next_button: Button = Button.new()
		_apply_icon(next_button, &"Forward", ">")
		next_button.pressed.connect(_change_page.bind(1))
		_pager.add_child(next_button)
		root.add_child(_pager)
		var add_button: Button = Button.new()
		add_button.text = "Add Class"
		_apply_icon(add_button, &"Add", "")
		add_button.pressed.connect(_on_add)
		root.add_child(add_button)

	func _apply_icon(button: Button, icon_name: StringName, fallback_text: String) -> void:
		if Engine.is_editor_hint():
			var theme: Theme = EditorInterface.get_editor_theme()
			if theme.has_icon(icon_name, &"EditorIcons"):
				button.icon = theme.get_icon(icon_name, &"EditorIcons")
				button.flat = true
				return
		if button.text.is_empty():
			button.text = fallback_text

	func _ready() -> void:
		_sync.call_deferred()

	func _update_property() -> void:
		_sync()

	func _sync() -> void:
		var obj: Object = get_edited_object()
		if obj == null:
			return
		_node_type = (obj as Node).get_class()
		_values = (obj.get_meta(GDSS.CLASSES_META, PackedStringArray()) as PackedStringArray).duplicate()
		_page = clampi(_page, 0, _page_count() - 1)
		_rebuild()

	func _page_count() -> int:
		return maxi(1, ceili(float(_values.size()) / PAGE_SIZE))

	func _rebuild() -> void:
		if not is_inside_tree():
			return
		_updating = true
		var obj: Object = get_edited_object()
		if obj != null:
			_node_type = (obj as Node).get_class()
		for child: Node in _rows.get_children():
			child.queue_free()
		var existing: PackedStringArray = GdssInterpreter.get_class_names(_node_type)
		var start: int = _page * PAGE_SIZE
		var end: int = mini(start + PAGE_SIZE, _values.size())
		for i: int in range(start, end):
			_rows.add_child(_make_row(i, existing))
		var paged: bool = _values.size() > PAGE_SIZE
		_pager.visible = paged
		_empty_label.visible = _values.is_empty()
		if paged:
			_page_label.text = "Page %d / %d" % [_page + 1, _page_count()]
		_updating = false

	func _make_row(index: int, existing: PackedStringArray) -> Control:
		var value: String = _values[index]
		var row: HBoxContainer = HBoxContainer.new()
		row.size_flags_horizontal = SIZE_EXPAND_FILL
		var option: OptionButton = OptionButton.new()
		option.size_flags_horizontal = SIZE_EXPAND_FILL
		var selected: int = -1
		for class_name_entry: String in existing:
			option.add_item(class_name_entry)
			if class_name_entry == value:
				selected = option.item_count - 1
		if option.item_count > 0:
			option.add_separator()
		option.add_item("Custom…")
		option.set_item_id(option.item_count - 1, CUSTOM_ID)
		var is_custom: bool = not value.is_empty() and selected == -1
		var line: LineEdit = LineEdit.new()
		line.placeholder_text = "custom class"
		line.size_flags_horizontal = SIZE_EXPAND_FILL
		line.text = value if is_custom else ""
		line.visible = is_custom
		option.select(option.item_count - 1 if is_custom else selected)
		option.item_selected.connect(_on_option_selected.bind(index, option, line))
		line.text_submitted.connect(func(_submitted: String) -> void: _commit_line(index, option, line))
		line.focus_exited.connect(_commit_line.bind(index, option, line))
		row.add_child(option)
		row.add_child(line)
		var up_button: Button = Button.new()
		_apply_icon(up_button, &"MoveUp", "↑")
		up_button.tooltip_text = "Move up"
		up_button.disabled = index == 0
		up_button.pressed.connect(_move.bind(index, -1))
		row.add_child(up_button)
		var down_button: Button = Button.new()
		_apply_icon(down_button, &"MoveDown", "↓")
		down_button.tooltip_text = "Move down"
		down_button.disabled = index == _values.size() - 1
		down_button.pressed.connect(_move.bind(index, 1))
		row.add_child(down_button)
		var remove_button: Button = Button.new()
		_apply_icon(remove_button, &"Remove", "X")
		remove_button.tooltip_text = "Remove class"
		remove_button.pressed.connect(_on_remove.bind(index))
		row.add_child(remove_button)
		return row

	func _on_option_selected(item_index: int, row_index: int, option: OptionButton, line: LineEdit) -> void:
		if _updating:
			return
		if option.get_item_id(item_index) == CUSTOM_ID:
			line.visible = true
			line.grab_focus()
			return
		line.visible = false
		_set_value(row_index, option.get_item_text(item_index))

	func _commit_line(index: int, option: OptionButton, line: LineEdit) -> void:
		if _updating or not is_instance_valid(option) or not is_instance_valid(line):
			return
		if option.get_selected_id() != CUSTOM_ID:
			return
		_set_value(index, line.text)

	func _set_value(index: int, text: String) -> void:
		if _updating or index < 0 or index >= _values.size():
			return
		var trimmed: String = text.strip_edges()
		if _values[index] == trimmed:
			return
		_values[index] = trimmed
		_commit()

	func _on_add() -> void:
		_values.append("")
		_page = (_values.size() - 1) / PAGE_SIZE
		_commit()
		_rebuild.call_deferred()

	func _on_remove(index: int) -> void:
		if index < 0 or index >= _values.size():
			return
		_values.remove_at(index)
		_commit()
		_rebuild.call_deferred()

	func _move(index: int, delta: int) -> void:
		var target: int = index + delta
		if index < 0 or target < 0 or index >= _values.size() or target >= _values.size():
			return
		var moved: String = _values[index]
		_values[index] = _values[target]
		_values[target] = moved
		_commit()
		_rebuild.call_deferred()

	func _change_page(delta: int) -> void:
		_page = clampi(_page + delta, 0, _page_count() - 1)
		_rebuild()

	func _commit() -> void:
		var obj: Object = get_edited_object()
		if obj == null:
			return
		var old_val: PackedStringArray = obj.get_meta(GDSS.CLASSES_META, PackedStringArray())
		if old_val == _values:
			return
		var undo_redo: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
		undo_redo.create_action("Set GDSS Classes")
		undo_redo.add_do_method(obj, &"set_meta", GDSS.CLASSES_META, _values.duplicate())
		undo_redo.add_undo_method(obj, &"set_meta", GDSS.CLASSES_META, old_val)
		undo_redo.add_do_method(GdssNodeHandler, &"refresh", obj)
		undo_redo.add_undo_method(GdssNodeHandler, &"refresh", obj)
		undo_redo.commit_action()


class GdssPreviewProperty extends EditorProperty:
	var _option: OptionButton

	func _init() -> void:
		_option = OptionButton.new()
		_option.size_flags_horizontal = SIZE_EXPAND_FILL
		_option.tooltip_text = "Force a state to preview it in the editor. Live = follow the real state."
		add_child(_option)
		add_focusable(_option)
		_option.item_selected.connect(_on_selected)

	func _ready() -> void:
		_update_property.call_deferred()

	func _update_property() -> void:
		var obj: Object = get_edited_object()
		if obj == null:
			return
		var gdss_node: GdssNode = GDSS._get_gdss_nodes().get((obj as Node).get_class())
		_option.clear()
		_option.add_item("Live")
		if gdss_node != null:
			for state: String in gdss_node.states:
				_option.add_item(state)
		_option.select(0)

	func _on_selected(index: int) -> void:
		var obj: Object = get_edited_object()
		if obj == null or not obj is CanvasItem:
			return
		var node: CanvasItem = obj as CanvasItem
		if index == 0:
			var gdss_node: GdssNode = GDSS._get_gdss_nodes().get(node.get_class())
			if gdss_node != null:
				gdss_node.update_state(node)
			return
		var state: String = _option.get_item_text(index)
		for handler: GdssPropHandler in GdssNodeHandler.get_handlers(node):
			handler.current_state = state


func _can_handle(object: Object) -> bool:
	return object is Control and GDSS._get_gdss_nodes().has(object.get_class())


func _parse_property(object: Object, type: Variant.Type, name: String, hint_type: PropertyHint, hint_string: String, usage_flags: int, wide: bool) -> bool:
	var is_enabled: bool = GDSS.resolve_mode(object as Node)

	if name == "theme":
		var mode_prop: GdssModeProperty = GdssModeProperty.new()
		mode_prop.set_label("GDSS")
		add_custom_control(mode_prop)
		if is_enabled:
			var classes_prop: GdssClassesProperty = GdssClassesProperty.new()
			classes_prop.set_label("Classes")
			add_custom_control(classes_prop)
			var gdss_node: GdssNode = GDSS._get_gdss_nodes().get((object as Node).get_class())
			if gdss_node != null and not gdss_node.is_static and gdss_node.states.size() > 1:
				var preview_prop: GdssPreviewProperty = GdssPreviewProperty.new()
				preview_prop.set_label("Preview State")
				add_custom_control(preview_prop)
			return true

	if is_enabled:
		# theme_type_variation stays visible: GDSS now targets it via "/Variation { }"
		# selectors, so users need to be able to set it.
		if name.begins_with("theme_override") and not GDSS.DEBUG_MODE:
			return true

	return false
