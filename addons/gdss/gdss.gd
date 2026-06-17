@tool
class_name GDSS
extends EditorPlugin
## Looking for documentation on the plugin as a whole? See [GDSSDocumentation].


const DEBUG_MODE: bool = false
const DEBUG_WAS_VISIBLE: StringName = &"gdss_was_visible"
const CLASSES_META: StringName = &"gdss_classes"

const GdssInspector = preload("uid://bhvd3stvftya8")
const GDSS_EDITOR = preload("uid://bh4sv3ta53fmk")

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
	ICON,
	FONT,
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
static var _db: GdssDB
static var _global_flush_scheduled: bool = false
static var _gpu_panels: int = -1

var debug_container: Container
var debug_label: Label
var debug_refresh_button: Button
var debug_unhook_button: Button
var debug_repopulate_button: Button
var gdss_editor: GdssEditor
var inspector_plugin: GdssInspectorPlugin
var gdss_dock: GdssDock
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
	if _global_flush_scheduled:
		return
	if Engine.get_main_loop() == null:
		_flush_global_refresh()
		return
	_global_flush_scheduled = true
	_flush_global_refresh.call_deferred()


## Assigns an [b]instance-specific override[/b] for a GDSS variable on a Node.
## [br][br]
## If the [param node] is currently bound to GDSS, this function will
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
	if node is CanvasItem:
		GdssNodeHandler.refresh(node as CanvasItem)


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


## Returns the GDSS classes currently applied to [param node], in priority order.
## [codeblock]
## var classes: PackedStringArray = GDSS.get_classes(my_button)
## [/codeblock]
static func get_classes(node: Node) -> PackedStringArray:
	return node.get_meta(CLASSES_META, PackedStringArray()) as PackedStringArray


## Replaces every GDSS class on [param node] and reapplies its style.
## [codeblock]
## GDSS.set_classes(my_button, PackedStringArray(["GhostButton", "PillButton"]))
## [/codeblock]
static func set_classes(node: Node, classes: PackedStringArray) -> void:
	node.set_meta(CLASSES_META, classes)
	if node is CanvasItem:
		GdssNodeHandler.refresh(node as CanvasItem)


## Returns [code]true[/code] if [param gdss_class] is currently applied to [param node].
static func has_class(node: Node, gdss_class: String) -> bool:
	return get_classes(node).has(gdss_class)


## Adds [param gdss_class] to [param node] and reapplies its style.
## [br][br]
## Does nothing if the class is already present.
## [codeblock]
## GDSS.add_class(my_button, "PillButton")
## [/codeblock]
static func add_class(node: Node, gdss_class: String) -> void:
	var classes: PackedStringArray = get_classes(node)
	if classes.has(gdss_class):
		return
	classes.append(gdss_class)
	set_classes(node, classes)


## Removes [param gdss_class] from [param node] and reapplies its style.
## [br][br]
## Does nothing if the class is not present.
static func remove_class(node: Node, gdss_class: String) -> void:
	var classes: PackedStringArray = get_classes(node)
	var index: int = classes.find(gdss_class)
	if index == -1:
		return
	classes.remove_at(index)
	set_classes(node, classes)


## Toggles [param gdss_class] on [param node], returning its new state
## ([code]true[/code] if the class is now applied).
## [codeblock]
## var active: bool = GDSS.toggle_class(my_button, "Active")
## [/codeblock]
static func toggle_class(node: Node, gdss_class: String) -> bool:
	if has_class(node, gdss_class):
		remove_class(node, gdss_class)
		return false
	add_class(node, gdss_class)
	return true


## Removes all GDSS classes from [param node] and reapplies its style.
static func clear_classes(node: Node) -> void:
	if get_classes(node).is_empty():
		return
	set_classes(node, PackedStringArray())


## Returns [code]true[/code] if GDSS styling is currently enabled on [param node].
static func is_gdss_enabled(node: Node) -> bool:
	return node.is_in_group(GdssNodeHandler.GROUP)


