@tool
class_name GdssResourcePanel
extends PanelContainer

const BASE_TYPES: Dictionary = {
	"font": "Font",
	"texture": "Texture2D",
	"sound": "AudioStream",
}

var editor: GdssEditor

var _tabs: TabBar
var _filter_field: LineEdit
var _rows: VBoxContainer
var _empty: Label
var _pending: Dictionary = {}
var _focus_key: String = ""
var _filter: String = ""
var _rebuilding: bool = false


func _init() -> void:
	visible = false
	custom_minimum_size = Vector2(250, 0)
	add_theme_stylebox_override(&"panel", GdssEditor.editor_panel_stylebox())
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 4)
	margin.add_theme_constant_override(&"margin_right", 4)
	margin.add_theme_constant_override(&"margin_top", 4)
	margin.add_theme_constant_override(&"margin_bottom", 4)
	add_child(margin)
	var root: VBoxContainer = VBoxContainer.new()
	margin.add_child(root)
	var header: HBoxContainer = HBoxContainer.new()
	_filter_field = LineEdit.new()
	_filter_field.placeholder_text = "Filter resources…"
	_filter_field.clear_button_enabled = true
	_filter_field.size_flags_horizontal = SIZE_EXPAND_FILL
	_filter_field.right_icon = _icon(&"Search")
	_filter_field.text_changed.connect(_on_filter_changed)
	header.add_child(_filter_field)
	var add_button: Button = Button.new()
	add_button.theme_type_variation = &"FlatButton"
	add_button.tooltip_text = "Add a resource"
	_apply_icon(add_button, &"Add")
	if add_button.icon == null:
		add_button.text = "+"
	add_button.pressed.connect(add_resource)
	header.add_child(add_button)
	root.add_child(header)
	_tabs = TabBar.new()
	_tabs.add_tab("All")
	for name: String in GdssStylesheet.resource_methods():
		_tabs.add_tab(name)
	_tabs.tab_changed.connect(_on_tab_changed)
	root.add_child(_tabs)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	root.add_child(scroll)
	_empty = Label.new()
	_empty.text = "No resources yet. Add one to reference it as $KEY."
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.custom_minimum_size = Vector2(220, 0)
	_empty.modulate = Color(1, 1, 1, 0.6)
	_rows.add_child(_empty)


func refresh() -> void:
	if editor == null:
		return
	_rebuilding = true
	var entries: Array[Dictionary] = editor.resource_entries()
	for child: Node in _rows.get_children():
		if child != _empty:
			_rows.remove_child(child)
			child.queue_free()
	var shown: int = 0
	for entry: Dictionary in entries:
		if not _in_view(entry):
			continue
		_rows.add_child(_make_row(entry))
		shown += 1
	if not _pending.is_empty():
		_rows.add_child(_make_row(_pending))
		shown += 1
	_empty.text = "No resources yet. Add one to reference it as $KEY." if entries.is_empty() else "Nothing matches this filter."
	_empty.visible = shown == 0
	_rebuilding = false
	if not _focus_key.is_empty():
		_focus_row.call_deferred(_focus_key)
		_focus_key = ""


func _on_filter_changed(text: String) -> void:
	_filter = text.strip_edges().to_lower()
	refresh()


func _on_tab_changed(_index: int) -> void:
	_pending = {}
	refresh()


func _tab_method() -> String:
	return "" if _tabs.current_tab <= 0 else _tabs.get_tab_title(_tabs.current_tab)


func _in_view(entry: Dictionary) -> bool:
	var method: String = _tab_method()
	if not method.is_empty() and entry.get("method") != method:
		return false
	if _filter.is_empty():
		return true
	return str(entry.get("key")).to_lower().contains(_filter) or str(entry.get("path")).to_lower().contains(_filter)


func add_resource() -> void:
	var methods: PackedStringArray = GdssStylesheet.resource_methods()
	if methods.is_empty():
		return
	_filter = ""
	_filter_field.text = ""
	_pending = {
		"key": _unique_key("NEW_RESOURCE"),
		"method": _tab_method(),
		"path": "",
		"pending": true,
		"custom": false,
	}
	_focus_key = _pending.get("key")
	refresh()


func _make_row(entry: Dictionary) -> Control:
	var key: String = entry.get("key")
	var method: String = entry.get("method")
	var path: String = entry.get("path")
	var pending: bool = entry.get("pending", false)
	var row: VBoxContainer = VBoxContainer.new()
	row.size_flags_horizontal = SIZE_EXPAND_FILL
	row.name = "row_%s" % key
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 0)
	var sigil: Label = Label.new()
	sigil.text = "$"
	sigil.add_theme_color_override(&"font_color", _method_color())
	top.add_child(sigil)
	var key_field: LineEdit = LineEdit.new()
	key_field.text = key
	key_field.size_flags_horizontal = SIZE_EXPAND_FILL
	key_field.tooltip_text = "Reference this resource as $%s" % key
	key_field.text_submitted.connect(func(value: String) -> void: _commit_key(entry, value))
	key_field.focus_exited.connect(func() -> void: _commit_key(entry, key_field.text))
	top.add_child(key_field)
	if not pending and not path.is_empty() and not ResourceLoader.exists(path):
		var warning: TextureRect = TextureRect.new()
		warning.texture = _icon(&"NodeWarning")
		warning.tooltip_text = "%s does not exist" % path
		warning.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		top.add_child(warning)
	var remove: Button = Button.new()
	remove.theme_type_variation = &"FlatButton"
	remove.tooltip_text = "Discard this row" if pending else "Remove this resource"
	_apply_icon(remove, &"Remove")
	if remove.icon == null:
		remove.text = "X"
	remove.pressed.connect(func() -> void: _remove(entry))
	top.add_child(remove)
	row.add_child(top)
	row.add_child(_make_picker(entry, method, path))
	row.add_child(HSeparator.new())
	return row


