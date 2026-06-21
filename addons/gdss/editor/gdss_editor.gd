@tool
class_name GdssEditor
extends Node

static var _code_editor_ref: CodeEdit
static var _re_hex: RegEx = RegEx.create_from_string(r"\"(#[0-9A-Fa-f]{3,8})\"")
static var _re_word: RegEx = RegEx.create_from_string(r"[A-Za-z_][A-Za-z_0-9]*")
static var _auto_checked: bool = false

@export_group("refs")
@export var code_edit: CodeEdit
@export var error_label: Label
@export var title_label: Label
@export var copy_button: Button
@export var toggle_map_button: Button
@export var caret_pos_label: Label
@export var zoom_percentage: Button
@export var outline: GdssOutline

var err_line_num: int
var font_size: float
var initial_font_size: float
var font_min: float
var font_max: float

var _has_unsaved_changes: bool = false
var _suppress_dirty: bool = false
var _current_file_path: String = ""
var _saved_label: Label
var _saved_tween: Tween

var _updater: GdssUpdater
var _version_button: Button
var _update_available: bool = false
var _latest_version: String = ""
var _latest_url: String = ""
var _checking: bool = false
var _check_silent: bool = false
var _chunk_tabs: TabBar
var _chunks: Array[Dictionary] = []
var _active_chunk: int = 0
var _rebuilding_tabs: bool = false
var _swatch_hitboxes: Array[Dictionary] = []
var _chunk_offsets: PackedInt32Array = []
var _error_target_chunk: int = 0
var _error_target_line: int = 0
var _error_bg: Color = Color.RED
var _all_errors: Array = []
var _highlighted_lines: PackedInt32Array = []
var _error_cursor: int = -1
var _error_timer: Timer
var _search_bar: VBoxContainer
var _search_field: LineEdit
var _search_label: Label
var _replace_row: HBoxContainer
var _replace_field: LineEdit
var _search_matches: Array[Vector2i] = []
var _search_index: int = -1
var _zoom_menu: PopupMenu
var _file_menu: PopupMenu
var _recent_menu: PopupMenu

enum {
	MENU_SAVE,
	MENU_NEW,
	MENU_OPEN,
	MENU_SAVE_AS,
	MENU_RENAME,
	MENU_REVEAL,
	MENU_THEME_PROPERTIES,
	MENU_FIND,
	MENU_REPLACE,
	MENU_COMMENT,
	MENU_SPACES_TO_TABS,
	MENU_MOVE_UP,
	MENU_MOVE_DOWN,
	MENU_SELECT_NEXT,
	MENU_NEXT_ERROR,
	MENU_PREV_ERROR,
	MENU_FOLD_ALL,
	MENU_UNFOLD_ALL,
	MENU_CHECK_UPDATE,
}

var file_name: String:
	get():
		return GdssStorage.get_save_path().get_file()


func _ready() -> void:
	initial_font_size = code_edit.get_theme_font_size(&"font_size")
	font_size = initial_font_size
	font_min = initial_font_size * 0.25
	font_max = initial_font_size * 3
	if not is_running_as_plugin():
		set_process(false)
		return
	
	name = "GDSS"
	_code_editor_ref = code_edit
	error_label.add_theme_font_override(&"font", EditorInterface.get_editor_theme().get_font(&"expression", &"EditorFonts"))
	error_label.add_theme_color_override(&"font_color", EditorInterface.get_editor_theme().get_color(&"error_color", &"Editor"))
	error_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	error_label.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton:
			if e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_jump_to_error()
	)
	_setup_saved_label()
	
	copy_button.icon = EditorInterface.get_editor_theme().get_icon(&"ActionCopy", &"EditorIcons")
	
	if not ProjectSettings.has_setting("gdss/editor/use_minimap"):
		ProjectSettings.set_setting("gdss/editor/use_minimap", true)
	
	toggle_map_button.button_pressed = ProjectSettings.get_setting("gdss/editor/use_minimap")
	
	title_label.text = file_name
	code_edit.gui_input.connect(_on_code_edit_input)
	code_edit.caret_changed.connect(_on_code_edit_caret_changed)
	_setup_outline_toggle()
	_setup_location_toggle()
	_setup_version_button()
	_setup_menu_bar()
	_push_recent(GdssStorage.get_save_path())
	_setup_interpreter()
	_setup_chunk_tabs()
	_setup_search()
	_setup_color_swatches()
	_update_editor()
	_on_code_edit_caret_changed()


func _setup_outline_toggle() -> void:
	if outline == null or toggle_map_button == null:
		return
	if not ProjectSettings.has_setting("gdss/editor/show_outline"):
		ProjectSettings.set_setting("gdss/editor/show_outline", true)
	var show_outline: bool = ProjectSettings.get_setting("gdss/editor/show_outline")
	outline.visible = show_outline
	var toggle: Button = Button.new()
	toggle.toggle_mode = true
	toggle.button_pressed = show_outline
	toggle.theme_type_variation = &"FlatButton"
	toggle.tooltip_text = "Toggle the outline panel"
	var editor_theme: Theme = EditorInterface.get_editor_theme()
	if editor_theme.has_icon(&"Tree", &"EditorIcons"):
		toggle.icon = editor_theme.get_icon(&"Tree", &"EditorIcons")
	else:
		toggle.text = "Outline"
	toggle.toggled.connect(_on_outline_toggled)
	var toolbar: Node = toggle_map_button.get_parent()
	toolbar.add_child(toggle)
	toolbar.move_child(toggle, toggle_map_button.get_index())


func _on_outline_toggled(pressed: bool) -> void:
	outline.visible = pressed
	ProjectSettings.set_setting("gdss/editor/show_outline", pressed)


func _setup_location_toggle() -> void:
	if toggle_map_button == null:
		return
	var button: Button = Button.new()
	button.toggle_mode = true
	button.button_pressed = EditorInterface.get_editor_settings().get_setting("gdss/editor/location") == 1
	button.theme_type_variation = &"FlatButton"
	button.tooltip_text = "Show GDSS as a main-screen tab (requires a project reload)"
	var editor_theme: Theme = EditorInterface.get_editor_theme()
	if editor_theme.has_icon(&"MakeFloating", &"EditorIcons"):
		button.icon = editor_theme.get_icon(&"MakeFloating", &"EditorIcons")
	else:
		button.text = "Main Screen"
	button.toggled.connect(_on_location_toggled)
	var toolbar: Node = toggle_map_button.get_parent()
	toolbar.add_child(button)
	toolbar.move_child(button, toggle_map_button.get_index())


func _on_location_toggled(pressed: bool) -> void:
	EditorInterface.get_editor_settings().set_setting("gdss/editor/location", 1 if pressed else 0)
	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.title = "GDSS"
	dialog.dialog_text = "Reload the project to apply the GDSS editor placement."
	dialog.ok_button_text = "Reload Now"
	dialog.cancel_button_text = "Later"
	dialog.confirmed.connect(func() -> void:
		EditorInterface.restart_editor(true)
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.queue_free)
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered()


