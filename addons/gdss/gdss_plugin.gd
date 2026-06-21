@tool
extends EditorPlugin


const GdssInspector = preload("uid://bhvd3stvftya8")
const GDSS_EDITOR = preload("uid://bh4sv3ta53fmk")

static var _inst: EditorPlugin

var debug_container: Container
var debug_label: Label
var debug_refresh_button: Button
var debug_unhook_button: Button
var debug_repopulate_button: Button
var gdss_editor: GdssEditor
var inspector_plugin: GdssInspectorPlugin
var export_plugin: GdssExportPlugin
var import_plugin: GdssImportPlugin
var gdss_dock: GdssDock
var was_in_distraction_free_mode: bool = false
var _loading_scene: bool = false


func _enter_tree() -> void:
	_inst = self
	var db: GdssDB = GDSS.get_db()
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
	if get_tree() != null and get_tree().node_added.is_connected(_on_editor_node_added):
		get_tree().node_added.disconnect(_on_editor_node_added)
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
	if export_plugin:
		remove_export_plugin(export_plugin)
		export_plugin = null
	if import_plugin:
		remove_import_plugin(import_plugin)
		import_plugin = null
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
	if not ProjectSettings.has_setting("gdss/binding/root_default"):
		ProjectSettings.set_setting("gdss/binding/root_default", 0)
		ProjectSettings.set_initial_value("gdss/binding/root_default", 0)
		ProjectSettings.add_property_info({
			"name": "gdss/binding/root_default",
			"type": TYPE_INT,
			"hint": PROPERTY_HINT_ENUM,
			"hint_string": "Disable,Enable"
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
	if GDSS.DEBUG_MODE:
		_debug_hook()
	add_inspector_plugin(inspector_plugin)
	export_plugin = GdssExportPlugin.new()
	add_export_plugin(export_plugin)
	import_plugin = GdssImportPlugin.new()
	add_import_plugin(import_plugin)
	if not ProjectSettings.has_setting("autoload/GdssRuntime"):
		add_autoload_singleton("GdssRuntime", "res://addons/gdss/runtime.gd")
	if not scene_changed.is_connected(_on_scene_changed):
		scene_changed.connect(_on_scene_changed)
	if not get_tree().node_added.is_connected(_on_editor_node_added):
		get_tree().node_added.connect(_on_editor_node_added)
	GdssNodeHandler.rebind_tree.bind(EditorInterface.get_edited_scene_root()).call_deferred()


func _on_scene_changed(scene_root: Node) -> void:
	_loading_scene = true
	GdssNodeHandler.rebind_tree(scene_root)
	_clear_loading_scene.call_deferred()


func _clear_loading_scene() -> void:
	_loading_scene = false


func _on_editor_node_added(node: Node) -> void:
	if _loading_scene:
		return
	if not node is CanvasItem:
		return
	var scene_root: Node = EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return
	if node != scene_root and not scene_root.is_ancestor_of(node):
		return
	GdssNodeHandler.apply_mode.call_deferred(node as CanvasItem)


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
		GDSS.get_db().repopulate()
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
