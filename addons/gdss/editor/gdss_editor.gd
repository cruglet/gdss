@tool
class_name GdssEditor
extends Node

static var _code_editor_ref: CodeEdit

@export_group("refs")
@export var code_edit: CodeEdit
@export var error_label: Label
@export var title_label: Label
@export var copy_button: Button
@export var toggle_map_button: Button

var err_line_num: int

var _has_unsaved_changes: bool = false
var _current_file_path: String = ""

var file_name: String:
	get():
		return GdssStorage.get_save_path().get_file()


func _ready() -> void:
	if not is_running_as_plugin():
		set_process(false)
		return
	
	name = "GDSS"
	_code_editor_ref = code_edit
	
	if not is_running_as_plugin():
		return
	
	error_label.add_theme_font_override(&"font", EditorInterface.get_editor_theme().get_font(&"expression", &"EditorFonts"))
	error_label.add_theme_color_override(&"font_color", EditorInterface.get_editor_theme().get_color(&"error_color", &"Editor"))
	error_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	error_label.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton:
			if e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				code_edit.set_caret_line(err_line_num)
	)
	
	copy_button.icon = EditorInterface.get_editor_theme().get_icon(&"ActionCopy", &"EditorIcons")
	
	if not ProjectSettings.has_setting("gdss/editor/use_minimap"):
		ProjectSettings.set_setting("gdss/editor/use_minimap", true)
	
	toggle_map_button.button_pressed = ProjectSettings.get_setting("gdss/editor/use_minimap")
	
	title_label.text = file_name
	code_edit.gui_input.connect(_on_code_edit_input)
	_update_editor()


func get_code_edit() -> CodeEdit:
	return code_edit


func show_error(message: String, line_num: int) -> void:
	if line_num == -1:
		error_label.text = ""
		error_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		copy_button.disabled = true
		return
	
	error_label.text = "[%s]: %s" % [line_num, message]
	err_line_num = line_num
	error_label.mouse_filter = Control.MOUSE_FILTER_STOP
	copy_button.disabled = false


func _on_code_edit_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.keycode == KEY_S and key.is_command_or_control_pressed():
		EditorInterface.save_scene()
		GdssInterpreter.get_instance().save_current()
		code_edit.get_viewport().set_input_as_handled()
	if key.keycode == KEY_I and key.is_command_or_control_pressed() and key.shift_pressed:
		_convert_spaces_to_tabs()
		code_edit.get_viewport().set_input_as_handled()


func _convert_spaces_to_tabs() -> void:
	var lines: PackedStringArray = code_edit.text.split("\n")
	for i: int in lines.size():
		var line: String = lines[i]
		var tab_count: int = 0
		while line.begins_with("    "):
			line = line.substr(4)
			tab_count += 1
		lines[i] = "\t".repeat(tab_count) + line
	var caret_line: int = code_edit.get_caret_line()
	var caret_col: int = code_edit.get_caret_column()
	code_edit.text = "\n".join(lines)
	code_edit.set_caret_line(caret_line)
	code_edit.set_caret_column(caret_col)


static func get_code_editor() -> CodeEdit:
	return _code_editor_ref


func load_file(path: String) -> void:
	var data: Dictionary = GdssStorage.load_data(path)
	if data.is_empty():
		return
	_current_file_path = path
	if data.has("source"):
		code_edit.text = data["source"]
	_user_saved()


func _prompt_save() -> void:
	if _has_unsaved_changes:
		return
	_has_unsaved_changes = true
	title_label.text = file_name + "(*)"


func _user_saved() -> void:
	_has_unsaved_changes = false
	title_label.text = file_name


func get_current_file_path() -> String:
	return _current_file_path if not _current_file_path.is_empty() else GdssStorage.get_save_path()


func has_unsaved_changes() -> bool:
	return _has_unsaved_changes


func _on_copy_button_pressed() -> void:
	DisplayServer.clipboard_set(error_label.text)


func is_running_as_plugin() -> bool:
	return get_parent() is EditorDock


func _on_toggle_map_button_toggled(toggled_on: bool) -> void:
	ProjectSettings.set_setting("gdss/editor/use_minimap", toggled_on)
	_update_editor()


func _update_editor() -> void:
	code_edit.minimap_draw = ProjectSettings.get_setting("gdss/editor/use_minimap")


func _on_doc_button_pressed() -> void:
	EditorInterface.get_script_editor().goto_help("class_name:GDSSDocumentation")
