@tool
class_name GdssEditor
extends Control

static var _code_editor_ref: CodeEdit

@export_group("refs")
@export var code_edit: CodeEdit
@export var error_label: Label
@export var title_label: Label

var _has_unsaved_changes: bool = false
var _current_file_path: String = ""

var file_name: String:
	get():
		return GdssStorage.get_save_path().get_file()


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_code_editor_ref = code_edit

	error_label.add_theme_font_override(&"font", EditorInterface.get_editor_theme().get_font(&"expression", &"EditorFonts"))
	error_label.add_theme_color_override(&"font_color", EditorInterface.get_editor_theme().get_color(&"error_color", &"Editor"))
	
	title_label.text = file_name
	code_edit.gui_input.connect(_on_code_edit_input)


func _on_code_edit_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.keycode == KEY_S and key.is_command_or_control_pressed():
		EditorInterface.save_scene()
		GdssInterpreter.get_instance().save_current()
		code_edit.get_viewport().set_input_as_handled()


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
