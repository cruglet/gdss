@tool
class_name GdssHighlightHandler
extends Node

@export var editor: CodeEdit

var _highlighter: GdssCodeHighlighter
var _nodes: Array[String] = []
var _properties: Array[String] = []
var _variants: Array[String] = []
var _property_meta: Dictionary = {}
var _builtin_colors: Array[String] = [
	"RED", "GREEN", "BLUE", "YELLOW", "WHITE", "BLACK",
	"TRANSPARENT", "ORANGE", "PURPLE", "CYAN", "MAGENTA", "GRAY"
]


func _ready() -> void:
	_build_from_objects()
	_setup_highlighter()


func _build_from_objects() -> void:
	_nodes.clear()
	_properties.clear()
	_variants.clear()
	_property_meta.clear()

	for obj: GdssNode in get_parent().style_objects:
		var style_name: String = obj.style_name
		if not _nodes.has(style_name):
			_nodes.append(style_name)

		var props_dict: Dictionary = {}
		for prop: GdssProp in obj.theme_properties:
			props_dict[prop.name] = prop
			if not _properties.has(prop.name):
				_properties.append(prop.name)
			for sub: String in prop.composite_of:
				if not _properties.has(sub):
					_properties.append(sub)

		_property_meta[style_name] = props_dict

		for v: String in obj.variants:
			if not _variants.has(v):
				_variants.append(v)


func _setup_highlighter() -> void:
	_highlighter = GdssCodeHighlighter.new()
	_highlighter.nodes = _nodes
	_highlighter.properties = _properties
	_highlighter.variants = _variants
	_highlighter.property_meta = _property_meta
	_highlighter.builtin_colors = _builtin_colors
	_highlighter._node_variants = {}
	for obj: GdssNode in get_parent().style_objects:
		_highlighter._node_variants[obj.style_name] = obj.variants
	_highlighter.refresh_colors()
	editor.syntax_highlighter = _highlighter


