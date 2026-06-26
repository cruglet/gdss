@tool
class_name GdssHighlightHandler
extends Node

@export var editor: CodeEdit
@export var interpreter: GdssInterpreter

var gdss_editor: GdssEditor

static var _re_global: RegEx = RegEx.create_from_string(r"@global\s+var\s+(\w+)\s*[:=]")
static var _re_instance: RegEx = RegEx.create_from_string(r"@instance\s+var\s+(\w+)\s*[:=]")
static var _re_local: RegEx = RegEx.create_from_string(r"(?:^|\s)var\s+(\w+)\s*[:=]")

var _highlighter: GdssCodeHighlighter
var _nodes: Array[String] = []
var _properties: Array[String] = []
var _states: Array[String] = []
var _property_meta: Dictionary = {}
var _global_variables: Array[String] = []
var _local_variables: Array[String] = []
var _instance_variables: Array[String] = []
var _builtin_colors: Array[String] = [
	"RED", "GREEN", "BLUE", "YELLOW", "WHITE", "BLACK",
	"TRANSPARENT", "ORANGE", "PURPLE", "CYAN", "MAGENTA", "GRAY"
]
var _value_functions: Array[String] = []
var _enum_values: Array[String] = []


func _ready() -> void:
	gdss_editor = get_parent() as GdssEditor
	_build_from_objects()
	_setup_highlighter()
	_parse_user_variables.call_deferred()
	editor.text_changed.connect(_on_text_changed)


func _build_from_objects() -> void:
	_nodes.clear()
	_properties.clear()
	_states.clear()
	_property_meta.clear()
	_value_functions.clear()
	_enum_values.clear()
	_builtin_colors.assign(GdssInterpreter.NAMED_COLORS)
	
	for key: String in GDSS.TransitionType:
		_enum_values.append(key)
	for key: String in GDSS.TransitionFunc:
		if not _enum_values.has(key):
			_enum_values.append(key)
	for key: String in GDSS.CursorType:
		if not _enum_values.has(key):
			_enum_values.append(key)
	
	for obj: GdssNode in GDSS._get_gdss_nodes().values():
		var style_name: String = obj.style_name
		if not _nodes.has(style_name):
			_nodes.append(style_name)

		var props_dict: Dictionary = {}
		for prop: GdssProp in obj.get_enabled_props():
			props_dict[prop.name] = prop
			if not _properties.has(prop.name):
				_properties.append(prop.name)
			for sub: String in prop.composite_of:
				if not _properties.has(sub):
					_properties.append(sub)

		_property_meta[style_name] = props_dict

		for v: String in obj.states:
			if not _states.has(v):
				_states.append(v)

	for method: GdssMethod in GDSS._get_gdss_methods().values():
		if not _value_functions.has(method.method_name):
			_value_functions.append(method.method_name)
	if not _value_functions.has("calc"):
		_value_functions.append("calc")


func _setup_highlighter() -> void:
	_highlighter = GdssCodeHighlighter.new()
	_highlighter.nodes = _nodes
	_highlighter.properties = _properties
	_highlighter.states = _states
	_highlighter.property_meta = _property_meta
	_highlighter.builtin_colors = _builtin_colors
	_highlighter.value_functions = _value_functions
	_highlighter.global_variables = _global_variables
	_highlighter.local_variables = _local_variables
	_highlighter.instance_variables = _instance_variables
	_highlighter.enum_values = _enum_values
	_highlighter._node_states = {}
	for obj: GdssNode in GDSS._get_gdss_nodes().values():
		_highlighter._node_states[obj.style_name] = obj.states
	_highlighter.refresh_colors()
	editor.syntax_highlighter = _highlighter
	_highlighter.clear_highlighting_cache()


