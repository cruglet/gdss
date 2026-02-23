@tool
class_name GDSS
extends EditorPlugin

const DEBUG_MODE: bool = true
const DEBUG_WAS_VISIBLE: StringName = &"gdss_was_visible"

const GdssInspector = preload("uid://bhvd3stvftya8")
const GDSS_EDITOR = preload("uid://c3jluwmuxtokv")

enum Type {
	INT,
	FLOAT,
	COLOR,
	COMPOSITE,
	COMPOSITE4,
	CURSOR,
	TRANS
}

enum CursorType {
	ARROW,
	POINTING,
	IBEAM,
	DISABLED
}

enum TransitionType {
	LINEAR,
	EASE,
	EASE_IN,
	EASE_OUT,
	EASE_IN_OUT
}

var debug_container: Container
var debug_label: Label
var debug_refresh_button: Button
var debug_unhook_button: Button
var gdss_editor: GdssEditor
var inspector_plugin: GdssInspectorPlugin

var theme_hook: Control

var was_in_distraction_free_mode: bool = false


func _enter_tree() -> void:
	gdss_editor = GDSS_EDITOR.instantiate()
	inspector_plugin = GdssInspectorPlugin.new()
	EditorInterface.get_editor_main_screen().add_child(gdss_editor)
	
	_make_visible(false)
		
	if DEBUG_MODE:
		_debug_hook()
	
	add_inspector_plugin(inspector_plugin)


func _exit_tree() -> void:
	if gdss_editor:
		gdss_editor.queue_free()
		inspector_plugin = null


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if gdss_editor:
		gdss_editor.visible = visible
		if visible:
			was_in_distraction_free_mode = EditorInterface.distraction_free_mode
			EditorInterface.distraction_free_mode = true
		if not was_in_distraction_free_mode and not visible:
			EditorInterface.distraction_free_mode = false


func _get_plugin_name() -> String:
	return "Style"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon(&"Theme", &"EditorIcons")


func _debug_hook() -> void:
	await get_tree().process_frame
	debug_container = HBoxContainer.new()
	EditorInterface.get_base_control().add_child(debug_container)
	
	debug_label = Label.new()
	debug_label.text = "GDSS Debug Mode is ON: "
	debug_label.label_settings = LabelSettings.new()
	debug_label.label_settings.shadow_size = 3
	debug_label.label_settings.shadow_color = Color(0, 0, 0, 1)
	debug_label.label_settings.shadow_offset = Vector2.ZERO
	debug_container.add_child(debug_label)
	
	debug_refresh_button = Button.new()
	debug_refresh_button.text = "Refresh"
	debug_refresh_button.pressed.connect(func() -> void:
		print("[GDSS] Refreshing...")
		_debug_unhook()
		EditorInterface.set_plugin_enabled("gdss", false)
		EditorInterface.call_deferred(&"set_plugin_enabled", "gdss", true)
	)
	debug_container.add_child(debug_refresh_button)
	
	debug_unhook_button = Button.new()
	debug_unhook_button.text = "Unhook"
	debug_unhook_button.pressed.connect(_debug_unhook)
	debug_container.add_child(debug_unhook_button)
	
	await get_tree().process_frame
	
	debug_container.position = (EditorInterface.get_base_control().size) - debug_container.size - Vector2(20, 20)
	print("[GDSS] Debug mode hooked!")


func _is_debug_hooked() -> bool:
	return is_instance_valid(debug_container)


func _debug_unhook() -> void:
	if debug_container:
		debug_container.queue_free()