## Enables GDSS styling on [param node].
## [br][br]
## Adds the node to the GDSS group and binds it so its style is applied and kept
## in sync. Has no visible effect on node types GDSS does not style.
## [codeblock]
## GDSS.enable_gdss(my_button)
## [/codeblock]
static func enable_gdss(node: Node) -> void:
	if not node.is_in_group(GdssNodeHandler.GROUP):
		node.add_to_group(GdssNodeHandler.GROUP, true)
	if node is CanvasItem:
		GdssNodeHandler.bind(node as CanvasItem)


## Disables GDSS styling on [param node].
## [br][br]
## Unbinds the node, removes its GDSS style overrides, and takes it out of the
## GDSS group.
## [codeblock]
## GDSS.disable_gdss(my_button)
## [/codeblock]
static func disable_gdss(node: Node) -> void:
	if node is CanvasItem and _get_gdss_nodes().has(node.get_class()):
		GdssNodeHandler.unbind(node as CanvasItem)
	node.remove_from_group(GdssNodeHandler.GROUP)


static func gpu_panels_enabled() -> bool:
	if _gpu_panels == -1:
		if not ProjectSettings.has_setting("gdss/rendering/gpu_panels"):
			ProjectSettings.set_setting("gdss/rendering/gpu_panels", true)
		_gpu_panels = 1 if ProjectSettings.get_setting("gdss/rendering/gpu_panels", true) else 0
	return _gpu_panels == 1


static func _flush_global_refresh() -> void:
	_global_flush_scheduled = false
	var seen: Dictionary[int, bool] = {}
	for handler: GdssPropHandler in GdssNodeHandler.get_all_handlers():
		var item: CanvasItem = handler.ref
		if item == null:
			continue
		var id: int = item.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		item.queue_redraw()


static func _get_gdss_nodes() -> Dictionary[String, GdssNode]:
	return get_db().node_list


static func _get_gdss_methods() -> Dictionary[String, GdssMethod]:
	return get_db().method_list


static func get_db() -> GdssDB:
	if _db != null and not _db.node_list.is_empty():
		return _db
	var db: GdssDB = load("res://addons/gdss/db/db.tres")
	if db != null:
		_db = db
	if _db == null:
		_db = GdssDB.new()
	return _db


func _enter_tree() -> void:
	_inst = self
	var db: GdssDB = get_db()
	if db != null and db.node_list.is_empty():
		db.repopulate()
	var is_first_run: bool = not ProjectSettings.has_setting("gdss/internal/initialized")
	if is_first_run:
		ProjectSettings.set_setting("gdss/internal/initialized", true)
		ProjectSettings.save()
	_setup_settings()
	if is_first_run:
		_prompt_reload.call_deferred()
		return
	_setup_editor()


func _exit_tree() -> void:
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)
	var editor_settings: EditorSettings = EditorInterface.get_editor_settings()
	if editor_settings.settings_changed.is_connected(_on_editor_settings_changed):
		editor_settings.settings_changed.disconnect(_on_editor_settings_changed)
	if is_instance_valid(gdss_dock):
		remove_dock(gdss_dock)
		gdss_dock.queue_free()
		gdss_dock = null
		gdss_editor = null
	elif is_instance_valid(gdss_editor):
		gdss_editor.queue_free()
		gdss_editor = null
	if inspector_plugin:
		remove_inspector_plugin(inspector_plugin)
		inspector_plugin = null
	if ProjectSettings.has_setting("autoload/GdssRuntime"):
		remove_autoload_singleton("GdssRuntime")


