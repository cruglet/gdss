@tool
class_name GdssCompletionHandler
extends Node

@export var editor: CodeEdit
@export_group("Icons")

var gdss_editor: GdssEditor

var _nodes: Array[String] = []
var _properties: Dictionary = {}
var _states: Dictionary = {}
var _property_meta: Dictionary = {}
var _user_variables: Array[String] = []
var _variable_lines: Dictionary = {}
var _methods: Array[GdssMethod] = []
var _last_hover_word: String = ""

var _completion_color: Color
var _hint_panel: PanelContainer
var _hint_label: Label

static var _re_global: RegEx = RegEx.create_from_string(r"@global\s+var\s+(\w+)\s*[:=]")
static var _re_instance: RegEx = RegEx.create_from_string(r"@instance\s+var\s+(\w+)\s*[:=]")
static var _re_local: RegEx = RegEx.create_from_string(r"^var\s+(\w+)\s*[:=]")
static var _re_node_open: RegEx = RegEx.create_from_string(r"^([\w][\w\s,]*)(?::(\w+))?\s*\{")
static var _re_variant_open: RegEx = RegEx.create_from_string(r"^:([\w][\w\s,:]*)?\s*\{")
static var _re_scheme_open: RegEx = RegEx.create_from_string(r"^@scheme\s+(\w+)")
static var _re_meta_open: RegEx = RegEx.create_from_string(r"^@meta\b")

const BUILTIN_COLORS: Array[String] = [
	"RED", "GREEN", "BLUE", "YELLOW", "WHITE", "BLACK",
	"TRANSPARENT", "ORANGE", "PURPLE", "CYAN", "MAGENTA", "GRAY"
]


func _ready() -> void:
	gdss_editor = get_parent() as GdssEditor
	_completion_color = EditorInterface.get_editor_settings().get_setting("text_editor/theme/highlighting/completion_font_color")
	_build_from_objects()
	editor.code_completion_requested.connect(_on_completion_requested)
	editor.text_changed.connect(_on_text_changed)
	editor.symbol_lookup_on_click = true
	editor.symbol_validate.connect(_on_symbol_validate)
	editor.symbol_lookup.connect(_on_symbol_lookup)
	editor.gui_input.connect(_on_editor_gui_input)
	editor.caret_changed.connect(_on_caret_changed)
	editor.focus_exited.connect(_hide_hint)
	editor.get_v_scroll_bar().value_changed.connect(_on_scrolled)
	_parse_user_variables.call_deferred()


func _build_from_objects() -> void:
	_nodes.clear()
	_properties.clear()
	_states.clear()
	_property_meta.clear()
	_methods.clear()

	var prefixes: Array[String] = ["@", ":", "\t", "$"]
	
	for obj: GdssNode in GDSS._get_gdss_nodes().values():
		var style_name: String = obj.style_name
		_nodes.append(style_name)

		var props_dict: Dictionary = {}
		for prop: GdssProp in obj.get_enabled_props():
			props_dict[prop.name] = prop
		_property_meta[style_name] = props_dict
		_properties[style_name] = props_dict.keys()
		_states[style_name] = obj.states

		if style_name.length() > 0 and not prefixes.has(style_name[0]):
			prefixes.append(style_name[0])

		for key: String in props_dict.keys():
			for l: int in range(1, min(4, key.length()) + 1):
				var pre: String = key.substr(0, l)
				if not prefixes.has(pre):
					prefixes.append(pre)

	for method: GdssMethod in GDSS._get_gdss_methods().values():
		_methods.append(method)
		if method.method_name.length() > 0 and not prefixes.has(method.method_name[0]):
			prefixes.append(method.method_name[0])

	editor.code_completion_prefixes = prefixes


func _caret_in_comment() -> bool:
	var line: String = editor.get_line(editor.get_caret_line())
	var col: int = mini(editor.get_caret_column(), line.length())
	var in_quote: bool = false
	var quote_char: String = ""
	for i: int in col:
		var c: String = line[i]
		if in_quote:
			if c == quote_char:
				in_quote = false
		elif c == "\"" or c == "'":
			in_quote = true
			quote_char = c
		elif c == "#":
			return true
	return false


