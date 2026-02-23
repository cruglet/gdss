@tool
class_name GdssCompletionHandler
extends Node

@export var editor: CodeEdit
@export_group("Icons")

var _nodes: Array[String] = []
var _properties: Dictionary = {}
var _variants: Dictionary = {}
var _property_meta: Dictionary = {}
var _user_variables: Array[String] = []

var _completion_color: Color

const BUILTIN_COLORS: Array[String] = [
	"RED", "GREEN", "BLUE", "YELLOW", "WHITE", "BLACK",
	"TRANSPARENT", "ORANGE", "PURPLE", "CYAN", "MAGENTA", "GRAY"
]


func _ready() -> void:
	_completion_color = EditorInterface.get_editor_settings().get_setting("text_editor/theme/highlighting/completion_font_color")
	_build_from_objects()
	editor.code_completion_requested.connect(_on_completion_requested)
	editor.text_changed.connect(_on_text_changed)
	editor.code_completion_requested


func _build_from_objects() -> void:
	_nodes.clear()
	_properties.clear()
	_variants.clear()
	_property_meta.clear()
	
	var prefixes: Array[String] = ["@", ":", "\t"]
	
	for obj: GdssNode in get_parent().style_objects:
		var style_name: String = obj.style_name
		_nodes.append(style_name)
		
		var props_dict: Dictionary = {}
		for prop: GdssProp in obj.theme_properties:
			props_dict[prop.name] = prop
		_property_meta[style_name] = props_dict
		_properties[style_name] = props_dict.keys()
		_variants[style_name] = obj.variants
		
		if style_name.length() > 0 and not prefixes.has(style_name[0]):
			prefixes.append(style_name[0])
		
		for key: String in props_dict.keys():
			for l: int in range(1, min(4, key.length()) + 1):
				var pre: String = key.substr(0, l)
				if not prefixes.has(pre):
					prefixes.append(pre)
	
	editor.code_completion_prefixes = prefixes


func _on_text_changed() -> void:
	_parse_user_variables()
	var word: String = _get_current_word()
	if word.is_empty():
		var context: Dictionary = _get_context()
		var type: String = context.get("type", "")
		var current_line: String = editor.get_line(editor.get_caret_line())
		var line_is_only_whitespace: bool = current_line.strip_edges().is_empty()
		if type == "property_value":
			editor.request_code_completion(true)
			return
		if line_is_only_whitespace:
			editor.cancel_code_completion()
			return
		editor.cancel_code_completion()
		return
	_update_completions(word)


func _on_completion_requested() -> void:
	_parse_user_variables()
	_update_completions(_get_current_word())


func _update_completions(word: String) -> void:
	var context: Dictionary = _get_context()
	
	match context.get("type", "top_level"):
		"top_level":
			if ":" in word:
				var parts: PackedStringArray = word.split(":")
				_complete_node_variants(parts[0], parts[1] if parts.size() > 1 else "")
			else:
				_complete_nodes(word)
				_complete_at_directives(word)
		"property_key":
			if word.begins_with(":"):
				_complete_variants(word.trim_prefix(":"), context.get("style", ""))
			else:
				_complete_properties(word, context.get("style", ""))
		"variant_decl":
			_complete_variants(word.trim_prefix(":"), context.get("style", ""))
		"property_value":
			_complete_values(word, context.get("style", ""), context.get("property", ""))
		"variant_block":
			_complete_properties(word, context.get("style", ""))
	
	editor.update_code_completion_options(true)


func _complete_nodes(word: String) -> void:
	for node: String in _nodes:
		if word.is_empty() or node.to_lower().begins_with(word.to_lower()):
			editor.add_code_completion_option(CodeEdit.KIND_CLASS, node, node, _completion_color, _get_icon(node))


func _complete_node_variants(node: String, partial: String) -> void:
	var variants: PackedStringArray = _variants.get(node, PackedStringArray())
	for v: String in variants:
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
		
		if word.is_empty() or prop.begins_with(word):
			editor.add_code_completion_option(CodeEdit.KIND_MEMBER, prop, prop + ": ", _completion_color, _get_icon(&"MemberProperty"))
		
		if prop_def == null or prop_def.type != GDSS.Type.COMPOSITE4:
			continue
		if prop_def.default_value == null or not prop_def.default_value is Vector4i:
			continue
		var v4: Vector4i = prop_def.default_value
		var components: Array[Variant] = [v4.x, v4.y, v4.z, v4.w]
		
		for idx: int in range(prop_def.composite_of.size()):
			var sub: String = prop_def.composite_of[idx]
			if word.is_empty() or sub.begins_with(word):
				editor.add_code_completion_option(CodeEdit.KIND_MEMBER, sub, sub + ": ", _completion_color, _get_icon(&"MemberProperty"))