class GdssCodeHighlighter extends SyntaxHighlighter:
	var nodes: Array[String] = []
	var properties: Array[String] = []
	var states: Array[String] = []
	var property_meta: Dictionary = {}
	var builtin_colors: Array[String] = []
	var _node_states: Dictionary = {}
	var _brace_depth_cache: Array[int] = []
	var _cache_dirty: bool = true
	var value_functions: Array[String] = []
	var col_variable: Color
	var col_function: Color
	var col_event: Color
	var global_variables: Array[String] = []
	var local_variables: Array[String] = []
	var instance_variables: Array[String] = []
	var enum_values: Array[String] = []

	var col_keyword: Color
	var col_type: Color
	var col_user_type: Color
	var col_symbol: Color
	var col_number: Color
	var col_annotation: Color
	var col_comment: Color
	var col_control_flow: Color
	var col_string: Color
	var col_member: Color
	var col_brace_mismatch: Color
	var col_const: Color
	var col_default: Color
	var col_global: Color
	var col_instance: Color
	var col_critical: Color
	var col_warning: Color
	var col_notice: Color
	var _critical_markers: PackedStringArray = []
	var _warning_markers: PackedStringArray = []
	var _notice_markers: PackedStringArray = []


	func refresh_colors() -> void:
		var s: EditorSettings = EditorInterface.get_editor_settings()
		col_keyword = s.get_setting("text_editor/theme/highlighting/keyword_color")
		col_type = s.get_setting("text_editor/theme/highlighting/engine_type_color")
		col_user_type = s.get_setting("text_editor/theme/highlighting/user_type_color")
		col_symbol = s.get_setting("text_editor/theme/highlighting/symbol_color")
		col_number = s.get_setting("text_editor/theme/highlighting/number_color")
		col_annotation = s.get_setting("text_editor/theme/highlighting/gdscript/annotation_color")
		col_comment = s.get_setting("text_editor/theme/highlighting/comment_color")
		col_control_flow = s.get_setting("text_editor/theme/highlighting/control_flow_keyword_color")
		col_string = s.get_setting("text_editor/theme/highlighting/string_color")
		col_member = s.get_setting("text_editor/theme/highlighting/member_variable_color")
		col_brace_mismatch = s.get_setting("text_editor/theme/highlighting/brace_mismatch_color")
		col_const = s.get_setting("text_editor/theme/highlighting/gdscript/string_name_color")
		col_default = s.get_setting("text_editor/theme/highlighting/text_color")
		col_function = s.get_setting("text_editor/theme/highlighting/gdscript/global_function_color")
		col_variable = s.get_setting("text_editor/theme/highlighting/function_color")
		col_event = s.get_setting("text_editor/theme/highlighting/function_color")
		col_global = s.get_setting("text_editor/theme/highlighting/string_placeholder_color")
		col_instance = s.get_setting("text_editor/theme/highlighting/string_placeholder_color")
		col_critical = _get_marker_color(s, "critical_color")
		col_warning = _get_marker_color(s, "warning_color")
		col_notice = _get_marker_color(s, "notice_color")
		_critical_markers = _get_marker_list(s, "critical_list")
		_warning_markers = _get_marker_list(s, "warning_list")
		_notice_markers = _get_marker_list(s, "notice_list")


	func _get_marker_color(s: EditorSettings, key: String) -> Color:
		var path: String = "text_editor/theme/highlighting/comment_markers/" + key
		return s.get_setting(path) if s.has_setting(path) else col_comment


	func _get_marker_list(s: EditorSettings, key: String) -> PackedStringArray:
		var path: String = "text_editor/theme/highlighting/comment_markers/" + key
		var result: PackedStringArray = []
		if not s.has_setting(path):
			return result
		for entry: String in str(s.get_setting(path)).split(",", false):
			var trimmed: String = entry.strip_edges()
			if not trimmed.is_empty():
				result.append(trimmed)
		return result


	func _marker_color_for(word: String) -> Variant:
		if _critical_markers.has(word):
			return col_critical
		if _warning_markers.has(word):
			return col_warning
		if _notice_markers.has(word):
			return col_notice
		return null


	func _highlight_comment_markers(text: String, start: int, result: Dictionary) -> void:
		var n: int = text.length()
		var i: int = start
		while i < n:
			if not _is_word_char(text[i]):
				i += 1
				continue
			var word_start: int = i
			while i < n and _is_word_char(text[i]):
				i += 1
			var marker_color: Variant = _marker_color_for(text.substr(word_start, i - word_start))
			if marker_color != null:
				result[word_start] = {"color": marker_color}
				if i < n:
					result[i] = {"color": col_comment}


	func invalidate_cache() -> void:
		_cache_dirty = true


	func _is_word_char(c: String) -> bool:
		var code: int = c.unicode_at(0)
		return (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95


	func _node_has_state(node_name: String, state: String) -> bool:
		if _node_states.has(node_name):
			var v: PackedStringArray = _node_states[node_name]
			return v.has(state)
		return false


	func _get_line_syntax_highlighting(p_line: int) -> Dictionary:
		var result: Dictionary = {}
		var text: String = get_text_edit().get_line(p_line)
		var line_length: int = text.length()

		var total_lines: int = get_text_edit().get_line_count()

		if _cache_dirty or _brace_depth_cache.size() != total_lines:
			_rebuild_brace_cache()
			_cache_dirty = false

		var brace_depth: int = _brace_depth_cache[p_line] if p_line < _brace_depth_cache.size() else 0

		if line_length == 0:
			return result

		var i: int = 0
		while i < line_length:
			var c: String = text[i]

			if c == "#":
				result[i] = {"color": col_comment}
				_highlight_comment_markers(text, i, result)
				break

			if c == "\"":
				result[i] = {"color": col_string}
				var j: int = i + 1
				while j < line_length and text[j] != "\"":
					j += 1
				result[j] = {"color": col_string}
				i = j + 1
				continue
			
			if c == "$":
				var start: int = i
				i += 1
				while i < line_length and _is_word_char(text[i]):
					i += 1
				var var_name: String = text.substr(start + 1, i - start - 1)
				if global_variables.has(var_name):
					result[start] = {"color": col_global}
				elif instance_variables.has(var_name):
					result[start] = {"color": col_instance}
				elif local_variables.has(var_name):
					result[start] = {"color": col_variable}
				else:
					result[start] = {"color": col_default}
				continue
			
			if c == "@":
				var start: int = i
				i += 1
				while i < line_length:
					var next_char: String = text[i]
					var is_word_char: bool = (next_char >= "a" and next_char <= "z") or (next_char >= "A" and next_char <= "Z") or next_char == "_"
					if not is_word_char:
						break
					i += 1
				result[start] = {"color": col_annotation}
				continue

			if c == "{":
				result[i] = {"color": col_symbol if brace_depth >= 0 else col_brace_mismatch}
				brace_depth += 1
				i += 1
				continue

			if c == "}":
				brace_depth -= 1
				result[i] = {"color": col_symbol if brace_depth >= 0 else col_brace_mismatch}
				i += 1
				continue

			if c in ["(", ")", "[", "]"]:
				result[i] = {"color": col_symbol}
				i += 1
				continue

			if c in [":", ",", "="]:
				result[i] = {"color": col_symbol}
				i += 1
				continue

			if c == ";":
				result[i] = {"color": col_default}
				i += 1
				continue

			if c == "+" or c == "*" or c == "/":
				result[i] = {"color": col_symbol}
				i += 1
				continue

			if c.is_valid_int() or (c == "-" and i + 1 < line_length and text[i + 1].is_valid_int()):
				var start: int = i
				i += 1
				while i < line_length and (text[i].is_valid_int() or text[i] == "."):
					i += 1
				result[start] = {"color": col_number}
				continue

			var is_letter: bool = (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"
			if is_letter:
				var start: int = i
				i += 1
				while i < line_length:
					var next_char: String = text[i]
					var is_word_char: bool = (next_char >= "a" and next_char <= "z") or (next_char >= "A" and next_char <= "Z") or next_char == "_" or (next_char >= "0" and next_char <= "9")
					if not is_word_char:
						break
					i += 1
				if i == start:
					i += 1
					continue
				var word: String = text.substr(start, i - start)
				var before_full: String = text.substr(0, start)
				var semi: int = before_full.rfind(";")
				var before: String = before_full.substr(semi + 1) if semi != -1 else before_full
				var trimmed_before: String = before.rstrip(" \t")
				var is_after_colon: bool = trimmed_before.ends_with(":") and before.length() == trimmed_before.length()
				var after: String = text.substr(i).strip_edges()
				var is_before_brace: bool = after.begins_with("{") or (after.begins_with(":") and after.find("{") != -1)
				var colon_idx: int = maxi(trimmed_before.rfind(":"), trimmed_before.rfind("="))
				var brace_idx: int = trimmed_before.rfind("{")
				var in_value: bool = colon_idx != -1 and colon_idx > brace_idx and not is_after_colon

				if word == "pass":
					result[start] = {"color": col_control_flow}
				elif is_after_colon and states.has(word):
					var before_colon: String = trimmed_before.substr(0, trimmed_before.length() - 1).strip_edges()
					var valid: bool = false
					if brace_depth > 0:
						for style_name: String in _node_states:
							if _node_has_state(style_name, word):
								valid = true
								break
					else:
						valid = _node_has_state(before_colon, word)
					result[start] = {"color": col_control_flow if valid else col_default}
				elif nodes.has(word):
					result[start] = {"color": col_type}
				elif after.begins_with("(") and after.rfind("{") > after.rfind(")"):
					result[start] = {"color": col_event}
				elif is_before_brace:
					result[start] = {"color": col_user_type}
				elif in_value:
					if value_functions.has(word):
						result[start] = {"color": col_function}
					elif word.to_lower() == "true" or word.to_lower() == "false":
						result[start] = {"color": col_keyword}
					elif builtin_colors.has(word):
						result[start] = {"color": col_const}
					elif enum_values.has(word):
						result[start] = {"color": col_const}
					else:
						result[start] = {"color": col_default}
				elif word == "var":
					result[start] = {"color": col_keyword}
				elif word == "true" or word == "false":
					result[start] = {"color": col_keyword}
				elif properties.has(word):
					result[start] = {"color": col_member}
				else:
					result[start] = {"color": col_default}
				continue

			i += 1

		return result


	func _rebuild_brace_cache() -> void:
		var total_lines: int = get_text_edit().get_line_count()
		_brace_depth_cache.resize(total_lines)
		_brace_depth_cache.fill(0)
		var depth: int = 0
		for line_idx: int in range(total_lines):
			_brace_depth_cache[line_idx] = depth
			var line: String = get_text_edit().get_line(line_idx)
			for ch: String in line:
				if ch == "{":
					depth += 1
				elif ch == "}":
					depth -= 1


func _on_text_changed() -> void:
	_parse_user_variables()
	_highlighter.global_variables = _global_variables
	_highlighter.local_variables = _local_variables
	_highlighter.instance_variables = _instance_variables
	_highlighter.clear_highlighting_cache()
	_highlighter.invalidate_cache()


func _parse_user_variables() -> void:
	_global_variables.clear()
	_local_variables.clear()
	_instance_variables.clear()
	var source: String = gdss_editor.get_full_source() if gdss_editor != null else editor.text
	for line: String in source.split("\n"):
		var stripped: String = line.strip_edges()
		var gm: RegExMatch = _re_global.search(stripped)
		if gm:
			_global_variables.append(gm.get_string(1))
			continue
		var im: RegExMatch = _re_instance.search(stripped)
		if im:
			_instance_variables.append(im.get_string(1))
			continue
		var lm: RegExMatch = _re_local.search(stripped)
		if lm:
			_local_variables.append(lm.get_string(1))