func _on_text_changed() -> void:
	_parse_user_variables()
	if _caret_in_comment():
		editor.cancel_code_completion()
		_hide_hint()
		return
	var word: String = _get_current_word()
	_update_code_hint(word)
	if word.begins_with("$"):
		_update_completions(word)
		editor.request_code_completion(true)
		return
	if word.is_empty():
		var context: Dictionary = _get_context()
		var type: String = context.get("type", "")
		if type == "property_value" or type == "variant_decl" or type == "scheme_block" or type == "meta_block":
			editor.request_code_completion(true)
			return
		editor.cancel_code_completion()
		return
	_update_completions(word)
	editor.request_code_completion(true)


func _on_completion_requested() -> void:
	if _caret_in_comment():
		editor.cancel_code_completion()
		return
	_parse_user_variables()
	var word: String = _get_current_word()
	_update_completions(word)
	_update_code_hint(word)


func _update_code_hint(_word: String) -> void:
	var line: String = editor.get_line(editor.get_caret_line())
	var col: int = mini(editor.get_caret_column(), line.length())
	var paren_pos: int = line.rfind("(", col)
	if paren_pos == -1:
		_hide_hint()
		return
	var before_paren: String = line.substr(0, paren_pos).strip_edges()
	var method_name: String = before_paren.split(" ")[-1].split(":")[-1].strip_edges()
	var method: GdssMethod = GDSS._get_gdss_methods().get(method_name)
	if method == null:
		_hide_hint()
		return
	var inside: String = line.substr(paren_pos + 1, col - paren_pos - 1)
	var depth: int = 0
	var active_param: int = 0
	for i: int in inside.length():
		var c: String = inside[i]
		if c == "(":
			depth += 1
		elif c == ")":
			depth -= 1
		elif c == "," and depth == 0:
			active_param += 1
	_show_hint(method.get_code_hint(active_param))


func _ensure_hint_panel() -> void:
	if _hint_panel != null:
		return
	var theme: Theme = EditorInterface.get_editor_theme()
	_hint_panel = PanelContainer.new()
	_hint_panel.top_level = true
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_panel.visible = false
	if theme.has_stylebox(&"panel", &"TooltipPanel"):
		_hint_panel.add_theme_stylebox_override(&"panel", theme.get_stylebox(&"panel", &"TooltipPanel"))
	else:
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = theme.get_color(&"base_color", &"Editor") if theme.has_color(&"base_color", &"Editor") else Color(0.13, 0.14, 0.17)
		sb.border_color = theme.get_color(&"accent_color", &"Editor") if theme.has_color(&"accent_color", &"Editor") else Color(0.3, 0.3, 0.35)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		sb.set_content_margin_all(6.0)
		_hint_panel.add_theme_stylebox_override(&"panel", sb)
	_hint_label = Label.new()
	_hint_label.add_theme_font_override(&"font", theme.get_font(&"source", &"EditorFonts"))
	_hint_label.add_theme_font_size_override(&"font_size", theme.get_font_size(&"source_size", &"EditorFonts"))
	_hint_label.add_theme_color_override(&"font_color", theme.get_color(&"font_color", &"Editor") if theme.has_color(&"font_color", &"Editor") else Color.WHITE)
	_hint_panel.add_child(_hint_label)
	editor.add_child(_hint_panel)


func _show_hint(text: String) -> void:
	_ensure_hint_panel()
	_hint_label.text = text
	_hint_panel.visible = true
	_hint_panel.reset_size()
	var caret: Vector2 = editor.get_global_position() + editor.get_caret_draw_pos()
	var bounds: Vector2 = editor.get_viewport_rect().size
	var pos: Vector2 = Vector2(caret.x, caret.y + 4.0)
	pos.x = clampf(pos.x, 4.0, maxf(bounds.x - _hint_panel.size.x - 4.0, 4.0))
	pos.y = clampf(pos.y, 4.0, maxf(bounds.y - _hint_panel.size.y - 4.0, 4.0))
	_hint_panel.global_position = pos


func _hide_hint() -> void:
	if _hint_panel != null:
		_hint_panel.visible = false


func _on_caret_changed() -> void:
	_update_code_hint("")


func _on_scrolled(_value: float) -> void:
	if _hint_panel != null and _hint_panel.visible:
		_update_code_hint("")