func _setup_version_button() -> void:
	if toggle_map_button == null:
		return
	_ensure_updater()
	_version_button = Button.new()
	_version_button.theme_type_variation = &"FlatButton"
	_version_button.pressed.connect(_on_version_button_pressed)
	var toolbar: Node = toggle_map_button.get_parent()
	toolbar.add_child(_version_button)
	toolbar.move_child(_version_button, 1)
	_set_update_state(false, _updater.get_current_version(), "")
	if not _auto_checked:
		_auto_checked = true
		_run_update_check(true)


func _on_version_button_pressed() -> void:
	if _update_available:
		_prompt_install()
	else:
		_run_update_check(false)


func _set_update_state(available: bool, version: String, url: String) -> void:
	_update_available = available
	_latest_version = version if available else ""
	_latest_url = url if available else ""
	if _version_button == null:
		return
	var editor_theme: Theme = EditorInterface.get_editor_theme()
	if available:
		_version_button.text = "Update to %s" % version
		_version_button.tooltip_text = "GDSS %s is available, click to update" % version
		_version_button.add_theme_color_override(&"font_color", editor_theme.get_color(&"accent_color", &"Editor"))
		if editor_theme.has_icon(&"Reload", &"EditorIcons"):
			_version_button.icon = editor_theme.get_icon(&"Reload", &"EditorIcons")
	else:
		_version_button.text = "v%s" % version
		_version_button.tooltip_text = "GDSS %s, click to check for updates" % version
		_version_button.remove_theme_color_override(&"font_color")
		_version_button.icon = null


func _setup_chunk_tabs() -> void:
	var split: Control = code_edit.get_parent() as Control
	if split == null:
		return
	_error_bg = EditorInterface.get_editor_settings().get_setting("text_editor/theme/highlighting/mark_color")
	var inner_box: Node = split.get_parent()
	var bar: HBoxContainer = HBoxContainer.new()
	_chunk_tabs = TabBar.new()
	_chunk_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chunk_tabs.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ACTIVE_ONLY
	_chunk_tabs.drag_to_rearrange_enabled = true
	bar.add_child(_chunk_tabs)
	var add_button: Button = Button.new()
	add_button.theme_type_variation = &"FlatButton"
	add_button.tooltip_text = "Add a new chunk"
	var editor_theme: Theme = EditorInterface.get_editor_theme()
	if editor_theme.has_icon(&"Add", &"EditorIcons"):
		add_button.icon = editor_theme.get_icon(&"Add", &"EditorIcons")
	else:
		add_button.text = "+"
	bar.add_child(add_button)
	inner_box.add_child(bar)
	inner_box.move_child(bar, split.get_index())
	if _chunks.is_empty():
		_chunks = _parse_chunks(code_edit.text)
		code_edit.text = _chunks[_active_chunk]["content"]
	_rebuild_chunk_tabs()
	_chunk_tabs.tab_selected.connect(_on_chunk_selected)
	_chunk_tabs.tab_close_pressed.connect(_on_chunk_closed)
	_chunk_tabs.tab_rmb_clicked.connect(_on_chunk_rename)
	_chunk_tabs.active_tab_rearranged.connect(_on_chunk_rearranged)
	add_button.pressed.connect(_on_chunk_added)


func set_full_source(source: String) -> void:
	_chunks = _parse_chunks(source)
	_active_chunk = clampi(_active_chunk, 0, _chunks.size() - 1)
	code_edit.text = _chunks[_active_chunk]["content"]
	if _chunk_tabs != null:
		_rebuild_chunk_tabs()


func get_full_source() -> String:
	_sync_active_chunk()
	_chunk_offsets = PackedInt32Array()
	if _chunks.size() <= 1:
		_chunk_offsets.append(0)
		return _chunks[0]["content"] if not _chunks.is_empty() else code_edit.text
	var parts: PackedStringArray = []
	var line_cursor: int = 0
	for chunk: Dictionary in _chunks:
		parts.append("# @chunk " + str(chunk["name"]))
		line_cursor += 1
		_chunk_offsets.append(line_cursor)
		var content: String = chunk["content"]
		parts.append(content)
		line_cursor += content.split("\n").size()
	return "\n".join(parts)


func _parse_chunks(source: String) -> Array[Dictionary]:
	var chunks: Array[Dictionary] = []
	var chunk_name: String = "main"
	var lines: PackedStringArray = []
	for line: String in source.split("\n"):
		if line.strip_edges().begins_with("# @chunk"):
			chunks.append({"name": chunk_name, "content": "\n".join(lines)})
			chunk_name = line.strip_edges().substr("# @chunk".length()).strip_edges()
			lines = PackedStringArray()
		else:
			lines.append(line)
	chunks.append({"name": chunk_name, "content": "\n".join(lines)})
	if chunks.size() > 1 and (chunks[0]["content"] as String).strip_edges().is_empty():
		chunks.remove_at(0)
	return chunks


func _sync_active_chunk() -> void:
	if _active_chunk >= 0 and _active_chunk < _chunks.size():
		_chunks[_active_chunk]["content"] = code_edit.text


func _rebuild_chunk_tabs() -> void:
	_rebuilding_tabs = true
	_chunk_tabs.clear_tabs()
	for chunk: Dictionary in _chunks:
		_chunk_tabs.add_tab(str(chunk["name"]))
	if _active_chunk >= 0 and _active_chunk < _chunks.size():
		_chunk_tabs.current_tab = _active_chunk
	_rebuilding_tabs = false


func _on_chunk_selected(idx: int) -> void:
	if _rebuilding_tabs:
		return
	if idx < 0 or idx >= _chunks.size() or idx == _active_chunk:
		return
	_sync_active_chunk()
	_active_chunk = idx
	_suppress_dirty = true
	code_edit.text = _chunks[idx]["content"]
	if _chunk_tabs != null and _chunk_tabs.current_tab != idx:
		_chunk_tabs.current_tab = idx
	code_edit.text_changed.emit()
	_clear_suppress_dirty.call_deferred()


func _on_chunk_added() -> void:
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = "New Chunk"
	var line: LineEdit = LineEdit.new()
	line.placeholder_text = "chunk name"
	line.text = _unique_chunk_name("chunk")
	line.custom_minimum_size = Vector2(220, 0)
	dialog.add_child(line)
	dialog.register_text_enter(line)
	dialog.confirmed.connect(func() -> void:
		var entered: String = line.text.strip_edges()
		if entered.is_empty():
			entered = "chunk"
		_create_chunk(_unique_chunk_name(entered))
	)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered()
	line.grab_focus()
	line.select_all()


func _create_chunk(chunk_name: String) -> void:
	_sync_active_chunk()
	_chunks.append({"name": chunk_name, "content": ""})
	_active_chunk = _chunks.size() - 1
	_suppress_dirty = true
	code_edit.text = ""
	_rebuild_chunk_tabs()
	_clear_suppress_dirty.call_deferred()
	GdssInterpreter.get_instance().save_current(get_full_source())


