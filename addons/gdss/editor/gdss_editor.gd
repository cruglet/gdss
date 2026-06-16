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

var _chunk_tabs: TabBar
var _chunks: Array[Dictionary] = []
var _active_chunk: int = 0
var _chunk_offsets: PackedInt32Array = []
var _error_target_chunk: int = 0
var _error_target_line: int = 0
var _error_bg: Color = Color.RED
var _all_errors: Array = []
var _highlighted_lines: PackedInt32Array = []
var _search_bar: HBoxContainer
var _search_field: LineEdit
var _search_label: Label

var file_name: String:
	get():
		return GdssStorage.get_save_path().get_file()


func _ready() -> void:
	initial_font_size = code_edit.get_theme_font_size(&"font_size")
	font_size = initial_font_size
	font_min = initial_font_size * 0.5
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
	
	copy_button.icon = EditorInterface.get_editor_theme().get_icon(&"ActionCopy", &"EditorIcons")
	
	if not ProjectSettings.has_setting("gdss/editor/use_minimap"):
		ProjectSettings.set_setting("gdss/editor/use_minimap", true)
	
	toggle_map_button.button_pressed = ProjectSettings.get_setting("gdss/editor/use_minimap")
	
	title_label.text = file_name
	code_edit.gui_input.connect(_on_code_edit_input)
	code_edit.caret_changed.connect(_on_code_edit_caret_changed)
	_setup_outline_toggle()
	_setup_location_toggle()
	_setup_chunk_tabs()
	_setup_search()
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
	_chunk_tabs.clear_tabs()
	for chunk: Dictionary in _chunks:
		_chunk_tabs.add_tab(str(chunk["name"]))
	if _active_chunk >= 0 and _active_chunk < _chunks.size():
		_chunk_tabs.current_tab = _active_chunk


func _on_chunk_selected(idx: int) -> void:
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
	_sync_active_chunk()
	_chunks.append({"name": _unique_chunk_name("chunk"), "content": ""})
	_active_chunk = _chunks.size() - 1
	code_edit.text = ""
	_rebuild_chunk_tabs()
	code_edit.text_changed.emit()
	GdssInterpreter.get_instance().save_current()


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
			GdssInterpreter.get_instance().save_current()
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


func show_error(message: String, line_num: int, total_errors: int = 1) -> void:
	if line_num == -1:
		error_label.text = ""
		error_label.tooltip_text = ""
		error_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		copy_button.disabled = true
		return

	var more_suffix: String = "  (+%d more)" % (total_errors - 1) if total_errors > 1 else ""
	error_label.text = "[%s]: %s%s" % [line_num + 1, message, more_suffix]
	error_label.tooltip_text = error_label.text
	err_line_num = line_num
	error_label.mouse_filter = Control.MOUSE_FILTER_STOP
	copy_button.disabled = false


func _on_code_edit_input(event: InputEvent) -> void:
	if event is InputEventMagnifyGesture:
		font_size += (event.factor - 1) * 5
		font_size = clamp(font_size, font_min, font_max)
	elif event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key == null or not key.pressed:
			return
		if key.keycode == KEY_EQUAL and key.is_command_or_control_pressed():
			font_size += 4
		if key.keycode == KEY_MINUS and key.is_command_or_control_pressed():
			font_size -= 4
		if key.keycode == KEY_S and key.is_command_or_control_pressed():
			EditorInterface.save_scene()
			GdssInterpreter.get_instance().save_current()
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
			_open_search()
			code_edit.get_viewport().set_input_as_handled()
	else:
		return
	code_edit.add_theme_font_size_override(&"font_size", int(font_size))
	zoom_percentage.text = "%s%%" % int((font_size / initial_font_size) * 100)


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
	_search_bar = HBoxContainer.new()
	_search_bar.visible = false
	_search_field = LineEdit.new()
	_search_field.placeholder_text = "Find…"
	_search_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_bar.add_child(_search_field)
	_search_label = Label.new()
	_search_bar.add_child(_search_label)
	var prev_button: Button = Button.new()
	prev_button.text = "<"
	prev_button.flat = true
	_search_bar.add_child(prev_button)
	var next_button: Button = Button.new()
	next_button.text = ">"
	next_button.flat = true
	_search_bar.add_child(next_button)
	var close_button: Button = Button.new()
	close_button.text = "✕"
	close_button.flat = true
	_search_bar.add_child(close_button)
	var inner_box: Node = split.get_parent()
	inner_box.add_child(_search_bar)
	inner_box.move_child(_search_bar, 0)
	_search_field.text_changed.connect(func(_text: String) -> void: _step_search(0))
	_search_field.text_submitted.connect(func(_text: String) -> void: _step_search(1))
	prev_button.pressed.connect(_step_search.bind(-1))
	next_button.pressed.connect(_step_search.bind(1))
	close_button.pressed.connect(_close_search)
	_search_field.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
			_close_search()
	)


func _open_search() -> void:
	if _search_bar == null:
		return
	_search_bar.visible = true
	if code_edit.has_selection():
		_search_field.text = code_edit.get_selected_text()
	_search_field.grab_focus()
	_search_field.select_all()
	_step_search(0)


func _close_search() -> void:
	if _search_bar != null:
		_search_bar.visible = false
	code_edit.grab_focus()


func _step_search(direction: int) -> void:
	var needle: String = _search_field.text
	if needle.is_empty():
		_search_label.text = ""
		return
	var flags: int = TextEdit.SEARCH_BACKWARDS if direction < 0 else 0
	var from_line: int = code_edit.get_caret_line()
	var from_column: int = code_edit.get_caret_column() + (1 if direction > 0 else 0)
	var result: Vector2i = code_edit.search(needle, flags, from_line, from_column)
	if result.x == -1:
		var wrap_line: int = code_edit.get_line_count() - 1 if direction < 0 else 0
		var wrap_column: int = code_edit.get_line(wrap_line).length() if direction < 0 else 0
		result = code_edit.search(needle, flags, wrap_line, wrap_column)
	if result.x == -1:
		_search_label.text = "0/0"
		return
	code_edit.set_caret_line(result.y)
	code_edit.set_caret_column(result.x)
	code_edit.select(result.y, result.x, result.y, result.x + needle.length())
	code_edit.center_viewport_to_caret()
	_search_label.text = "%d found" % _count_matches(needle)


func _count_matches(needle: String) -> int:
	var count: int = 0
	var result: Vector2i = code_edit.search(needle, 0, 0, 0)
	while result.x != -1 and count < 9999:
		count += 1
		var next_column: int = result.x + needle.length()
		var line: int = result.y
		if next_column > code_edit.get_line(line).length():
			line += 1
			next_column = 0
			if line >= code_edit.get_line_count():
				break
		result = code_edit.search(needle, 0, line, next_column)
	return count


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
	_user_saved()


func _prompt_save() -> void:
	if _suppress_dirty or _has_unsaved_changes:
		return
	_has_unsaved_changes = true
	title_label.text = file_name + "(*)"


func _clear_suppress_dirty() -> void:
	_suppress_dirty = false


func _user_saved() -> void:
	_has_unsaved_changes = false
	title_label.text = file_name


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
	font_size = initial_font_size
	code_edit.add_theme_font_size_override("font_size", initial_font_size)
	zoom_percentage.text = "100%"
	