func _update_completions(word: String) -> void:
	if word.begins_with("$"):
		_complete_values(word, "", "")
		editor.update_code_completion_options(true)
		return
	
	var context: Dictionary = _get_context()
	
	match context.get("type", "top_level"):
		"top_level":
			if ":" in word:
				var parts: PackedStringArray = word.split(":")
				_complete_node_states(parts[0], parts[1] if parts.size() > 1 else "")
			else:
				_complete_nodes(word)
				_complete_at_directives(word)
		"property_key":
			if word.begins_with(":"):
				_complete_states(word.trim_prefix(":"), context.get("style", ""))
			else:
				_complete_properties(word, context.get("style", ""))
		"variant_decl":
			_complete_states(word.trim_prefix(":"), context.get("style", ""))
		"property_value", "property_value_filled":
			_complete_values(word, context.get("style", ""), context.get("property", ""))
		"variant_block":
			_complete_properties(word, context.get("style", ""))
		"scheme_block":
			_complete_scheme_vars(word)
		"meta_block":
			_complete_meta_keys(word)
	
	editor.update_code_completion_options(true)


func _complete_nodes(word: String) -> void:
	for node: String in _nodes:
		if _matches(node, word):
			editor.add_code_completion_option(CodeEdit.KIND_CLASS, node, node, _completion_color, _get_icon(node))


func _complete_node_states(node: String, partial: String) -> void:
	var states: PackedStringArray = _states.get(node, PackedStringArray())
	for v: String in states:
		if partial.is_empty() or v.begins_with(partial):
			editor.add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, v, v + " ", _completion_color, _get_icon(&"Signal"))


func _complete_properties(word: String, style_name: String) -> void:
	var props: Array[String] = []

	if style_name != "" and _properties.has(style_name):
		props.assign(_properties[style_name])
	else:
		for key: String in _properties:
			for p: String in _properties[key]:
				if not props.has(p):
					props.append(p)

	for prop: String in props:
		var meta: Dictionary = _property_meta.get(style_name, {})
		var prop_def: GdssProp = meta.get(prop, null)
		var icon: Texture2D = _get_prop_icon(prop_def)

		if _matches(prop, word):
			editor.add_code_completion_option(CodeEdit.KIND_MEMBER, prop, prop + ": ", _completion_color, icon)

		if prop_def == null or prop_def.type != GDSS.Type.COMPOSITE4:
			continue
		if prop_def.default_value == null or not prop_def.default_value is Vector4i:
			continue
		var v4: Vector4i = prop_def.default_value
		var components: Array[Variant] = [v4.x, v4.y, v4.z, v4.w]

		for idx: int in range(prop_def.composite_of.size()):
			var sub: String = prop_def.composite_of[idx]
			if _matches(sub, word):
				editor.add_code_completion_option(CodeEdit.KIND_MEMBER, sub, sub + ": ", _completion_color, _get_icon(&"int"))


func _complete_states(word: String, style_name: String) -> void:
	var states: PackedStringArray = _states.get(style_name, PackedStringArray())
	
	for v: String in states:
		var display: String = ":" + v
		if word.is_empty() or display.begins_with(word) or v.begins_with(word):
			editor.add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, display, v + " ", _completion_color, _get_icon(&"Signal"))