func _on_chunk_closed(idx: int) -> void:
	if _chunks.size() <= 1 or idx < 0 or idx >= _chunks.size():
		return
	if str(_chunks[idx]["content"]).strip_edges().is_empty():
		_delete_chunk(idx)
		return
	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.title = "Delete Chunk"
	dialog.dialog_text = "Delete chunk '%s'? Its contents will be removed.\nThe change is only applied once you save (Ctrl+S)." % _chunks[idx]["name"]
	dialog.ok_button_text = "Delete"
	dialog.confirmed.connect(_delete_chunk.bind(idx))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered()


func _delete_chunk(idx: int) -> void:
	if _chunks.size() <= 1 or idx < 0 or idx >= _chunks.size():
		return
	_sync_active_chunk()
	_chunks.remove_at(idx)
	if _active_chunk > idx:
		_active_chunk -= 1
	_active_chunk = clampi(_active_chunk, 0, _chunks.size() - 1)
	code_edit.text = _chunks[_active_chunk]["content"]
	_rebuild_chunk_tabs()
	code_edit.text_changed.emit()


func _on_chunk_rearranged(_idx_to: int) -> void:
	_sync_active_chunk()
	var active_name: String = str(_chunks[_active_chunk]["name"])
	var pool: Array[Dictionary] = _chunks.duplicate()
	var reordered: Array[Dictionary] = []
	for tab_index: int in _chunk_tabs.get_tab_count():
		var tab_name: String = _chunk_tabs.get_tab_title(tab_index)
		for pool_index: int in pool.size():
			if str(pool[pool_index]["name"]) == tab_name:
				reordered.append(pool[pool_index])
				pool.remove_at(pool_index)
				break
	if reordered.size() != _chunks.size():
		return
	_chunks = reordered
	for chunk_index: int in _chunks.size():
		if str(_chunks[chunk_index]["name"]) == active_name:
			_active_chunk = chunk_index
			break
	_prompt_save()


func goto_full_source_line(full_line: int) -> void:
	get_full_source()
	var chunk: int = _chunk_for_line(full_line)
	if chunk != _active_chunk:
		_on_chunk_selected(chunk)
	var chunk_start: int = _chunk_offsets[chunk] if chunk < _chunk_offsets.size() else 0
	var local_line: int = full_line - chunk_start
	if local_line >= 0 and local_line < code_edit.get_line_count():
		code_edit.set_caret_line(local_line)
		code_edit.set_caret_column(code_edit.get_line(local_line).length())
		code_edit.center_viewport_to_caret()


func _on_chunk_rename(idx: int) -> void:
	if idx < 0 or idx >= _chunks.size():
		return
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = "Rename Chunk"
	var line: LineEdit = LineEdit.new()
	line.text = str(_chunks[idx]["name"])
	line.custom_minimum_size = Vector2(220, 0)
	dialog.add_child(line)
	dialog.register_text_enter(line)
	dialog.confirmed.connect(func() -> void:
		var new_name: String = line.text.strip_edges()
		if not new_name.is_empty():
			_chunks[idx]["name"] = new_name
			_rebuild_chunk_tabs()
			GdssInterpreter.get_instance().save_current(get_full_source())
	)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered()
	line.grab_focus()


func _unique_chunk_name(base: String) -> String:
	var taken: PackedStringArray = []
	for chunk: Dictionary in _chunks:
		taken.append(str(chunk["name"]))
	var candidate: String = base
	var suffix: int = 2
	while Array(taken).has(candidate):
		candidate = base + str(suffix)
		suffix += 1
	return candidate


func display_errors(errors: Array) -> void:
	_all_errors = errors
	_error_cursor = -1
	for line_index: int in _highlighted_lines:
		if line_index < code_edit.get_line_count():
			code_edit.set_line_background_color(line_index, Color.TRANSPARENT)
	_highlighted_lines = PackedInt32Array()
	if errors.is_empty():
		show_error("", -1)
		return
	var active_start: int = _chunk_offsets[_active_chunk] if _active_chunk < _chunk_offsets.size() else 0
	var active_end: int = active_start + code_edit.get_line_count()
	for err: Array in errors:
		var full_line: int = err[1]
		if full_line >= active_start and full_line < active_end:
			var local_line: int = full_line - active_start
			if local_line >= 0 and local_line < code_edit.get_line_count():
				code_edit.set_line_background_color(local_line, _error_bg)
				_highlighted_lines.append(local_line)
	var first: Array = errors[0]
	_error_target_chunk = _chunk_for_line(first[1])
	var chunk_start: int = _chunk_offsets[_error_target_chunk] if _error_target_chunk < _chunk_offsets.size() else 0
	_error_target_line = first[1] - chunk_start
	var message: String = str(first[0]) if _error_target_chunk == _active_chunk else "[%s] %s" % [_chunks[_error_target_chunk]["name"], first[0]]
	show_error(message, _error_target_line, errors.size())


func _chunk_for_line(full_line: int) -> int:
	var result: int = 0
	for i: int in _chunk_offsets.size():
		if full_line >= _chunk_offsets[i]:
			result = i
	return result


func _jump_to_error() -> void:
	if _error_target_chunk != _active_chunk and _error_target_chunk >= 0 and _error_target_chunk < _chunks.size():
		_on_chunk_selected(_error_target_chunk)
	if _error_target_line >= 0 and _error_target_line < code_edit.get_line_count():
		code_edit.set_caret_line(_error_target_line)
		code_edit.center_viewport_to_caret()


func get_code_edit() -> CodeEdit:
	return code_edit


func _setup_interpreter() -> void:
	_error_timer = Timer.new()
	_error_timer.wait_time = 0.5
	_error_timer.one_shot = true
	_error_timer.timeout.connect(_on_error_check_timeout)
	add_child(_error_timer)
	if not code_edit.text_changed.is_connected(_on_source_changed):
		code_edit.text_changed.connect(_on_source_changed)
	var interpreter: GdssInterpreter = GdssInterpreter.get_instance()
	if interpreter == null:
		return
	if not interpreter.source_loaded.is_connected(_on_interpreter_source_loaded):
		interpreter.source_loaded.connect(_on_interpreter_source_loaded)
	if not interpreter.saved.is_connected(_on_interpreter_saved):
		interpreter.saved.connect(_on_interpreter_saved)
	interpreter.initialize()


func _on_source_changed() -> void:
	_prompt_save()
	_error_timer.start()


func _on_error_check_timeout() -> void:
	_recheck_errors()


func _recheck_errors() -> void:
	var interpreter: GdssInterpreter = GdssInterpreter.get_instance()
	if interpreter != null:
		display_errors(interpreter.check_errors(get_full_source()))


func _on_interpreter_source_loaded(source: String) -> void:
	var was_connected: bool = code_edit.text_changed.is_connected(_on_source_changed)
	if was_connected:
		code_edit.text_changed.disconnect(_on_source_changed)
	set_full_source(source)
	if was_connected:
		code_edit.text_changed.connect(_on_source_changed)
	_recheck_errors.call_deferred()


func _on_interpreter_saved() -> void:
	_user_saved()


func _goto_error(direction: int) -> void:
	if _all_errors.is_empty():
		return
	if _error_cursor == -1:
		_error_cursor = 0 if direction > 0 else _all_errors.size() - 1
	else:
		_error_cursor = wrapi(_error_cursor + direction, 0, _all_errors.size())
	var err: Array = _all_errors[_error_cursor]
	goto_full_source_line(int(err[1]))
	var chunk_start: int = _chunk_offsets[_active_chunk] if _active_chunk < _chunk_offsets.size() else 0
	show_error(str(err[0]), int(err[1]) - chunk_start, _all_errors.size(), _error_cursor)


