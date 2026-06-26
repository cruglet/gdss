@tool
class_name GdssOutline
extends VBoxContainer

@export var code_edit: CodeEdit

var _search: LineEdit
var _tree: Tree
var _filter: String = ""
var _rebuilding: bool = false
var _rebuild_queued: bool = false
var _state_icon: Texture2D
var _fallback_icon: Texture2D
var _event_icon: Texture2D
var _scheme_icon: Texture2D
var _white_icon_cache: Dictionary = {}


func _ready() -> void:
	if code_edit == null:
		return
	_load_icons()
	_search = LineEdit.new()
	_search.placeholder_text = "Filter outline…"
	_search.clear_button_enabled = true
	_search.right_icon = _get_icon(&"Search")
	add_child(_search)
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.scroll_horizontal_enabled = false
	_tree.allow_rmb_select = false
	_tree.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(_tree)
	_search.text_changed.connect(_on_filter_changed)
	_tree.item_selected.connect(_jump_to_selected)
	code_edit.text_changed.connect(_queue_rebuild)
	var interpreter: GdssInterpreter = GdssInterpreter.get_instance()
	if interpreter != null:
		interpreter.parsed_changed.connect(_queue_rebuild)
	_rebuild()


func _load_icons() -> void:
	_state_icon = _get_icon(&"Signal")
	_fallback_icon = _get_icon(&"Theme")
	_event_icon = _get_icon(&"Slot")
	_scheme_icon = _get_icon(&"BlitMaterial")


func _queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_queued = false
	_rebuilding = true
	_tree.clear()
	var open_blocks: Array[TreeItem] = [_tree.create_item()]
	var base_selectors: Array[String] = [""]
	var lines: PackedStringArray = code_edit.text.split("\n")
	for line_number: int in lines.size():
		var content: String = _without_comment(lines[line_number]).strip_edges()
		if content.ends_with("{"):
			var label: String = content.trim_suffix("{").strip_edges()
			var depth: int = open_blocks.size()
			var base_selector: String = label if depth <= 1 else base_selectors.back()
			var item: TreeItem = _tree.create_item(open_blocks.back())
			item.set_text(0, label)
			item.set_metadata(0, line_number)
			_decorate(item, label, depth, base_selector)
			open_blocks.push_back(item)
			base_selectors.push_back(base_selector)
		elif content.begins_with("}") and open_blocks.size() > 1:
			open_blocks.pop_back()
			base_selectors.pop_back()
	_rebuilding = false
	_refilter()


func _decorate(item: TreeItem, label: String, depth: int, base_selector: String) -> void:
	if label.begins_with(":"):
		item.set_icon(0, _state_icon)
		return
	if label.contains("("):
		item.set_icon(0, _event_icon)
		return
	if label.begins_with("@scheme"):
		item.set_icon(0, _scheme_icon)
		return
	if depth <= 1:
		item.set_icon(0, _selector_icon(label))
		return
	item.set_icon(0, _white_subclass_icon(base_selector))


func _selector_icon(label: String) -> Texture2D:
	var first_selector: String = label.split(",")[0].strip_edges()
	var editor_theme: Theme = EditorInterface.get_editor_theme()
	if editor_theme.has_icon(first_selector, &"EditorIcons"):
		return editor_theme.get_icon(first_selector, &"EditorIcons")
	return _fallback_icon


func _white_subclass_icon(base_selector: String) -> Texture2D:
	if _white_icon_cache.has(base_selector):
		return _white_icon_cache[base_selector]
	var white: Texture2D = _to_white(_selector_icon(base_selector))
	_white_icon_cache[base_selector] = white
	return white


func _to_white(source: Texture2D) -> Texture2D:
	if source == null:
		return null
	var image: Image = source.get_image()
	if image == null:
		return source
	image = image.duplicate()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	for y: int in image.get_height():
		for x: int in image.get_width():
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, image.get_pixel(x, y).a))
	return ImageTexture.create_from_image(image)


func _on_filter_changed(text: String) -> void:
	_filter = text.strip_edges().to_lower()
	_refilter()


func _refilter() -> void:
	var child: TreeItem = _tree.get_root().get_first_child()
	while child != null:
		_filter_item(child, false)
		child = child.get_next()


func _filter_item(item: TreeItem, ancestor_match: bool) -> bool:
	var self_match: bool = _filter.is_empty() or item.get_text(0).to_lower().contains(_filter)
	var keep_subtree: bool = ancestor_match or self_match
	var descendant_match: bool = false
	var child: TreeItem = item.get_first_child()
	while child != null:
		if _filter_item(child, keep_subtree):
			descendant_match = true
		child = child.get_next()
	item.visible = keep_subtree or descendant_match
	return self_match or descendant_match


func _jump_to_selected() -> void:
	if _rebuilding:
		return
	var item: TreeItem = _tree.get_selected()
	if item == null:
		return
	var line: int = item.get_metadata(0)
	code_edit.set_caret_line(line)
	code_edit.set_caret_column(code_edit.get_line(line).length())
	code_edit.center_viewport_to_caret()
	code_edit.grab_focus()


func _without_comment(line: String) -> String:
	var comment_start: int = line.find("#")
	return line if comment_start == -1 else line.substr(0, comment_start)


func _get_icon(icon_name: StringName) -> Texture2D:
	var editor_theme: Theme = EditorInterface.get_editor_theme()
	if editor_theme.has_icon(icon_name, &"EditorIcons"):
		return editor_theme.get_icon(icon_name, &"EditorIcons")
	return null