func _make_picker(entry: Dictionary, method: String, path: String) -> Control:
	var picker: EditorResourcePicker = EditorResourcePicker.new()
	picker.size_flags_horizontal = SIZE_EXPAND_FILL
	picker.base_type = _base_type(method)
	if not path.is_empty() and ResourceLoader.exists(path):
		picker.edited_resource = load(path)
	picker.resource_changed.connect(func(resource: Resource) -> void: _on_picked(entry, resource))
	return picker


func _base_type(method: String) -> String:
	if not method.is_empty():
		return BASE_TYPES.get(method, "Resource")
	var types: PackedStringArray = []
	for name: String in GdssStylesheet.resource_methods():
		var base: String = BASE_TYPES.get(name, "")
		if not base.is_empty() and not types.has(base):
			types.append(base)
	return ",".join(types) if not types.is_empty() else "Resource"


func _commit_key(entry: Dictionary, new_key: String) -> void:
	if _rebuilding:
		return
	var trimmed: String = new_key.strip_edges()
	if trimmed.is_empty() or trimmed == entry.get("key"):
		return
	if entry.get("pending", false):
		_pending.set("key", trimmed)
		_pending.set("custom", true)
		_focus_key = trimmed
		refresh()
		return
	editor.rename_resource(entry.get("key"), trimmed)


func _remove(entry: Dictionary) -> void:
	if _rebuilding:
		return
	if entry.get("pending", false):
		_pending = {}
		refresh()
		return
	editor.remove_resource(entry.get("key"))


func _on_picked(entry: Dictionary, resource: Resource) -> void:
	if _rebuilding or resource == null:
		return
	var path: String = resource.resource_path
	if path.is_empty():
		editor.flash_warning("That resource has no file of its own to point at")
		refresh()
		return
	var method: String = _loader_for(path, entry.get("method"))
	if method.is_empty():
		editor.flash_warning("No GDSS loader can read %s" % path.get_file())
		refresh()
		return
	var pending: bool = entry.get("pending", false)
	var key: String = entry.get("key")
	if pending and not entry.get("custom", false):
		key = _unique_key(_key_from_path(path))
	_pending = {}
	_focus_key = key
	editor.write_resource("" if pending else entry.get("key"), key, method, path)


func _loader_for(path: String, preferred: String) -> String:
	var names: PackedStringArray = GdssStylesheet.resource_methods()
	if not preferred.is_empty() and names.has(preferred) and _loads(path, preferred):
		return preferred
	for name: String in names:
		if _loads(path, name):
			return name
	return ""


func _loads(path: String, method_name: String) -> bool:
	var method: GdssMethod = GDSS._get_gdss_methods().get(method_name)
	if method == null:
		return false
	var args: Array[Variant] = [path]
	return method.call_method(args) != null


func _key_from_path(path: String) -> String:
	var base: String = path.get_file().get_basename().to_upper()
	var cleaned: String = ""
	for i: int in base.length():
		var c: String = base[i]
		cleaned += c if (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_" else "_"
	return cleaned if cleaned.is_valid_identifier() else "RESOURCE_%s" % cleaned


func _unique_key(base: String) -> String:
	var taken: PackedStringArray = []
	for entry: Dictionary in editor.resource_entries():
		taken.append(entry.get("key"))
	var candidate: String = base
	var suffix: int = 2
	while taken.has(candidate):
		candidate = "%s_%d" % [base, suffix]
		suffix += 1
	return candidate


func _focus_row(key: String) -> void:
	var row: Node = _rows.get_node_or_null("row_%s" % key)
	if row == null:
		return
	var field: LineEdit = row.get_child(0).get_child(1) as LineEdit
	if field != null:
		field.grab_focus()
		field.select_all()


func _method_color() -> Color:
	var raw: Variant = EditorInterface.get_editor_settings().get_setting("text_editor/theme/highlighting/gdscript/global_function_color")
	return raw if raw is Color else EditorInterface.get_editor_theme().get_color(&"accent_color", &"Editor")


func _apply_icon(button: Button, icon_name: StringName) -> void:
	var icon: Texture2D = _icon(icon_name)
	if icon != null:
		button.icon = icon


func _icon(icon_name: StringName) -> Texture2D:
	var theme: Theme = EditorInterface.get_editor_theme()
	if theme.has_icon(icon_name, &"EditorIcons"):
		return theme.get_icon(icon_name, &"EditorIcons")
	return null