func show_error(message: String, line_num: int, total_errors: int = 1, current_index: int = -1) -> void:
	if line_num == -1:
		error_label.text = ""
		error_label.tooltip_text = ""
		error_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		copy_button.disabled = true
		return

	var more_suffix: String = ""
	if current_index >= 0 and total_errors > 1:
		more_suffix = "  (%d/%d)" % [current_index + 1, total_errors]
	elif total_errors > 1:
		more_suffix = "  (+%d more)" % (total_errors - 1)
	error_label.text = "[%s]: %s%s" % [line_num + 1, message, more_suffix]
	error_label.tooltip_text = error_label.text
	err_line_num = line_num
	error_label.mouse_filter = Control.MOUSE_FILTER_STOP
	copy_button.disabled = false


func _on_code_edit_input(event: InputEvent) -> void:
	if event is InputEventMagnifyGesture:
		font_size += ((event as InputEventMagnifyGesture).factor - 1) * 5
		_apply_font_size()
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if not (mb.pressed and mb.is_command_or_control_pressed()):
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			font_size += 2
			_apply_font_size()
			code_edit.get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			font_size -= 2
			_apply_font_size()
			code_edit.get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey:
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed:
		return
	if key.keycode == KEY_EQUAL and key.is_command_or_control_pressed():
		font_size += 4
		_apply_font_size()
		code_edit.get_viewport().set_input_as_handled()
	if key.keycode == KEY_MINUS and key.is_command_or_control_pressed():
		font_size -= 4
		_apply_font_size()
		code_edit.get_viewport().set_input_as_handled()
	if key.keycode == KEY_S and key.is_command_or_control_pressed():
		GdssInterpreter.get_instance().save_current(get_full_source())
		code_edit.get_viewport().set_input_as_handled()
	if key.keycode == KEY_I and key.is_command_or_control_pressed() and key.shift_pressed:
		_convert_spaces_to_tabs()
		code_edit.get_viewport().set_input_as_handled()
	if key.keycode == KEY_SLASH and key.is_command_or_control_pressed():
		_toggle_comment()
		code_edit.get_viewport().set_input_as_handled()
	if key.keycode == KEY_D and key.is_command_or_control_pressed():
		_select_next_occurrence()
		code_edit.get_viewport().set_input_as_handled()
	if key.keycode == KEY_F and key.is_command_or_control_pressed():
		_open_search(key.shift_pressed)
		code_edit.get_viewport().set_input_as_handled()
	if key.keycode == KEY_UP and key.alt_pressed:
		code_edit.move_lines_up()
		code_edit.get_viewport().set_input_as_handled()
	if key.keycode == KEY_DOWN and key.alt_pressed:
		code_edit.move_lines_down()
		code_edit.get_viewport().set_input_as_handled()
	if key.keycode == KEY_F8:
		_goto_error(-1 if key.shift_pressed else 1)
		code_edit.get_viewport().set_input_as_handled()


func _apply_font_size() -> void:
	font_size = clampf(font_size, font_min, font_max)
	code_edit.add_theme_font_size_override(&"font_size", int(font_size))
	zoom_percentage.text = "%d%%" % int(round(font_size / initial_font_size * 100.0))


func _set_zoom_percent(percent: int) -> void:
	font_size = initial_font_size * percent / 100.0
	_apply_font_size()


func _setup_menu_bar() -> void:
	var top_bar: Node = title_label.get_node_or_null("HBoxContainer")
	if top_bar == null:
		return
	var menu_bar: MenuBar = MenuBar.new()
	menu_bar.flat = true
	_file_menu = PopupMenu.new()
	_file_menu.name = "File"
	_file_menu.add_item("New…", MENU_NEW)
	_file_menu.add_item("Open…", MENU_OPEN)
	_recent_menu = PopupMenu.new()
	_recent_menu.name = "RecentMenu"
	_recent_menu.index_pressed.connect(_on_recent_selected)
	_file_menu.add_submenu_node_item("Open Recent", _recent_menu)
	_file_menu.add_separator()
	_file_menu.add_item("Save  (Ctrl+S)", MENU_SAVE)
	_file_menu.add_item("Save As…", MENU_SAVE_AS)
	_file_menu.add_item("Rename…", MENU_RENAME)
	_file_menu.add_separator()
	_file_menu.add_item("Reveal in FileSystem", MENU_REVEAL)
	_file_menu.add_separator()
	_file_menu.add_item("Theme Properties…", MENU_THEME_PROPERTIES)
	_file_menu.id_pressed.connect(_on_menu_id_pressed)
	_file_menu.about_to_popup.connect(_refresh_recent_menu)
	menu_bar.add_child(_file_menu)
	var edit_menu: PopupMenu = PopupMenu.new()
	edit_menu.name = "Edit"
	edit_menu.add_item("Find  (Ctrl+F)", MENU_FIND)
	edit_menu.add_item("Find & Replace  (Ctrl+Shift+F)", MENU_REPLACE)
	edit_menu.add_separator()
	edit_menu.add_item("Toggle Comment  (Ctrl+/)", MENU_COMMENT)
	edit_menu.add_item("Convert Spaces to Tabs  (Ctrl+Shift+I)", MENU_SPACES_TO_TABS)
	edit_menu.add_separator()
	edit_menu.add_item("Move Line Up  (Alt+Up)", MENU_MOVE_UP)
	edit_menu.add_item("Move Line Down  (Alt+Down)", MENU_MOVE_DOWN)
	edit_menu.add_item("Select Next Occurrence  (Ctrl+D)", MENU_SELECT_NEXT)
	edit_menu.add_separator()
	edit_menu.add_item("Next Error  (F8)", MENU_NEXT_ERROR)
	edit_menu.add_item("Previous Error  (Shift+F8)", MENU_PREV_ERROR)
	edit_menu.add_separator()
	edit_menu.add_item("Fold All", MENU_FOLD_ALL)
	edit_menu.add_item("Unfold All", MENU_UNFOLD_ALL)
	edit_menu.id_pressed.connect(_on_menu_id_pressed)
	menu_bar.add_child(edit_menu)
	var help_menu: PopupMenu = PopupMenu.new()
	help_menu.name = "Help"
	help_menu.add_item("Check for Updates…", MENU_CHECK_UPDATE)
	help_menu.id_pressed.connect(_on_menu_id_pressed)
	menu_bar.add_child(help_menu)
	top_bar.add_child(menu_bar)
	top_bar.move_child(menu_bar, 0)