func _complete_values(word: String, style_name: String, prop: String) -> void:
	if word.begins_with("$"):
		var partial: String = word.substr(1)
		for v: String in _user_variables:
			if v.begins_with("$"):
				var name: String = v.substr(1)
				if partial.is_empty() or name.begins_with(partial):
					editor.add_code_completion_option(CodeEdit.KIND_VARIABLE, v, name +" ", _completion_color, _get_icon(&"LocalVariable"))
		return
	
	var meta: Dictionary = _property_meta.get(style_name, {})
	if meta.is_empty():
		for key: String in _property_meta:
			var m: Dictionary = _property_meta[key]
			if m.has(prop):
				meta = m
				break

	var prop_def: GdssProp = meta.get(prop, null)
	var effective_type: GDSS.Type = GDSS.Type.INT

	if prop_def == null:
		for key: String in meta:
			var raw: Variant = meta[key]
			if not raw is GdssProp:
				continue
			var pd: GdssProp = raw
			if pd.type != GDSS.Type.COMPOSITE4:
				continue
			var raw_default: Variant = pd.default_value
			if not raw_default is Vector4i:
				continue
			var idx: int = pd.composite_of.find(prop)
			if idx == -1:
				continue
			var v4: Vector4i = raw_default
			var components: Array[Variant] = [v4.x, v4.y, v4.z, v4.w]
			if idx < components.size():
				var hint: String = str(components[idx])
				editor.add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, hint, hint, _completion_color, _get_icon(&"MemberProperty"))
			effective_type = GDSS.Type.INT
			break
	else:
		effective_type = prop_def.type

	for method: GdssMethod in _methods:
		if not method.supported_prop_types.has(effective_type):
			continue
		if _matches(method.method_name, word):
			var has_params: bool = method.parameters.size() > 0
			var display: String = method.method_name + ("(…)" if has_params else "()")
			editor.add_code_completion_option(
				CodeEdit.KIND_FUNCTION,
				display,
				method.method_name + "(",
				_completion_color,
				_get_icon(&"MemberMethod")
			)

	if prop_def == null:
		return

	match prop_def.type:
		GDSS.Type.COLOR:
			for c: String in GdssInterpreter.NAMED_COLORS:
				if _matches(c, word):
					editor.add_code_completion_option(CodeEdit.KIND_CONSTANT, c, c, _completion_color, _get_icon(&"Color"))
		GDSS.Type.CURSOR:
			for cursor_key: String in GDSS.CursorType:
				if _matches(cursor_key, word):
					editor.add_code_completion_option(CodeEdit.KIND_ENUM, cursor_key, cursor_key, _completion_color, _get_icon(&"Mouse"))
		GDSS.Type.TRANSITION_TYPE:
			for trans_type: String in GDSS.TransitionType:
				if _matches(trans_type, word):
					editor.add_code_completion_option(CodeEdit.KIND_ENUM, trans_type, trans_type, _completion_color, _get_icon(&"Curve"))
		GDSS.Type.TRANSITION_FUNC:
			for trans_func: String in GDSS.TransitionFunc:
				if _matches(trans_func, word):
					editor.add_code_completion_option(CodeEdit.KIND_ENUM, trans_func, trans_func, _completion_color, _get_icon(&"Curve"))
		GDSS.Type.COMPOSITE4:
			var default: Variant = prop_def.default_value
			if default != null:
				var v4: Vector4i = default
				var hint: String = "%d %d %d %d" % [v4.x, v4.y, v4.z, v4.w]
				editor.add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, hint, hint, _completion_color, _get_icon(&"MemberProperty"))
		GDSS.Type.ICON, GDSS.Type.FONT:
			pass
		_:
			var default: Variant = prop_def.default_value
			if default != null:
				editor.add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, str(default), str(default), _completion_color, _get_icon(&"MemberProperty"))



func _complete_at_directives(word: String) -> void:
	if word.is_empty() or "@global".begins_with(word):
		editor.add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, "@global var", "global var ", _completion_color, _get_icon(&"MemberAnnotation"))
	if word.is_empty() or "@instance".begins_with(word):
		editor.add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, "@instance var", "instance var ", _completion_color, _get_icon(&"MemberAnnotation"))
	if word.is_empty() or "@scheme".begins_with(word):
		editor.add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, "@scheme", "scheme ", _completion_color, _get_icon(&"MemberAnnotation"))
	if word.is_empty() or "@meta".begins_with(word):
		editor.add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, "@meta", "meta {", _completion_color, _get_icon(&"MemberAnnotation"))
	if word.is_empty() or "@import".begins_with(word):
		editor.add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, "@import", "import \"", _completion_color, _get_icon(&"MemberAnnotation"))


func _get_prop_icon(prop_def: GdssProp) -> Texture2D:
	if prop_def == null:
		return _get_icon(&"MemberProperty")
	match prop_def.type:
		GDSS.Type.COLOR:
			return _get_icon(&"Color")
		GDSS.Type.INT:
			return _get_icon(&"int")
		GDSS.Type.FLOAT:
			return _get_icon(&"float")
		GDSS.Type.BOOLEAN:
			return _get_icon(&"bool")
		GDSS.Type.COMPOSITE4:
			return _get_icon(&"Vector4i")
		GDSS.Type.CURSOR:
			return _get_icon(&"Mouse")
		GDSS.Type.TRANSITION_TYPE, GDSS.Type.TRANSITION_FUNC:
			return _get_icon(&"Animation")
		GDSS.Type.ICON:
			return _get_icon(&"ImageTexture")
		_:
			return _get_icon(&"MemberProperty")