func _setup_settings() -> void:
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
		ProjectSettings.set_setting("gdss/storage/save_path", "res://theme.tgdss")
		ProjectSettings.set_initial_value("gdss/storage/save_path", "res://theme.tgdss")
		ProjectSettings.add_property_info({
			"name": "gdss/storage/save_path",
			"type": TYPE_STRING,
			"hint": PROPERTY_HINT_FILE,
			"hint_string": "*.tgdss,*.gdss"
		})
	if not ProjectSettings.has_setting("gdss/storage/gdss_cache_path"):
		ProjectSettings.set_setting("gdss/storage/gdss_cache_path", "user://gdss_cache.gdssc")
		ProjectSettings.set_initial_value("gdss/storage/gdss_cache_path", "user://gdss_cache.gdssc")
		ProjectSettings.add_property_info({
			"name": "gdss/storage/gdss_cache_path",
			"type": TYPE_STRING,
			"hint": PROPERTY_HINT_PLACEHOLDER_TEXT,
			"hint_string": "user://gdss_cache.gdssc"
		})
	if not ProjectSettings.has_setting("gdss/rendering/gpu_panels"):
		ProjectSettings.set_setting("gdss/rendering/gpu_panels", true)
	ProjectSettings.set_initial_value("gdss/rendering/gpu_panels", true)
	ProjectSettings.add_property_info({
		"name": "gdss/rendering/gpu_panels",
		"type": TYPE_BOOL,
		"hint": PROPERTY_HINT_NONE,
		"hint_string": "Draw panels with a GPU SDF shader (fast). Disable to use the CPU geometry fallback."
	})
	ProjectSettings.save()


func _setup_editor() -> void:
	inspector_plugin = GdssInspectorPlugin.new()
	gdss_editor = GDSS_EDITOR.instantiate()
	if _has_main_screen():
		gdss_editor.set(&"size_flags_horizontal", Control.SIZE_EXPAND_FILL)
		gdss_editor.set(&"size_flags_vertical", Control.SIZE_EXPAND_FILL)
		EditorInterface.get_editor_main_screen().add_child(gdss_editor)
		_make_visible(false)
	else:
		gdss_dock = GdssDock.new()
		gdss_dock.set_editor(gdss_editor)
		add_dock(gdss_dock)
	if DEBUG_MODE:
		_debug_hook()
	add_inspector_plugin(inspector_plugin)
	if not ProjectSettings.has_setting("autoload/GdssRuntime"):
		add_autoload_singleton("GdssRuntime", "res://addons/gdss/runtime.gd")
	if not scene_changed.is_connected(_on_scene_changed):
		scene_changed.connect(_on_scene_changed)
	GdssNodeHandler.rebind_tree.bind(EditorInterface.get_edited_scene_root()).call_deferred()


func _on_scene_changed(scene_root: Node) -> void:
	GdssNodeHandler.rebind_tree(scene_root)


# Called by the editor right before a scene is packed for saving. Strip the
# live GDSS overrides so they are never baked into the .tscn, then restore them
# on the next idle frame so the editor preview is uninterrupted.
func _apply_changes() -> void:
	GdssNodeHandler.strip_overrides()
	_reapply_overrides_deferred.call_deferred()


func _reapply_overrides_deferred() -> void:
	GdssNodeHandler.reapply_overrides()


func _prompt_reload() -> void:
	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.title = "GDSS Reload Recommended"
	dialog.dialog_text = "GDSS has been enabled for the first time,\nplease reload the project to use it.\n(You may have to enable the plugin again)"
	dialog.ok_button_text = "Reload Now"
	dialog.cancel_button_text = "Later"
	dialog.exclusive = false
	dialog.confirmed.connect(func() -> void:
		EditorInterface.restart_editor(true)
	)
	dialog.canceled.connect(dialog.queue_free)
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered()


func _on_editor_settings_changed() -> void:
	pass


func _has_main_screen() -> bool:
	return EditorInterface.get_editor_settings().get_setting("gdss/editor/location") == 1


func _make_visible(visible: bool) -> void:
	if not _has_main_screen() or not is_instance_valid(gdss_editor):
		return
	gdss_editor.set(&"visible", visible)
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