func _on_menu_id_pressed(id: int) -> void:
	match id:
		MENU_SAVE:
			GdssInterpreter.get_instance().save_current(get_full_source())
		MENU_NEW:
			_new_file()
		MENU_OPEN:
			_open_file()
		MENU_SAVE_AS:
			_save_as()
		MENU_RENAME:
			_rename_file()
		MENU_REVEAL:
			if Engine.is_editor_hint():
				EditorInterface.select_file(GdssStorage.get_save_path())
		MENU_THEME_PROPERTIES:
			_open_theme_properties()
		MENU_FIND:
			_open_search(false)
		MENU_REPLACE:
			_open_search(true)
		MENU_COMMENT:
			_toggle_comment()
		MENU_SPACES_TO_TABS:
			_convert_spaces_to_tabs()
		MENU_MOVE_UP:
			code_edit.move_lines_up()
		MENU_MOVE_DOWN:
			code_edit.move_lines_down()
		MENU_SELECT_NEXT:
			_select_next_occurrence()
		MENU_NEXT_ERROR:
			_goto_error(1)
		MENU_PREV_ERROR:
			_goto_error(-1)
		MENU_FOLD_ALL:
			code_edit.fold_all_lines()
		MENU_UNFOLD_ALL:
			code_edit.unfold_all_lines()
		MENU_CHECK_UPDATE:
			_check_for_updates()


func _toggle_comment() -> void:
	var from_line: int = code_edit.get_caret_line()
	var to_line: int = from_line
	if code_edit.has_selection():
		from_line = code_edit.get_selection_from_line()
		to_line = code_edit.get_selection_to_line()
	var all_commented: bool = true
	for line_index: int in range(from_line, to_line + 1):
		var stripped: String = code_edit.get_line(line_index).strip_edges()
		if not stripped.is_empty() and not stripped.begins_with("#"):
			all_commented = false
			break
	code_edit.begin_complex_operation()
	for line_index: int in range(from_line, to_line + 1):
		var line: String = code_edit.get_line(line_index)
		if line.strip_edges().is_empty():
			continue
		if all_commented:
			var hash_index: int = line.find("#")
			if hash_index != -1:
				var tail: String = line.substr(hash_index + 1)
				if tail.begins_with(" "):
					tail = tail.substr(1)
				code_edit.set_line(line_index, line.substr(0, hash_index) + tail)
		else:
			var indent: int = line.length() - line.lstrip(" \t").length()
			code_edit.set_line(line_index, line.substr(0, indent) + "#" + line.substr(indent))
	code_edit.end_complex_operation()


func _select_next_occurrence() -> void:
	if not code_edit.has_selection():
		code_edit.select_word_under_caret()
		return
	var last: int = code_edit.get_caret_count() - 1
	var needle: String = code_edit.get_selected_text(last)
	if needle.is_empty():
		return
	var result: Vector2i = code_edit.search(needle, 0, code_edit.get_selection_to_line(last), code_edit.get_selection_to_column(last))
	if result.x == -1:
		result = code_edit.search(needle, 0, 0, 0)
	if result.x == -1:
		return
	var new_caret: int = code_edit.add_caret(result.y, result.x + needle.length())
	if new_caret != -1:
		code_edit.select(result.y, result.x, result.y, result.x + needle.length(), new_caret)
		code_edit.center_viewport_to_caret(new_caret)


func _setup_search() -> void:
	var split: Control = code_edit.get_parent() as Control
	if split == null:
		return
	var theme: Theme = EditorInterface.get_editor_theme()
	_search_bar = VBoxContainer.new()
	_search_bar.visible = false
	var find_row: HBoxContainer = HBoxContainer.new()
	_search_field = LineEdit.new()
	_search_field.placeholder_text = "Find…"
	_search_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	find_row.add_child(_search_field)
	_search_label = Label.new()
	_search_label.custom_minimum_size = Vector2(52, 0)
	_search_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	find_row.add_child(_search_label)
	var prev_button: Button = _make_tool_button(theme, &"MoveUp", "Previous match")
	prev_button.pressed.connect(_advance_search.bind(-1))
	find_row.add_child(prev_button)
	var next_button: Button = _make_tool_button(theme, &"MoveDown", "Next match")
	next_button.pressed.connect(_advance_search.bind(1))
	find_row.add_child(next_button)
	var close_button: Button = _make_tool_button(theme, &"Close", "Close")
	close_button.pressed.connect(_close_search)
	find_row.add_child(close_button)
	_search_bar.add_child(find_row)
	_replace_row = HBoxContainer.new()
	_replace_row.visible = false
	_replace_field = LineEdit.new()
	_replace_field.placeholder_text = "Replace…"
	_replace_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_replace_row.add_child(_replace_field)
	var replace_button: Button = Button.new()
	replace_button.text = "Replace"
	replace_button.pressed.connect(_replace_current)
	_replace_row.add_child(replace_button)
	var replace_all_button: Button = Button.new()
	replace_all_button.text = "Replace All"
	replace_all_button.pressed.connect(_replace_all)
	_replace_row.add_child(replace_all_button)
	_search_bar.add_child(_replace_row)
	var inner_box: Node = split.get_parent()
	inner_box.add_child(_search_bar)
	inner_box.move_child(_search_bar, 0)
	_search_field.text_changed.connect(_on_search_text_changed)
	_search_field.text_submitted.connect(func(_text: String) -> void: _advance_search(1))
	_search_field.gui_input.connect(_on_search_field_input)
	_replace_field.text_submitted.connect(func(_text: String) -> void: _replace_current())
	_replace_field.gui_input.connect(_on_search_field_input)


func _make_tool_button(theme: Theme, icon_name: StringName, tooltip: String) -> Button:
	var button: Button = Button.new()
	button.theme_type_variation = &"FlatButton"
	button.tooltip_text = tooltip
	if theme.has_icon(icon_name, &"EditorIcons"):
		button.icon = theme.get_icon(icon_name, &"EditorIcons")
	else:
		button.text = tooltip.left(1)
	return button


func _open_search(replace_mode: bool = false) -> void:
	if _search_bar == null:
		return
	_search_bar.visible = true
	_replace_row.visible = replace_mode
	if code_edit.has_selection():
		_search_field.text = code_edit.get_selected_text()
	_rebuild_matches()
	_focus_match(_search_index)
	_search_field.grab_focus()
	_search_field.select_all()


func _close_search() -> void:
	if _search_bar != null:
		_search_bar.visible = false
	code_edit.grab_focus()


func _on_search_text_changed(_text: String) -> void:
	_rebuild_matches()
	_focus_match(_search_index)


func _on_search_field_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed:
		return
	if key.keycode == KEY_ESCAPE:
		_close_search()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_UP:
		_advance_search(-1)
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_DOWN:
		_advance_search(1)
		get_viewport().set_input_as_handled()


func _rebuild_matches() -> void:
	_search_matches.clear()
	var needle: String = _search_field.text
	if needle.is_empty():
		_search_index = -1
		_update_search_label()
		return
	var lower_needle: String = needle.to_lower()
	var lines: PackedStringArray = code_edit.text.split("\n")
	for line_idx: int in lines.size():
		var hay: String = lines[line_idx].to_lower()
		var from: int = 0
		while true:
			var found: int = hay.find(lower_needle, from)
			if found == -1:
				break
			_search_matches.append(Vector2i(found, line_idx))
			from = found + needle.length()
	_search_index = _nearest_match_index()
	_update_search_label()


