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

static var _inst: EditorPlugin

var debug_container: Container
var debug_label: Label
var debug_refresh_button: Button
var debug_unhook_button: Button
var debug_repopulate_button: Button
var gdss_editor: GdssEditor
var inspector_plugin: GdssInspectorPlugin
var gdss_dock: GdssDock

var theme_hook: Control
var was_in_distraction_free_mode: bool = false


## Gets the value of a [b]global variable[/b] defined in GDSS.
## [br][br]
## Global variables are shared across the entire environment. If the variable
## does not exist, it returns the [param fallback] value.
## [codeblock]
## var my_color: Color = GDSS.get_global_var("theme_accent", Color.WHITE)
## [/codeblock]
static func get_global_var(name: String, fallback: Variant = null) -> Variant:
	return GdssInterpreter.globals.get(name, fallback)

## Sets the value of a [b]global variable[/b] and triggers a refresh.
## [br][br]
## This updates the global state and automatically notifies any objects or 
## UI elements that are currently "listening" to or affected by this variable.
## [codeblock]
## GDSS.set_global_var("player_score", 100)
## [/codeblock]
static func set_global_var(name: String, value: Variant) -> void:
	GdssInterpreter.globals[name] = value
	_refresh_affected(name)

## Assigns an [b]instance-specific override[/b] for a GDSS variable on a Node.
## [br][br]
## If the [param node] has a [code]gdss_handler[/code] meta-tag, this function will 
## automatically apply the new value, emit change signals, and queue a redraw 
## if the node is a [CanvasItem].
## [codeblock]
## GDSS.set_instance_var(enemy_sprite, "modulate_color", Color.RED)
## [/codeblock]
static func set_instance_var(node: Node, name: String, value: Variant) -> void:
	var id: int = node.get_instance_id()
	if not GdssInterpreter._instance_vars.has(id):
		GdssInterpreter._instance_vars[id] = {}
	GdssInterpreter._instance_vars[id][name] = value
	var gdss_node: GdssNode = GDSS._get_gdss_nodes().get(node.get_class()) if node is CanvasItem else null
	if gdss_node != null and gdss_node.is_static:
		for state: String in gdss_node.states:
			var meta_key: StringName = "gdss_handler_" + state
			if node.has_meta(meta_key):
				var box: GdssPropHandler = node.get_meta(meta_key) as GdssPropHandler
				box._apply_overrides()
				box.emit_changed()
				if node is CanvasItem:
					(node as CanvasItem).queue_redraw()
	elif node.has_meta("gdss_handler"):
		var box: GdssPropHandler = node.get_meta("gdss_handler") as GdssPropHandler
		box._apply_overrides()
		box.emit_changed()
		if node is CanvasItem:
			(node as CanvasItem).queue_redraw()

## Retrieves the value of a variable for a [b]specific Node instance[/b].
## [br][br]
## This function checks for local overrides first. If no instance-specific 
## value is found, it falls back to the default value defined in 
## [code]_instance_defaults[/code].
## [codeblock]
## var speed = GDSS.get_instance_var(self, "move_speed", 200.0)
## [/codeblock]
static func get_instance_var(node: Node, name: String, fallback: Variant = null) -> Variant:
	var id: int = node.get_instance_id()
	if GdssInterpreter._instance_vars.has(id):
		return GdssInterpreter._instance_vars[id].get(name, fallback)
	return GdssInterpreter._instance_defaults.get(name, fallback)

## Clears all GDSS instance variables from a specific node.
static func clear_instance_vars(node: Node) -> void:
	GdssInterpreter._instance_vars.erase(node.get_instance_id())


static func _refresh_affected(global_name: String) -> void:
	var sentinel: String = "__gdss_global__" + global_name
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	_refresh_affected_tree(tree.root, sentinel)


static func _refresh_affected_tree(node: Node, sentinel: String) -> void:
	var gdss_node: GdssNode = GDSS._get_gdss_nodes().get(node.get_class())
	if gdss_node != null and gdss_node.is_static:
		for state: String in gdss_node.states:
			var meta_key: StringName = "gdss_handler_" + state
			if node.has_meta(meta_key):
				var box: GdssPropHandler = node.get_meta(meta_key) as GdssPropHandler
				if _handler_uses_sentinel(box, sentinel):
					box._apply_overrides()
					box.emit_changed()
					if node is CanvasItem:
						(node as CanvasItem).queue_redraw()
	elif node.has_meta("gdss_handler"):
		var box: GdssPropHandler = node.get_meta("gdss_handler") as GdssPropHandler
		if _handler_uses_sentinel(box, sentinel):
			box._apply_overrides()
			box.emit_changed()
			if node is CanvasItem:
				(node as CanvasItem).queue_redraw()
	for child: Node in node.get_children():
		_refresh_affected_tree(child, sentinel)


