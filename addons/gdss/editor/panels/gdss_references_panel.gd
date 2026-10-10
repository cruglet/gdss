@tool
class_name GdssReferencesPanel
extends VBoxContainer

signal jump_requested(file: String, line: int, column: int)
signal close_requested

var editor: GdssEditor

var _title: Label
var _tree: Tree


func _init() -> void:
	visible = false
	var header: HBoxContainer = HBoxContainer.new()
	_title = Label.new()
	_title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(_title)
	var close_button: Button = Button.new()
	close_button.theme_type_variation = &"FlatButton"
	close_button.tooltip_text = "Close"
	close_button.focus_mode = Control.FOCUS_NONE
	var close_icon: Texture2D = _icon(&"Close")
	if close_icon != null:
		close_button.icon = close_icon
	else:
		close_button.text = "X"
	close_button.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(close_button)
	add_child(header)
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.allow_rmb_select = false
	_tree.size_flags_vertical = SIZE_EXPAND_FILL
	_tree.item_selected.connect(_on_item_selected)
	add_child(_tree)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		accept_event()
		close_requested.emit()


func show_references(symbol: GdssSymbols.Symbol, refs: Array[GdssSymbols.Ref]) -> void:
	_title.text = "%d reference%s to %s" % [refs.size(), "" if refs.size() == 1 else "s", symbol.label()]
	_tree.clear()
	var root: TreeItem = _tree.create_item()
	var groups: Dictionary = {}
	for entry: GdssSymbols.Ref in refs:
		var group: TreeItem = groups.get(entry.file)
		if group == null:
			group = _tree.create_item(root)
			group.set_text(0, editor.describe_file(entry.file))
			group.set_selectable(0, false)
			group.set_custom_color(0, _accent())
			groups.set(entry.file, group)
		var item: TreeItem = _tree.create_item(group)
		var suffix: String = "" if entry.is_editable() else "   (left as-is)"
		item.set_text(0, "%s   %s%s" % [editor.describe_location(entry.file, entry.line), entry.text.strip_edges(), suffix])
		item.set_metadata(0, {"file": entry.file, "line": entry.line, "column": entry.from})
		item.set_icon(0, _ref_icon(entry))
		if entry.declaration:
			item.set_custom_color(0, _accent())


func show_diagnostics(items: Array[Dictionary]) -> void:
	_title.text = "No problems found" if items.is_empty() else "%d problem%s" % [items.size(), "" if items.size() == 1 else "s"]
	_tree.clear()
	var root: TreeItem = _tree.create_item()
	var warning_icon: Texture2D = _icon(&"NodeWarning")
	for diagnostic: Dictionary in items:
		var item: TreeItem = _tree.create_item(root)
		var file: String = diagnostic.get("file")
		var line: int = diagnostic.get("line")
		item.set_text(0, "%s   %s" % [editor.describe_location(file, line), diagnostic.get("message")])
		item.set_metadata(0, {"file": file, "line": line, "column": 0})
		item.set_icon(0, warning_icon)


func _ref_icon(entry: GdssSymbols.Ref) -> Texture2D:
	match entry.file.get_extension().to_lower():
		"tscn":
			return _icon(&"PackedScene")
		"gd":
			return _icon(&"Script")
		"tgdss":
			return _icon(&"Load")
	return _icon(GdssSymbols.KIND_ICONS.get(entry.kind))


func _on_item_selected() -> void:
	var item: TreeItem = _tree.get_selected()
	if item == null:
		return
	var data: Dictionary = item.get_metadata(0)
	if data.is_empty():
		return
	jump_requested.emit(data.get("file"), data.get("line"), data.get("column"))


func _accent() -> Color:
	return EditorInterface.get_editor_theme().get_color(&"accent_color", &"Editor")


func _icon(icon_name: StringName) -> Texture2D:
	var theme: Theme = EditorInterface.get_editor_theme()
	if theme.has_icon(icon_name, &"EditorIcons"):
		return theme.get_icon(icon_name, &"EditorIcons")
	return null