func _nearest_match_index() -> int:
	if _search_matches.is_empty():
		return -1
	var line: int = code_edit.get_caret_line()
	var col: int = code_edit.get_caret_column()
	if code_edit.has_selection():
		line = code_edit.get_selection_from_line()
		col = code_edit.get_selection_from_column()
	for i: int in _search_matches.size():
		var m: Vector2i = _search_matches[i]
		if m.y > line or (m.y == line and m.x >= col):
			return i
	return 0


func _advance_search(direction: int) -> void:
	if _search_matches.is_empty():
		_rebuild_matches()
	if _search_matches.is_empty():
		_update_search_label()
		return
	if _search_index == -1:
		_search_index = _nearest_match_index()
	else:
		_search_index = (_search_index + direction + _search_matches.size()) % _search_matches.size()
	_focus_match(_search_index)


func _focus_match(index: int) -> void:
	if index < 0 or index >= _search_matches.size():
		_update_search_label()
		return
	var m: Vector2i = _search_matches[index]
	var length: int = _search_field.text.length()
	code_edit.remove_secondary_carets()
	code_edit.set_caret_line(m.y)
	code_edit.set_caret_column(m.x + length)
	code_edit.select(m.y, m.x, m.y, m.x + length)
	code_edit.center_viewport_to_caret()
	_update_search_label()


func _update_search_label() -> void:
	if _search_matches.is_empty():
		_search_label.text = "" if _search_field.text.is_empty() else "0/0"
		return
	_search_label.text = "%d/%d" % [_search_index + 1, _search_matches.size()]


func _replace_current() -> void:
	var needle: String = _search_field.text
	if needle.is_empty() or _search_index < 0 or _search_index >= _search_matches.size():
		return
	if code_edit.has_selection() and code_edit.get_selected_text().to_lower() == needle.to_lower():
		code_edit.begin_complex_operation()
		code_edit.delete_selection()
		code_edit.insert_text_at_caret(_replace_field.text)
		code_edit.end_complex_operation()
	_rebuild_matches()
	_focus_match(_search_index)


func _replace_all() -> void:
	var needle: String = _search_field.text
	if needle.is_empty() or _search_matches.is_empty():
		return
	code_edit.remove_secondary_carets()
	code_edit.begin_complex_operation()
	for idx: int in range(_search_matches.size() - 1, -1, -1):
		var m: Vector2i = _search_matches[idx]
		code_edit.select(m.y, m.x, m.y, m.x + needle.length())
		code_edit.delete_selection()
		code_edit.set_caret_line(m.y)
		code_edit.set_caret_column(m.x)
		code_edit.insert_text_at_caret(_replace_field.text)
	code_edit.end_complex_operation()
	_rebuild_matches()


func _on_code_edit_caret_changed() -> void:
	caret_pos_label.text = "%s:%s" % [code_edit.get_caret_line() + 1, code_edit.get_caret_column()]


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
	_user_saved(false)


func _prompt_save() -> void:
	if _suppress_dirty or _has_unsaved_changes:
		return
	_has_unsaved_changes = true
	title_label.text = file_name + "(*)"


func _clear_suppress_dirty() -> void:
	_suppress_dirty = false


func _user_saved(flash: bool = true) -> void:
	_has_unsaved_changes = false
	title_label.text = file_name
	if flash:
		_show_saved()


func _show_saved() -> void:
	if _saved_label == null:
		return
	if _saved_tween != null and _saved_tween.is_valid():
		_saved_tween.kill()
	_saved_label.text = "Saved!"
	_saved_label.modulate.a = 1.0
	_saved_tween = create_tween().set_ease(Tween.EASE_IN)
	_saved_tween.tween_interval(0.8)
	_saved_tween.tween_property(_saved_label, "modulate:a", 0.0, 0.7)
	_saved_tween.tween_callback(func() -> void:
		_saved_label.text = ""
	)


func _setup_saved_label() -> void:
	_saved_label = Label.new()
	_saved_label.add_theme_font_override(&"font", EditorInterface.get_editor_theme().get_font(&"expression", &"EditorFonts"))
	_saved_label.add_theme_color_override(&"font_color", EditorInterface.get_editor_theme().get_color(&"success_color", &"Editor"))
	_saved_label.modulate = Color(1, 1, 1, 0)
	var bar: Node = error_label.get_parent()
	bar.add_child(_saved_label)
	bar.move_child(_saved_label, 0)


func get_current_file_path() -> String:
	return _current_file_path if not _current_file_path.is_empty() else GdssStorage.get_save_path()


func has_unsaved_changes() -> bool:
	return _has_unsaved_changes


func _on_copy_button_pressed() -> void:
	if Input.is_key_pressed(KEY_SHIFT) and not _all_errors.is_empty():
		var formatted: PackedStringArray = []
		for err: Array in _all_errors:
			var chunk: int = _chunk_for_line(err[1])
			var chunk_start: int = _chunk_offsets[chunk] if chunk < _chunk_offsets.size() else 0
			var line_label: String = str(err[1] - chunk_start + 1)
			if _chunks.size() > 1:
				line_label = "%s:%s" % [_chunks[chunk]["name"], line_label]
			formatted.append("[%s] %s" % [line_label, err[0]])
		DisplayServer.clipboard_set("\n".join(formatted))
		return
	DisplayServer.clipboard_set(error_label.text)


func is_running_as_plugin() -> bool:
	var host: Node = get_parent()
	if host is EditorDock:
		return true
	return Engine.is_editor_hint() and host == EditorInterface.get_editor_main_screen()


func _on_toggle_map_button_toggled(toggled_on: bool) -> void:
	ProjectSettings.set_setting("gdss/editor/use_minimap", toggled_on)
	_update_editor()


func _update_editor() -> void:
	code_edit.minimap_draw = ProjectSettings.get_setting("gdss/editor/use_minimap")


func _on_doc_button_pressed() -> void:
	EditorInterface.get_script_editor().goto_help("class_name:GDSSDocumentation")


func _on_zoom_percentage_pressed() -> void:
	_ensure_zoom_menu()
	_zoom_menu.reset_size()
	var origin: Vector2 = zoom_percentage.get_screen_position()
	_zoom_menu.position = Vector2i(int(origin.x), int(origin.y - _zoom_menu.size.y))
	_zoom_menu.popup()


func _ensure_zoom_menu() -> void:
	if _zoom_menu != null:
		return
	_zoom_menu = PopupMenu.new()
	for level: int in [25, 50, 75, 100, 150, 200, 300]:
		_zoom_menu.add_item("%d%%" % level, level)
	_zoom_menu.id_pressed.connect(_set_zoom_percent)
	zoom_percentage.add_child(_zoom_menu)
	


func _open_theme_properties() -> void:
	var dialog: GdssThemePropertiesDialog = GdssThemePropertiesDialog.new()
	EditorInterface.get_base_control().add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.open_for(self)