func _get_context() -> Dictionary:
	var annotation: String = _annotation_block_context()
	if annotation == "scheme":
		return {"type": "scheme_block"}
	if annotation == "meta":
		return {"type": "meta_block"}
	var caret_line: int = editor.get_caret_line()
	var lines: PackedStringArray = editor.text.split("\n")
	
	var stack: Array[Dictionary] = []

	for i: int in range(caret_line):
		var line: String = lines[i].strip_edges()
		var comment_idx: int = line.find("#")
		if comment_idx != -1:
			line = line.substr(0, comment_idx).strip_edges()
		if line.is_empty():
			continue

		var m: RegExMatch = _re_node_open.search(line)
		if m:
			var raw_selector: String = m.get_string(1)
			var first_selector: String = raw_selector.split(",")[0].strip_edges()
			stack.push_back({
				"style": first_selector,
				"variant": m.get_string(2),
				"in_variant": m.get_string(2) != ""
			})
			continue

		var vm: RegExMatch = _re_variant_open.search(line)
		if vm:
			var raw_variant: String = vm.get_string(1)
			var first_variant: String = raw_variant.split(",")[0].strip_edges().trim_prefix(":")
			var top: Dictionary = stack.back() if stack.size() > 0 else {}
			stack.push_back({
				"style": top.get("style", ""),
				"variant": first_variant,
				"in_variant": true
			})
			continue

		if "}" in line:
			if stack.size() > 0:
				stack.pop_back()
	
	var caret_text: String = lines[caret_line] if caret_line < lines.size() else ""
	var stripped: String = caret_text.strip_edges()
	var comment_idx: int = stripped.find("#")
	if comment_idx != -1:
		stripped = stripped.substr(0, comment_idx).strip_edges()
	
	if stack.is_empty():
		return {"type": "top_level"}
	
	var current: Dictionary = stack.back()
	var current_style: String = current.get("style", "")
	var current_variant: String = current.get("variant", "")
	var in_variant_block: bool = current.get("in_variant", false)
	
	if not _property_meta.has(current_style):
		for idx: int in range(stack.size() - 1, -1, -1):
			var s: String = stack[idx].get("style", "")
			if _property_meta.has(s):
				current_style = s
				break
	
	if stripped.begins_with(":"):
		return {
			"type": "variant_decl",
			"style": current_style,
			"variant": current_variant
		}
	
	var colon_pos: int = _first_separator(stripped)
	if colon_pos != -1:
		var value_part: String = stripped.substr(colon_pos + 1).strip_edges()
		if not value_part.is_empty():
			return {
				"type": "property_value_filled",
				"style": current_style,
				"variant": current_variant,
				"property": stripped.substr(0, colon_pos).strip_edges()
			}
		return {
			"type": "property_value",
			"style": current_style,
			"variant": current_variant,
			"property": stripped.substr(0, colon_pos).strip_edges()
		}
	
	return {
		"type": "variant_block" if in_variant_block else "property_key",
		"style": current_style,
		"variant": current_variant
	}


func _parse_user_variables() -> void:
	_user_variables.clear()
	_variable_lines.clear()
	var source: String = gdss_editor.get_full_source() if gdss_editor != null else editor.text
	var lines: PackedStringArray = source.split("\n")
	for line_number: int in lines.size():
		var stripped: String = lines[line_number].strip_edges()
		var gm: RegExMatch = _re_global.search(stripped)
		if gm:
			_record_variable(gm.get_string(1), line_number)
			continue
		var im: RegExMatch = _re_instance.search(stripped)
		if im:
			_record_variable(im.get_string(1), line_number)
			continue
		var lm: RegExMatch = _re_local.search(stripped)
		if lm:
			_record_variable(lm.get_string(1), line_number)


func _record_variable(var_name: String, line_number: int) -> void:
	_user_variables.append("$" + var_name)
	_variable_lines[var_name] = line_number


func _on_symbol_validate(symbol: String) -> void:
	_parse_user_variables()
	editor.set_symbol_lookup_word_as_valid(_variable_lines.has(symbol.trim_prefix("$")))


func _on_symbol_lookup(symbol: String, _line: int, _column: int) -> void:
	var var_name: String = symbol.trim_prefix("$")
	if not _variable_lines.has(var_name):
		return
	var target: int = _variable_lines[var_name]
	if gdss_editor != null:
		gdss_editor.goto_full_source_line(target)
		return
	editor.set_caret_line(target)
	editor.set_caret_column(editor.get_line(target).length())
	editor.center_viewport_to_caret()


func _on_editor_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseMotion:
		return
	var at: Vector2i = editor.get_line_column_at_pos((event as InputEventMouseMotion).position)
	var word: String = _word_at(at.y, at.x)
	if word == _last_hover_word:
		return
	_last_hover_word = word
	editor.tooltip_text = _hover_doc(word)


func _word_at(line: int, column: int) -> String:
	if line < 0 or line >= editor.get_line_count():
		return ""
	var text: String = editor.get_line(line)
	if column < 0 or column > text.length():
		return ""
	var start: int = column
	while start > 0 and _is_identifier_char(text[start - 1]):
		start -= 1
	var end: int = column
	while end < text.length() and _is_identifier_char(text[end]):
		end += 1
	return text.substr(start, end - start)


