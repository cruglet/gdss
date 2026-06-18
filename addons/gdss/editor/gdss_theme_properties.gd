@tool
class_name GdssThemePropertiesDialog
extends ConfirmationDialog

const FIELDS: Array[String] = ["name", "description", "author", "version"]

var _editor: GdssEditor
var _inputs: Dictionary[String, LineEdit] = {}
var _scheme_option: OptionButton
var _schemes_label: Label


func _init() -> void:
	title = "Theme Properties"
	ok_button_text = "Save"
	min_size = Vector2i(440, 0)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 8)
	add_child(vbox)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(grid)
	for field: String in FIELDS:
		var label: Label = Label.new()
		label.text = field.capitalize()
		grid.add_child(label)
		var line: LineEdit = LineEdit.new()
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(line)
		_inputs[field] = line
	var ds_label: Label = Label.new()
	ds_label.text = "Default Scheme"
	grid.add_child(ds_label)
	_scheme_option = OptionButton.new()
	_scheme_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_scheme_option)
	_schemes_label = Label.new()
	_schemes_label.modulate = Color(1, 1, 1, 0.6)
	_schemes_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_schemes_label.clip_text = true
	vbox.add_child(_schemes_label)
	confirmed.connect(_on_confirmed)


func open_for(editor: GdssEditor) -> void:
	_editor = editor
	for field: String in FIELDS:
		_inputs[field].text = str(GdssInterpreter.meta.get(field, ""))
	var schemes: PackedStringArray = GDSS.get_schemes()
	var current: String = GDSS.get_default_scheme()
	_scheme_option.clear()
	_scheme_option.add_item("(none)")
	_scheme_option.set_item_metadata(0, "")
	for i: int in schemes.size():
		_scheme_option.add_item(schemes[i])
		_scheme_option.set_item_metadata(i + 1, schemes[i])
		if schemes[i] == current:
			_scheme_option.select(i + 1)
	if not current.is_empty() and not schemes.has(current):
		_scheme_option.add_item("%s (missing)" % current)
		var missing_index: int = _scheme_option.item_count - 1
		_scheme_option.set_item_metadata(missing_index, current)
		_scheme_option.select(missing_index)
	_schemes_label.text = "Declared schemes: " + (", ".join(schemes) if not schemes.is_empty() else "(none)")
	reset_size()
	popup_centered()
	_inputs["name"].grab_focus()


func _on_confirmed() -> void:
	if _editor == null:
		return
	var meta: Dictionary = GdssInterpreter.meta.duplicate(true)
	for field: String in FIELDS:
		var value: String = _inputs[field].text.strip_edges().replace("\n", " ")
		if value.is_empty():
			meta.erase(field)
		else:
			meta[field] = value
	var default_scheme: String = str(_scheme_option.get_item_metadata(_scheme_option.selected))
	if default_scheme.is_empty():
		meta.erase("default_scheme")
	else:
		meta["default_scheme"] = default_scheme
	_editor.upsert_meta_block(_build_block(meta))


func _build_block(meta: Dictionary) -> String:
	var lines: PackedStringArray = ["@meta {"]
	for key: String in meta:
		var value: String = str(meta[key]).strip_edges()
		if value.is_empty():
			continue
		if key == "default_scheme":
			lines.append("\t%s: %s" % [key, value])
		else:
			lines.append("\t%s: \"%s\"" % [key, value.replace("\"", "")])
	lines.append("}")
	return "\n".join(lines)