func upsert_meta_block(block_text: String) -> void:
	var interpreter: GdssInterpreter = GdssInterpreter.get_instance()
	if interpreter == null:
		return
	_sync_active_chunk()
	var replaced: bool = false
	for chunk: Dictionary in _chunks:
		var outcome: Dictionary = interpreter.replace_meta_block(str(chunk["content"]), block_text)
		if outcome["found"]:
			chunk["content"] = outcome["source"]
			replaced = true
			break
	if not replaced:
		_chunks[0]["content"] = _insert_meta_at_top(str(_chunks[0]["content"]), block_text)
	_suppress_dirty = true
	code_edit.text = _chunks[_active_chunk]["content"]
	_clear_suppress_dirty.call_deferred()
	interpreter.save_current(get_full_source())


func _insert_meta_at_top(content: String, block_text: String) -> String:
	var lines: PackedStringArray = content.split("\n")
	var insert_at: int = 0
	for i: int in lines.size():
		var stripped: String = lines[i].strip_edges()
		if stripped.is_empty() or stripped.begins_with("#"):
			insert_at = i + 1
		else:
			break
	var result: PackedStringArray = lines.slice(0, insert_at)
	result.append_array(block_text.split("\n"))
	result.append("")
	result.append_array(lines.slice(insert_at))
	return "\n".join(result)


const RECENT_KEY: String = "gdss/editor/recent_files"
const RECENT_MAX: int = 10


func _base_control() -> Node:
	return EditorInterface.get_base_control()


func _show_error(message: String) -> void:
	_show_info("GDSS", message)


func _show_info(title: String, message: String) -> void:
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = title
	dialog.dialog_text = message
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	_base_control().add_child(dialog)
	dialog.popup_centered()


func _ensure_updater() -> void:
	if _updater == null:
		_updater = GdssUpdater.new()
		add_child(_updater)
		_updater.check_completed.connect(_on_update_checked)


func _check_for_updates() -> void:
	_run_update_check(false)


func _run_update_check(silent: bool) -> void:
	_ensure_updater()
	if _checking:
		if not silent:
			_check_silent = false
		return
	_checking = true
	_check_silent = silent
	_updater.check()


func _on_update_checked(result: Dictionary) -> void:
	_checking = false
	if not result.get("ok", false):
		if not _check_silent:
			_show_info("Update check failed", str(result.get("message", "Unknown error.")))
		return
	if not result.get("update", false):
		_set_update_state(false, str(result.get("current")), "")
		if not _check_silent:
			_show_info("GDSS is up to date", "You have the latest version (%s)." % result.get("current"))
		return
	_set_update_state(true, str(result.get("latest")), str(result.get("url")))
	if not _check_silent:
		_prompt_install()


func _prompt_install() -> void:
	var confirm: ConfirmationDialog = ConfirmationDialog.new()
	confirm.title = "Update available"
	confirm.dialog_text = "GDSS %s is available, you have %s.\n\nUpdating overwrites the files in res://addons/gdss. Reload the project afterward to apply.\n\nUpdate now?" % [_latest_version, _updater.get_current_version()]
	confirm.confirmed.connect(_install_update.bind(_latest_version, _latest_url))
	confirm.confirmed.connect(confirm.queue_free)
	confirm.canceled.connect(confirm.queue_free)
	_base_control().add_child(confirm)
	confirm.popup_centered()


func _install_update(version: String, url: String) -> void:
	_updater.install_completed.connect(_on_update_installed, CONNECT_ONE_SHOT)
	_updater.install(version, url)


func _on_update_installed(success: bool, message: String) -> void:
	if not success:
		_show_info("Update failed", message)
		return
	var confirm: ConfirmationDialog = ConfirmationDialog.new()
	confirm.title = "Update installed"
	confirm.dialog_text = message + "\n\nRestart the editor now?"
	confirm.confirmed.connect(func() -> void: EditorInterface.restart_editor(true))
	confirm.canceled.connect(confirm.queue_free)
	_base_control().add_child(confirm)
	confirm.popup_centered()


func _make_file_dialog(save_mode: bool) -> EditorFileDialog:
	var dialog: EditorFileDialog = EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE if save_mode else EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.add_filter("*.tgdss", "GDSS Theme")
	dialog.current_dir = GdssStorage.get_save_path().get_base_dir()
	dialog.canceled.connect(dialog.queue_free)
	_base_control().add_child(dialog)
	return dialog


func _new_file() -> void:
	_confirm_unsaved(func() -> void:
		var dialog: EditorFileDialog = _make_file_dialog(true)
		dialog.current_file = "theme.tgdss"
		dialog.file_selected.connect(func(path: String) -> void:
			GdssStorage.write_source(path, "# @chunk main\n")
			_switch_to_file(path)
			dialog.queue_free()
		)
		dialog.popup_centered_ratio(0.5)
	)


func _open_file() -> void:
	_confirm_unsaved(func() -> void:
		var dialog: EditorFileDialog = _make_file_dialog(false)
		dialog.file_selected.connect(func(path: String) -> void:
			_switch_to_file(path)
			dialog.queue_free()
		)
		dialog.popup_centered_ratio(0.5)
	)


func _save_as() -> void:
	var dialog: EditorFileDialog = _make_file_dialog(true)
	dialog.current_file = file_name
	dialog.file_selected.connect(func(path: String) -> void:
		GdssStorage.write_source(path, get_full_source())
		_switch_to_file(path)
		dialog.queue_free()
	)
	dialog.popup_centered_ratio(0.5)


func _rename_file() -> void:
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = "Rename Stylesheet"
	var line: LineEdit = LineEdit.new()
	line.text = file_name
	line.custom_minimum_size = Vector2(260, 0)
	dialog.add_child(line)
	dialog.register_text_enter(line)
	dialog.confirmed.connect(func() -> void:
		var new_name: String = line.text.strip_edges().get_file()
		if new_name.is_empty():
			return
		if new_name.get_extension() != "tgdss":
			new_name = new_name.get_basename() + ".tgdss"
		var old_path: String = GdssStorage.get_save_path()
		var new_path: String = old_path.get_base_dir().path_join(new_name)
		if new_path == old_path:
			return
		if FileAccess.file_exists(new_path):
			_show_error("A file named '%s' already exists." % new_name)
			return
		GdssStorage.write_source(old_path, get_full_source())
		var error: int = DirAccess.rename_absolute(old_path, new_path)
		if error != OK:
			_show_error("Could not rename the stylesheet.")
			return
		var old_compiled: String = old_path.get_basename() + ".gdssc"
		if FileAccess.file_exists(old_compiled):
			DirAccess.remove_absolute(old_compiled)
		_switch_to_file(new_path)
		if Engine.is_editor_hint():
			EditorInterface.get_resource_filesystem().scan()
	)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	_base_control().add_child(dialog)
	dialog.popup_centered()
	line.grab_focus()
	line.select_all()


func _switch_to_file(path: String) -> void:
	GdssStorage.set_save_path(path)
	_active_chunk = 0
	_push_recent(path)
	var interpreter: GdssInterpreter = GdssInterpreter.get_instance()
	if interpreter != null:
		interpreter.reload_active_file()
	if Engine.is_editor_hint():
		GdssNodeHandler.rebind_tree(EditorInterface.get_edited_scene_root())
	_user_saved(false)