func _hover_doc(word: String) -> String:
	if word.is_empty():
		return ""
	var method: GdssMethod = GDSS._get_gdss_methods().get(word)
	if method != null:
		return method.get_code_hint()
	for style_name: String in _property_meta:
		var meta: Dictionary = _property_meta[style_name]
		if meta.has(word):
			var prop: GdssProp = meta[word]
			return "%s: %s" % [word, GDSS.Type.keys()[prop.type].to_lower()]
	return ""


func _is_identifier_char(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_"


func _get_current_word() -> String:
	var line: String = editor.get_line(editor.get_caret_line())
	var col: int = editor.get_caret_column()
	var word: String = ""

	for i: int in range(col - 1, -1, -1):
		var c: String = line[i]
		if c == " " or c == "\t" or c in ["{", "}", "\n", ","]:
			break
		if c == "=":
			break
		if c == "$":
			word = c + word
			break
		if c == ":" and word.length() > 0 and not word.begins_with(":"):
			var before_colon: String = line.substr(0, i).strip_edges()
			var last_char: String = before_colon[before_colon.length() - 1] if before_colon.length() > 0 else ""
			var last_is_word: bool = (last_char >= "a" and last_char <= "z") or (last_char >= "A" and last_char <= "Z") or last_char == "_"
			if last_is_word:
				word = c + word
				continue
			break
		word = c + word

	return word


func _matches(candidate: String, word: String) -> bool:
	return word.is_empty() or candidate.to_lower().contains(word.to_lower())


func _get_icon(icon_name: StringName) -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon(icon_name, &"EditorIcons")


func _first_separator(s: String) -> int:
	var in_quote: bool = false
	var quote_char: String = ""
	for i: int in s.length():
		var c: String = s[i]
		if in_quote:
			if c == quote_char:
				in_quote = false
		elif c == "\"" or c == "'":
			in_quote = true
			quote_char = c
		elif c == ":" or c == "=":
			return i
	return -1


func _annotation_block_context() -> String:
	var caret: int = editor.get_caret_line()
	var lines: PackedStringArray = editor.text.split("\n")
	var depth: int = 0
	var kind: String = ""
	for i: int in mini(caret + 1, lines.size()):
		var stripped: String = _strip_comment(lines[i]).strip_edges()
		if depth == 0:
			if _re_scheme_open.search(stripped) != null and stripped.contains("{"):
				kind = "scheme"
				depth += _brace_count(stripped)
			elif _re_meta_open.search(stripped) != null and stripped.contains("{"):
				kind = "meta"
				depth += _brace_count(stripped)
		else:
			depth += _brace_count(stripped)
			if depth <= 0:
				kind = ""
	return kind if depth > 0 else ""


func _brace_count(s: String) -> int:
	var depth: int = 0
	var in_quote: bool = false
	var quote_char: String = ""
	for c: String in s:
		if in_quote:
			if c == quote_char:
				in_quote = false
		elif c == "\"" or c == "'":
			in_quote = true
			quote_char = c
		elif c == "{":
			depth += 1
		elif c == "}":
			depth -= 1
	return depth


func _strip_comment(line: String) -> String:
	var in_quote: bool = false
	var quote_char: String = ""
	for i: int in line.length():
		var c: String = line[i]
		if in_quote:
			if c == quote_char:
				in_quote = false
		elif c == "\"" or c == "'":
			in_quote = true
			quote_char = c
		elif c == "#":
			return line.substr(0, i)
	return line


func _complete_scheme_vars(word: String) -> void:
	var names: Array[String] = []
	for key: String in GdssInterpreter._global_defaults:
		if not names.has(key):
			names.append(key)
	for key: String in GdssInterpreter._instance_scheme_base:
		if not names.has(key):
			names.append(key)
	for name: String in names:
		if word.is_empty() or name.begins_with(word):
			editor.add_code_completion_option(CodeEdit.KIND_VARIABLE, name, name + ": ", _completion_color, _get_icon(&"LocalVariable"))


func _complete_meta_keys(word: String) -> void:
	for key: String in ["name", "description", "author", "version", "default_scheme"]:
		if word.is_empty() or key.begins_with(word):
			editor.add_code_completion_option(CodeEdit.KIND_MEMBER, key, key + ": ", _completion_color, _get_icon(&"MemberProperty"))