static func _handler_uses_sentinel(box: GdssPropHandler, sentinel: String) -> bool:
	var entry: Dictionary = box._resolve_entry()
	for state: String in entry:
		if not entry[state] is Dictionary:
			continue
		for key: String in entry[state]:
			var val: Variant = entry[state][key]
			if val is String and (val as String) == sentinel:
				return true
	return false


static func _get_gdss_nodes() -> Dictionary[String, GdssNode]:
	return get_db().node_list


static func _get_gdss_methods() -> Dictionary[String, GdssMethod]:
	return get_db().method_list


static func get_db() -> GdssDB:
	var db: GdssDB = preload("uid://wmo287ce38ty")
	return db


func _enter_tree() -> void:
	_inst = self

	var editor_settings: EditorSettings = EditorInterface.get_editor_settings()
	if not editor_settings.has_setting("gdss/editor/location"):
		editor_settings.set_setting("gdss/editor/location", 0)
		editor_settings.set_initial_value("gdss/editor/location", 0, false)
	editor_settings.add_property_info({
		"name": "gdss/editor/location",
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": "Dock,Main Screen"
	})
	editor_settings.settings_changed.connect(_on_editor_settings_changed)


	if not ProjectSettings.has_setting("gdss/storage/save_path"):
		ProjectSettings.set_setting("gdss/storage/save_path", "res://theme.gdss")
		ProjectSettings.set_initial_value("gdss/storage/save_path", "res://theme.gdss")
		ProjectSettings.add_property_info({
			"name": "gdss/storage/save_path",
			"type": TYPE_STRING,
			"hint": PROPERTY_HINT_FILE,
			"hint_string": "*.gdss"
		})

	inspector_plugin = GdssInspectorPlugin.new()
	gdss_editor = GDSS_EDITOR.instantiate()

	if _has_main_screen():
		EditorInterface.get_editor_main_screen().add_child(gdss_editor)
		_make_visible(false)
	else:
		gdss_dock = GdssDock.new()
		gdss_dock.set_editor(gdss_editor)
		add_dock(gdss_dock)

	if DEBUG_MODE:
		_debug_hook()
	add_inspector_plugin(inspector_plugin)
	add_autoload_singleton("GdssRuntime", "res://addons/gdss/runtime.gd")


func _exit_tree() -> void:
	var editor_settings: EditorSettings = EditorInterface.get_editor_settings()
	if editor_settings.settings_changed.is_connected(_on_editor_settings_changed):
		editor_settings.settings_changed.disconnect(_on_editor_settings_changed)
	if is_instance_valid(gdss_editor):
		gdss_editor.queue_free()
		gdss_editor = null
	if is_instance_valid(gdss_dock):
		remove_dock(gdss_dock)
		gdss_dock.queue_free()
		gdss_dock = null
	if inspector_plugin:
		remove_inspector_plugin(inspector_plugin)
		inspector_plugin = null
	remove_autoload_singleton("GdssRuntime")


func _on_editor_settings_changed() -> void:
	if EditorInterface.get_editor_settings().get_setting("gdss/editor/location") != (1 if _has_main_screen() else 0):
		return
	EditorInterface.get_editor_toaster().push_toast(
		"GDSS: Reload the project to apply dock mode changes.",
		EditorToaster.SEVERITY_WARNING
	)


func _has_main_screen() -> bool:
	return EditorInterface.get_editor_settings().get_setting("gdss/editor/location") == 1


func _make_visible(visible: bool) -> void:
	if not _has_main_screen():
		return
	if gdss_editor:
		gdss_editor.visible = visible
		if visible:
			was_in_distraction_free_mode = EditorInterface.distraction_free_mode
			EditorInterface.distraction_free_mode = true
		if not was_in_distraction_free_mode and not visible:
			EditorInterface.distraction_free_mode = false


func _get_plugin_name() -> String:
	return "GDSS"


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
		get_db().repopulate()
		EditorInterface.get_editor_toaster().push_toast("Repopulated nodes + methods!", EditorToaster.SEVERITY_INFO)
	)
	debug_container.add_child(debug_repopulate_button)

	debug_unhook_button = Button.new()
	debug_unhook_button.text = "Unhook"
	debug_unhook_button.pressed.connect(_debug_unhook)
	debug_container.add_child(debug_unhook_button)

	await get_tree().process_frame

	debug_container.position = EditorInterface.get_base_control().size - debug_container.size - Vector2(20, 20)
	print("[GDSS] Debug mode hooked!")
	EditorInterface.get_editor_toaster().push_toast("GDSS reloaded!", EditorToaster.SEVERITY_INFO)


func _is_debug_hooked() -> bool:
	return is_instance_valid(debug_container)


func _debug_unhook() -> void:
	if debug_container:
		debug_container.queue_free()