func _confirm_unsaved(on_proceed: Callable) -> void:
	if not _has_unsaved_changes:
		on_proceed.call()
		return
	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.title = "Unsaved Changes"
	dialog.dialog_text = "Save changes to '%s' before continuing?" % file_name
	dialog.ok_button_text = "Save & Continue"
	dialog.add_button("Discard", true, "discard")
	dialog.confirmed.connect(func() -> void:
		var interpreter: GdssInterpreter = GdssInterpreter.get_instance()
		if interpreter != null:
			interpreter.save_current(get_full_source())
		on_proceed.call()
		dialog.queue_free()
	)
	dialog.custom_action.connect(func(action: StringName) -> void:
		if action == "discard":
			on_proceed.call()
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	_base_control().add_child(dialog)
	dialog.popup_centered()


func _recent_files() -> PackedStringArray:
	var editor_settings: EditorSettings = EditorInterface.get_editor_settings()
	if editor_settings.has_setting(RECENT_KEY):
		return editor_settings.get_setting(RECENT_KEY)
	return PackedStringArray()


func _push_recent(path: String) -> void:
	var recent: PackedStringArray = _recent_files()
	var existing: int = recent.find(path)
	if existing != -1:
		recent.remove_at(existing)
	recent.insert(0, path)
	while recent.size() > RECENT_MAX:
		recent.remove_at(recent.size() - 1)
	EditorInterface.get_editor_settings().set_setting(RECENT_KEY, recent)


func _refresh_recent_menu() -> void:
	if _recent_menu == null:
		return
	_recent_menu.clear()
	var kept: PackedStringArray = PackedStringArray()
	for path: String in _recent_files():
		if not FileAccess.file_exists(path):
			continue
		kept.append(path)
		if path == GdssStorage.get_save_path():
			continue
		_recent_menu.add_item(path)
	EditorInterface.get_editor_settings().set_setting(RECENT_KEY, kept)
	if _recent_menu.item_count == 0:
		_recent_menu.add_item("(no recent files)")
		_recent_menu.set_item_disabled(_recent_menu.item_count - 1, true)


func _on_recent_selected(index: int) -> void:
	var path: String = _recent_menu.get_item_text(index)
	if not FileAccess.file_exists(path):
		return
	_confirm_unsaved(func() -> void:
		_switch_to_file(path)
	)


func _setup_color_swatches() -> void:
	if not code_edit.draw.is_connected(_draw_color_swatches):
		code_edit.draw.connect(_draw_color_swatches)
	if not code_edit.gui_input.is_connected(_on_swatch_gui_input):
		code_edit.gui_input.connect(_on_swatch_gui_input)
	var v_scroll: VScrollBar = code_edit.get_v_scroll_bar()
	if v_scroll != null and not v_scroll.value_changed.is_connected(_queue_swatch_redraw):
		v_scroll.value_changed.connect(_queue_swatch_redraw)


func _queue_swatch_redraw(_value: float) -> void:
	code_edit.queue_redraw()


func _strip_line_comment(line: String) -> String:
	var in_string: bool = false
	for i: int in line.length():
		var c: String = line[i]
		if c == "\"":
			in_string = not in_string
		elif c == "#" and not in_string:
			return line.substr(0, i)
	return line


func _find_colors_in_line(line: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var code: String = _strip_line_comment(line)
	for m: RegExMatch in _re_hex.search_all(code):
		if Color.html_is_valid(m.get_string(1)):
			out.append({"color": Color.html(m.get_string(1)), "from": m.get_start(0), "to": m.get_end(0)})
	var sentinel: Color = Color(-1, -1, -1, -1)
	for m: RegExMatch in _re_word.search_all(code):
		var start: int = m.get_start(0)
		if not _is_value_position(code, start):
			continue
		var col: Color = GdssInterpreter.parse_named_color(m.get_string(0), sentinel)
		if col != sentinel:
			out.append({"color": col, "from": start, "to": m.get_end(0)})
	return out


func _is_value_position(line: String, column: int) -> bool:
	var in_string: bool = false
	var has_separator: bool = false
	for i: int in column:
		var c: String = line[i]
		if c == "\"":
			in_string = not in_string
		elif not in_string and (c == ":" or c == "=" or c == "("):
			has_separator = true
	return has_separator and not in_string


func _draw_color_swatches() -> void:
	_swatch_hitboxes.clear()
	var first: int = code_edit.get_first_visible_line()
	var last: int = code_edit.get_last_full_visible_line()
	var line_height: float = code_edit.get_line_height()
	var swatch_size: float = maxf(line_height - 4.0, 6.0)
	for line: int in range(first, last + 1):
		if line < 0 or line >= code_edit.get_line_count():
			continue
		var colors: Array[Dictionary] = _find_colors_in_line(code_edit.get_line(line))
		if colors.is_empty():
			continue
		var anchor: Vector2 = code_edit.get_pos_at_line_column(line, code_edit.get_line(line).length())
		if anchor.x < 0 or anchor.y < 0:
			continue
		var swatch_y: float = anchor.y - line_height + (line_height - swatch_size) * 0.5
		var cursor_x: float = anchor.x + 12.0
		for hit: Dictionary in colors:
			var swatch: Rect2 = Rect2(cursor_x, swatch_y, swatch_size, swatch_size)
			code_edit.draw_rect(swatch, Color(0, 0, 0, 0.6))
			code_edit.draw_rect(swatch.grow(-1.0), hit["color"])
			_swatch_hitboxes.append({"rect": swatch, "line": line, "from": hit["from"], "to": hit["to"]})
			cursor_x += swatch_size + 4.0


func _on_swatch_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	for hit: Dictionary in _swatch_hitboxes:
		if hit["rect"].has_point(mb.position):
			_open_swatch_picker(hit)
			code_edit.accept_event()
			return


func _open_swatch_picker(hit: Dictionary) -> void:
	var text: String = code_edit.get_line(hit["line"])
	if hit["to"] > text.length():
		return
	var state: Dictionary = {"line": hit["line"], "from": hit["from"], "to": hit["to"]}
	var popup: PopupPanel = PopupPanel.new()
	var picker: ColorPicker = ColorPicker.new()
	picker.color = Color.from_string(text.substr(hit["from"], hit["to"] - hit["from"]).strip_edges().trim_prefix("\"").trim_suffix("\""), Color.WHITE)
	picker.color_changed.connect(_apply_swatch_color.bind(state))
	popup.add_child(picker)
	popup.popup_hide.connect(popup.queue_free)
	EditorInterface.get_base_control().add_child(popup)
	var origin: Vector2 = code_edit.get_screen_position() + hit["rect"].position + Vector2(0, hit["rect"].size.y)
	popup.popup(Rect2i(Vector2i(origin), Vector2i.ZERO))


func _apply_swatch_color(color: Color, state: Dictionary) -> void:
	var line: int = state["line"]
	if line < 0 or line >= code_edit.get_line_count():
		return
	var text: String = code_edit.get_line(line)
	var from: int = state["from"]
	var to: int = state["to"]
	if from < 0 or to > text.length():
		return
	var literal: String = "\"#%s\"" % color.to_html(color.a < 1.0)
	code_edit.set_line(line, text.substr(0, from) + literal + text.substr(to))
	state["to"] = from + literal.length()