class GdssCodeHighlighter extends SyntaxHighlighter:
	var nodes: Array[String] = []
	var properties: Array[String] = []
	var variants: Array[String] = []
	var property_meta: Dictionary = {}
	var builtin_colors: Array[String] = []
	var _node_variants: Dictionary = {}
	var _brace_depth_cache: Array[int] = []
	var _cache_dirty: bool = true

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
	var col_enum: Color
	var col_default: Color


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
		col_member = s.get_setting("text_editor/theme/highlighting/member_variable_color")
		col_brace_mismatch = s.get_setting("text_editor/theme/highlighting/brace_mismatch_color")
		col_enum = s.get_setting("text_editor/theme/highlighting/gdscript/node_path_color")
		col_default = s.get_setting("text_editor/theme/highlighting/text_color")


	func invalidate_cache() -> void:
		_cache_dirty = true
	
	
	func update_cache() -> void:
		_rebuild_brace_cache()
		_cache_dirty = false


	func _is_word_char(c: String) -> bool:
		var code: int = c.unicode_at(0)
		return (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95


	func _node_has_variant(node_name: String, variant: String) -> bool:
		if _node_variants.has(node_name):
			var v: PackedStringArray = _node_variants[node_name]
			return v.has(variant)
		return false

	func _get_line_syntax_highlighting(p_line: int) -> Dictionary:
		var result: Dictionary = {}
		var text: String = get_text_edit().get_line(p_line)
		var len: int = text.length()

		var total_lines: int = get_text_edit().get_line_count()

		if _cache_dirty or _brace_depth_cache.size() != total_lines:
			_rebuild_brace_cache()
			_cache_dirty = false

		var open_count: int = _brace_depth_cache[p_line] if p_line < _brace_depth_cache.size() else 0

		if len == 0:
			return result

		var i: int = 0
		while i < len:
			var c: String = text[i]

			# Comment
			if c == "/" and i + 1 < len and text[i + 1] == "/":
				result[i] = {"color": col_comment}
				break

			# String
			if c == "\"":
				result[i] = {"color": col_string}
				var j: int = i + 1
				while j < len and text[j] != "\"":
					j += 1
				result[j] = {"color": col_string}
				i = j + 1
				continue

			if c == "@":
						var start: int = i
						i += 1
						while i < len:
							var nc: String = text[i]
							var is_word_char: bool = (nc >= "a" and nc <= "z") or (nc >= "A" and nc <= "Z") or nc == "_"
							if not is_word_char:
								break
							i += 1
						result[start] = {"color": col_annotation}
						continue

			if c == "{":
				result[i] = {"color": col_symbol if open_count >= 0 else col_brace_mismatch}
				open_count += 1
				i += 1
				continue

			if c == "}":
				open_count -= 1
				result[i] = {"color": col_symbol if open_count >= 0 else col_brace_mismatch}
				i += 1
				continue

			# Parentheses and brackets — explicit symbol color so numbers don't bleed
			if c in ["(", ")", "[", "]"]:
				result[i] = {"color": col_symbol}
				i += 1
				continue

			if c in [":", ",", "="]:
				result[i] = {"color": col_symbol}
				i += 1
				continue

			if c.is_valid_int() or (c == "-" and i + 1 < len and text[i + 1].is_valid_int()):
				var start: int = i
				i += 1
				while i < len and (text[i].is_valid_int() or text[i] == "."):
					i += 1
				result[start] = {"color": col_number}
				continue

			var is_letter: bool = (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"
			if is_letter:
				var start: int = i
				i += 1
				while i < len:
					var nc: String = text[i]
					var is_word_char: bool = (nc >= "a" and nc <= "z") or (nc >= "A" and nc <= "Z") or nc == "_" or (nc >= "0" and nc <= "9")
					if not is_word_char:
						break
					i += 1
				if i == start:
					i += 1
					continue
				var word: String = text.substr(start, i - start)
				var before: String = text.substr(0, start)
				var before_stripped: String = before.strip_edges()

				var is_after_colon: bool = before_stripped.ends_with(":")
				var after: String = text.substr(i).strip_edges()
				var is_before_brace: bool = after.begins_with("{") or (after.begins_with(":") and after.find("{") != -1)
				var colon_idx: int = before_stripped.rfind(":")
				var brace_idx: int = before_stripped.rfind("{")
				var in_value: bool = colon_idx != -1 and colon_idx > brace_idx and not is_after_colon

				if is_after_colon and variants.has(word):
					var before_colon: String = before_stripped.substr(0, before_stripped.length() - 1).strip_edges()
					var valid: bool = false
					if open_count > 0:
						for style_name: String in _node_variants:
							if _node_has_variant(style_name, word):
								valid = true
								break
					else:
						valid = _node_has_variant(before_colon, word)
					result[start] = {"color": col_control_flow if valid else col_default}
				elif nodes.has(word):
					result[start] = {"color": col_type}
				elif is_before_brace:
					result[start] = {"color": col_user_type}
				elif in_value:
					var is_enum: bool = builtin_colors.has(word)
					if not is_enum:
						var colon_prop: int = before_stripped.rfind(":")
						if colon_prop != -1:
							var prop: String = before_stripped.substr(0, colon_prop).strip_edges()
							for style_name: String in property_meta:
								var meta: Dictionary = property_meta[style_name]
								if meta.has(prop):
									var pd: GdssProp = meta[prop]
									if pd.type == GDSS.Type.CURSOR:
										is_enum = true
										break
					result[start] = {"color": col_enum if is_enum else col_default}
				elif word == "var":
					result[start] = {"color": col_keyword}
				elif properties.has(word):
					result[start] = {"color": col_member}
				elif variants.has(word):
					result[start] = {"color": col_control_flow}
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


	func _is_enum_property(prop: String) -> bool:
		for style_name: String in property_meta:
			var meta: Dictionary = property_meta[style_name]
			if not meta.has(prop):
				continue
			var pd: GdssProp = meta[prop]
			if pd.type == GDSS.Type.CURSOR or pd.type == GDSS.Type.COLOR:
				return true
		return false


func _on_text_changed() -> void:
	_highlighter.invalidate_cache()
	_highlighter.update_cache()
