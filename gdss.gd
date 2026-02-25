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
	BOOLEAN,
	COLOR,
	COMPOSITE,
	COMPOSITE4,
	CURSOR,
	TRANSITION_TYPE,
	TRANSITION_FUNC,
}

enum CursorType {
	ARROW,
	POINTING,
	IBEAM,
	DISABLED
}

enum TransitionType {
	EASE_IN,
	EASE_OUT,
	EASE_IN_OUT,
	EASE_OUT_IN,
}

enum TransitionFunc {
	LINEAR,
	SINE,
	QUINT,
	QUART,
	QUAD,
	EXPO,
	ELASTIC,
	CUBIC,
	CIRC,
	BOUNCE,
	BACK,
	SPRING
}

var debug_container: Container
var debug_label: Label
var debug_refresh_button: Button
var debug_unhook_button: Button
var debug_repopulate_button: Button
var gdss_editor: GdssEditor
var inspector_plugin: GdssInspectorPlugin

var theme_hook: Control

var was_in_distraction_free_mode: bool = false


static func get_gdss_nodes() -> Dictionary[String, GdssNode]:
	var nl: GdssNodeList = preload("uid://jw1xlcsh6exq")
	return nl.list


static func get_gdss_methods() -> Dictionary[String, GdssMethod]:
	var ml: GdssMethodList = preload("uid://b5cvdpn7uy7xt")
	return ml.list


func _enter_tree() -> void:
	if not ProjectSettings.has_setting("gdss/storage/save_path"):
		ProjectSettings.set_setting("gdss/storage/save_path", "res://gdss_data.gdss")
		ProjectSettings.set_initial_value("gdss/storage/save_path", "res://gdss_data.gdss")
		ProjectSettings.add_property_info({
			"name": "gdss/storage/save_path",
			"type": TYPE_STRING,
			"hint": PROPERTY_HINT_FILE,
			"hint_string": "*.gdss"
		})

	gdss_editor = GDSS_EDITOR.instantiate()
	inspector_plugin = GdssInspectorPlugin.new()
	EditorInterface.get_editor_main_screen().add_child(gdss_editor)
	
	_make_visible(false)
	if DEBUG_MODE:
		_debug_hook()
	add_inspector_plugin(inspector_plugin)
	add_autoload_singleton("GdssRuntime", "res://addons/gdss/runtime.gd")


func _exit_tree() -> void:
	if gdss_editor:
		gdss_editor.queue_free()
	if inspector_plugin:
		remove_inspector_plugin(inspector_plugin)
		inspector_plugin = null
	remove_autoload_singleton("GdssRuntime")


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
	debug_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	EditorInterface.get_base_control().add_child(debug_container)
	
	debug_label = Label.new()
	debug_label.text = "GDSS Debug Mode is ON: "
	debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	
	debug_repopulate_button = Button.new()
	debug_repopulate_button.text = "Repopulate (Nodes + Methods)"
	debug_repopulate_button.pressed.connect(func() -> void:
		preload("uid://b5cvdpn7uy7xt")._populate_list.call()
		preload("uid://jw1xlcsh6exq")._populate_list.call()
		EditorInterface.get_editor_toaster().push_toast("Repopulated nodes + methods!", EditorToaster.SEVERITY_INFO)
	)
	debug_container.add_child(debug_repopulate_button)
	
	debug_unhook_button = Button.new()
	debug_unhook_button.text = "Unhook"
	debug_unhook_button.pressed.connect(_debug_unhook)
	debug_container.add_child(debug_unhook_button)
	
	await get_tree().process_frame
	
	debug_container.position = (EditorInterface.get_base_control().size) - debug_container.size - Vector2(20, 20)
	print("[GDSS] Debug mode hooked!")
	EditorInterface.get_editor_toaster().push_toast("GDSS reloaded!", EditorToaster.SEVERITY_INFO)


func _is_debug_hooked() -> bool:
	return is_instance_valid(debug_container)


func _debug_unhook() -> void:
	if debug_container:
		debug_container.queue_free()
