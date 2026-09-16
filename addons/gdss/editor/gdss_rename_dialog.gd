@tool
class_name GdssRenameDialog
extends ConfirmationDialog

const CONTENT_WIDTH: float = 420.0

var _editor: GdssEditor
var _index: GdssSymbols.Index
var _symbol: GdssSymbols.Symbol
var _field: LineEdit
var _status: Label
var _scopes: VBoxContainer
var _scene_refs: Dictionary = {}
var _checks: Dictionary = {}
var _script_refs: Array[GdssSymbols.Ref] = []


func _init() -> void:
	title = "Rename Symbol"
	ok_button_text = "Rename"
	var root: VBoxContainer = VBoxContainer.new()
	root.custom_minimum_size = Vector2(CONTENT_WIDTH, 0)
	_field = LineEdit.new()
	_field.placeholder_text = "new name"
	_field.text_changed.connect(_validate)
	root.add_child(_field)
	_status = Label.new()
	_status.clip_text = true
	_status.add_theme_color_override(&"font_color", EditorInterface.get_editor_theme().get_color(&"error_color", &"Editor"))
	root.add_child(_status)
	_scopes = VBoxContainer.new()
	root.add_child(_scopes)
	add_child(root)
	register_text_enter(_field)
	add_button("Show References", true, "references")
	confirmed.connect(_on_confirmed)
	confirmed.connect(queue_free)
	canceled.connect(queue_free)
	custom_action.connect(_on_custom_action)


func open_for(editor: GdssEditor, index: GdssSymbols.Index, symbol: GdssSymbols.Symbol) -> void:
	_editor = editor
	_index = index
	_symbol = symbol
	title = "Rename %s" % symbol.label()
	_scene_refs = _group_by_file(GdssSymbols.scan_scenes(symbol))
	_script_refs = GdssSymbols.scan_scripts(symbol)
	_build_scopes()
	_status.custom_minimum_size = Vector2(CONTENT_WIDTH, _status.get_line_height())
	_field.text = symbol.name
	_validate(symbol.name)
	popup_centered()
	_field.grab_focus()
	_field.select_all()


func _group_by_file(refs: Array[GdssSymbols.Ref]) -> Dictionary:
	var grouped: Dictionary = {}
	for entry: GdssSymbols.Ref in refs:
		var bucket: Array[GdssSymbols.Ref] = grouped.get(entry.file, [] as Array[GdssSymbols.Ref])
		bucket.append(entry)
		grouped.set(entry.file, bucket)
	return grouped


func _build_scopes() -> void:
	for child: Node in _scopes.get_children():
		child.queue_free()
	_checks.clear()
	if _scene_refs.is_empty():
		return
	var scenes_label: Label = Label.new()
	scenes_label.text = "Also update:"
	_scopes.add_child(scenes_label)
	for path: String in _scene_refs:
		var count: int = (_scene_refs.get(path) as Array).size()
		var state: String = _editor.scene_state(path)
		var check: CheckBox = CheckBox.new()
		check.text = "%s  (%d)" % [path.get_file(), count]
		check.button_pressed = state != "open"
		check.tooltip_text = path
		if state == "open":
			check.disabled = true
			check.tooltip_text = "%s\nOpen in another tab — save and close it to include it." % path
		elif state == "current":
			check.tooltip_text = "%s\nCurrent scene — this change is undoable." % path
		_scopes.add_child(check)
		_checks.set(path, check)


func _validate(new_name: String) -> void:
	var error: String = GdssSymbols.validate(_index, _symbol, new_name.strip_edges())
	_status.text = error
	_status.tooltip_text = error
	get_ok_button().disabled = not error.is_empty()


func _on_confirmed() -> void:
	var new_name: String = _field.text.strip_edges()
	if not GdssSymbols.validate(_index, _symbol, new_name).is_empty():
		return
	var approved: Array[GdssSymbols.Ref] = []
	for path: String in _scene_refs:
		var check: CheckBox = _checks.get(path)
		if check != null and check.button_pressed and not check.disabled:
			approved.append_array(_scene_refs.get(path))
	_editor.rename_symbol(_symbol, new_name, approved)


func _on_custom_action(action: StringName) -> void:
	if action != &"references":
		return
	var extra: Array[GdssSymbols.Ref] = _group_values(_scene_refs)
	extra.append_array(_script_refs)
	_editor.show_references(_symbol, extra)
	hide()
	queue_free()


func _group_values(grouped: Dictionary) -> Array[GdssSymbols.Ref]:
	var result: Array[GdssSymbols.Ref] = []
	for path: String in grouped:
		result.append_array(grouped.get(path))
	return result