func _complete_variants(word: String, style_name: String) -> void:
	var variants: PackedStringArray = _variants.get(style_name, PackedStringArray())
	
	for v: String in variants:
		var display: String = ":" + v
		if word.is_empty() or display.begins_with(word) or v.begins_with(word):
			editor.add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, display, v + " ", _completion_color, _get_icon(&"Signal"))


func _complete_values(word: String, style_name: String, prop: String) -> void:
	var meta: Dictionary = _property_meta.get(style_name, {})
	if meta.is_empty():
		for key: String in _property_meta:
			var m: Dictionary = _property_meta[key]
			if m.has(prop):
				meta = m
				break
	
	var prop_def: GdssProp = meta.get(prop, null)
	
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
			return
		return

	match prop_def.type:
		GDSS.Type.COLOR:
			for c: String in BUILTIN_COLORS:
				if word.is_empty() or c.begins_with(word):
					editor.add_code_completion_option(CodeEdit.KIND_CONSTANT, c, c, _completion_color, _get_icon(&"Color"))
			for v: String in _user_variables:
				if word.is_empty() or v.begins_with(word):
					editor.add_code_completion_option(CodeEdit.KIND_VARIABLE, v, v)
		GDSS.Type.CURSOR:
			for cursor_key: String in GDSS.CursorType:
				if word.is_empty() or cursor_key.begins_with(word):
					editor.add_code_completion_option(CodeEdit.KIND_ENUM, cursor_key, cursor_key, _completion_color, _get_icon(&"Mouse"))
		GDSS.Type.TRANS:
			for trans_type: String in GDSS.TransitionType:
				if word.is_empty() or trans_type.begins_with(word):
					editor.add_code_completion_option(CodeEdit.KIND_ENUM, trans_type, trans_type, _completion_color, _get_icon(&"Curve"))
		GDSS.Type.INT:
			var default: Variant = prop_def.default_value
			if default != null:
				editor.add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, str(default), str(default), _completion_color, _get_icon(&"MemberProperty"))
		GDSS.Type.COMPOSITE4:
			var default: Variant = prop_def.default_value
			if default != null:
				var v4: Vector4i = default
				var hint: String = "%d %d %d %d" % [v4.x, v4.y, v4.z, v4.w]
				editor.add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, hint, hint, _completion_color, _get_icon(&"MemberProperty"))


func _complete_at_directives(word: String) -> void:
	if word.is_empty() or "@export var".begins_with(word):
		editor.add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, "@export var", "export var ")


func _get_context() -> Dictionary:
	var caret_line: int = editor.get_caret_line()
	var lines: PackedStringArray = editor.text.split("\n")
	
	var node_open_regex: RegEx = RegEx.new()
	node_open_regex.compile(r"^(\w+)(?::(\w+))?\s*\{")
	
	var variant_open_regex: RegEx = RegEx.new()
	variant_open_regex.compile(r"^:(\w+)\s*\{")
	
	var stack: Array[Dictionary] = []
	
	for i: int in range(caret_line):
		var line: String = lines[i].strip_edges()
		var comment_idx: int = line.find("//")
		if comment_idx != -1:
			line = line.substr(0, comment_idx).strip_edges()
		if line.is_empty():
			continue
		
		var m: RegExMatch = node_open_regex.search(line)
		if m:
			stack.push_back({
				"style": m.get_string(1),
				"variant": m.get_string(2),
				"in_variant": m.get_string(2) != ""
			})
			continue
		
		var vm: RegExMatch = variant_open_regex.search(line)
		if vm:
			var top: Dictionary = stack.back() if stack.size() > 0 else {}
			stack.push_back({
				"style": top.get("style", ""),
				"variant": vm.get_string(1),
				"in_variant": true
			})
			continue
		
		if "}" in line:
			if stack.size() > 0:
				stack.pop_back()
	
	var caret_text: String = lines[caret_line] if caret_line < lines.size() else ""
	var stripped: String = caret_text.strip_edges()
	var comment_idx: int = stripped.find("//")
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
	
	var colon_pos: int = stripped.find(":")
	if colon_pos != -1:
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
	var var_regex: RegEx = RegEx.new()
	var_regex.compile(r"@export\s+var\s+(\w+)")
	
	for line: String in editor.text.split("\n"):
		var m: RegExMatch = var_regex.search(line)
		if m:
			_user_variables.append(m.get_string(1))


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


func _get_icon(icon_name: StringName) -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon(icon_name, &"EditorIcons")
