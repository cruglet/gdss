@tool
class_name GdssEditor
extends Control

static var _code_editor_ref: CodeEdit

@export var style_objects: Array[GdssNode]

@export_group("refs")
@export var code_edit: CodeEdit
@export var top_menu_bar: MenuBar
@export var error_label: Label


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_code_editor_ref = code_edit
	
	error_label.add_theme_font_override(&"font", EditorInterface.get_editor_theme().get_font(&"expression", &"EditorFonts"))
	error_label.add_theme_color_override(&"font_color", EditorInterface.get_editor_theme().get_color(&"error_color", &"Editor"))


static func get_code_editor() -> CodeEdit:
	return _code_editor_ref
