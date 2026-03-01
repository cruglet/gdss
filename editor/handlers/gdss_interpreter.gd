@tool
class_name GdssInterpreter
extends Node

signal parsed_changed

static var parsed: Dictionary[String, Dictionary] = {}
static var globals: Dictionary = {}
static var _global_defaults: Dictionary = {}
static var _instance_vars: Dictionary = {}
static var _instance_defaults: Dictionary = {}
var _last_modified: int = 0
var _saving: bool = false
static var _inst: GdssInterpreter

@export var editor: GdssEditor

var _defaults: Dictionary[String, Dictionary] = {}


static func get_instance() -> GdssInterpreter:
	return _inst


func _ready() -> void:
	_inst = self
	_build_defaults()
	_load_from_file()
	if Engine.is_editor_hint():
		if not editor.code_edit.text_changed.is_connected(_on_text_changed):
			editor.code_edit.text_changed.connect(_on_text_changed)
		if OS.is_debug_build():
			EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_editor_file_saved)


func _on_editor_file_saved() -> void:
	if _saving:
		return
	var modified: int = FileAccess.get_modified_time(GdssStorage.get_save_path())
	if modified == _last_modified:
		return
	_last_modified = modified
	_load_from_file()
	if Engine.is_editor_hint():
		_force_viewport_redraw()


func _on_text_changed() -> void:
	editor._prompt_save()


func save_current() -> void:
	if editor == null:
		return
	parsed = interpret(editor.code_edit.text)
	_saving = true
	GdssStorage.save(editor.code_edit.text, parsed, GdssInterpreter._global_defaults, GdssInterpreter._instance_defaults)
	_last_modified = FileAccess.get_modified_time(GdssStorage.get_save_path())
	_saving = false
	editor._user_saved()
	parsed_changed.emit()
	if Engine.is_editor_hint():
		_force_viewport_redraw()


func _force_viewport_redraw() -> void:
	var viewport_container: Control = EditorInterface.get_editor_viewport_2d().get_parent() as Control
	if viewport_container == null:
		return
	var original_size: Vector2 = viewport_container.size
	viewport_container.size = original_size + Vector2(1, 0)
	viewport_container.size = original_size


func _load_from_file() -> void:
	_last_modified = FileAccess.get_modified_time(GdssStorage.get_save_path())
	var data: Dictionary = GdssStorage.load_data()
	if data.is_empty():
		return
	if data.has("source") and Engine.is_editor_hint() and is_instance_valid(editor):
		var source: String = data["source"]
		if editor.code_edit.text != source:
			if editor.code_edit.text_changed.is_connected(_on_text_changed):
				editor.code_edit.text_changed.disconnect(_on_text_changed)
			editor.code_edit.text = source
			editor.code_edit.text_changed.connect(_on_text_changed)
	if data.has("parsed") and data["parsed"] is Dictionary:
		for key: String in (data["parsed"] as Dictionary):
			var val: Variant = (data["parsed"] as Dictionary)[key]
			if val is Dictionary:
				parsed[key] = val
		parsed_changed.emit()


func _build_defaults() -> void:
	var known_states: PackedStringArray = _collect_states()
	for selector: String in GDSS._get_gdss_nodes():
		var node: GdssNode = GDSS._get_gdss_nodes().get(selector)
		_ensure_selector(_defaults, selector, known_states)
		if node.base_type != StringName("") and node.base_type != StringName(selector):
			_defaults[selector]["base"] = String(node.base_type)
		for prop: GdssProp in node.get_enabled_props():
			_defaults[selector]["all"][prop.name] = prop.get_default_value()


func _build_composite_map(selector: String) -> Dictionary:
	var map: Dictionary = {}
	var gdss_node: GdssNode = GDSS._get_gdss_nodes().get(selector)
	if gdss_node == null:
		return map
	for prop: GdssProp in gdss_node.get_enabled_props():
		if not prop.is_composite():
			continue
		for i: int in prop.composite_of.size():
			map[prop.composite_of[i]] = {"prop": prop.name, "index": i}
	return map


func interpret(source: String) -> Dictionary[String, Dictionary]:
	var globals: Dictionary = _extract_globals(source)
	var known_states: PackedStringArray = _collect_states()
	var result: Dictionary[String, Dictionary] = {}
	for selector: String in _defaults:
		result[selector] = {}
		for state: String in _defaults[selector]:
			if _defaults[selector][state] is Dictionary:
				result[selector][state] = _defaults[selector][state].duplicate()
			else:
				result[selector][state] = _defaults[selector][state]
	var tokens: Array[String] = _tokenize(source)
	tokens = _substitute_globals(tokens, globals)
	_parse_block(tokens, 0, result, "", known_states)
	return result


func _extract_globals(source: String) -> Dictionary:
	var local_vars: Dictionary = {}
	globals.clear()
	_global_defaults.clear()
	_instance_defaults.clear()

	var global_regex: RegEx = RegEx.new()
	global_regex.compile(r"^@global\s+var\s+(\w+)\s*:\s*(.+)")
	var instance_regex: RegEx = RegEx.new()
	instance_regex.compile(r"^@instance\s+var\s+(\w+)\s*:\s*(.+)")
	var local_regex: RegEx = RegEx.new()
	local_regex.compile(r"^var\s+(\w+)\s*:\s*(.+)")

	for line: String in source.split("\n"):
		var stripped: String = line.strip_edges()
		var comment_idx: int = stripped.find("//")
		if comment_idx != -1:
			stripped = stripped.substr(0, comment_idx).strip_edges()
		var gm: RegExMatch = global_regex.search(stripped)
		if gm:
			var name: String = gm.get_string(1)
			var val: Variant = _parse_value([gm.get_string(2).strip_edges()])
			globals[name] = val
			_global_defaults[name] = val
			continue
		var im: RegExMatch = instance_regex.search(stripped)
		if im:
			var name: String = im.get_string(1)
			var val: Variant = _parse_value([im.get_string(2).strip_edges()])
			_instance_defaults[name] = val
			continue
		var lm: RegExMatch = local_regex.search(stripped)
		if lm:
			local_vars[lm.get_string(1)] = lm.get_string(2).strip_edges()
	return local_vars



func _substitute_globals(tokens: Array[String], local_vars: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for token: String in tokens:
		if token.begins_with("$"):
			var key: String = token.substr(1)
			if local_vars.has(key):
				for part: String in local_vars[key].split(" ", false):
					result.append(part)
				continue
			if globals.has(key):
				result.append("__gdss_global__" + key)
				continue
			if _instance_defaults.has(key):
				result.append("__gdss_instance__" + key)
				continue
		result.append(token)
	return result


func _collect_states() -> PackedStringArray:
	var states: PackedStringArray = []
	for node: GdssNode in GDSS._get_gdss_nodes().values():
		for variant: String in node.states:
			if not states.has(variant):
				states.append(variant)
	return states


func _collect_selector_group(tokens: Array[String], pos: int, known_states: PackedStringArray) -> Array:
	var selectors: Array[String] = []
	while pos < tokens.size():
		var token: String = tokens[pos]
		if token == "{":
			break
		if token == ",":
			pos += 1
			continue
		if token == ":":
			var next: String = tokens[pos + 1] if pos + 1 < tokens.size() else ""
			selectors.append(":" + next)
			pos += 2
			continue
		selectors.append(token)
		pos += 1
	return [selectors, pos]


func _tokenize(source: String) -> Array[String]:
	var tokens: Array[String] = []
	for line: String in source.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("@global") or stripped.begins_with("@instance") or stripped.begins_with("var "):
			continue
		var comment_idx: int = stripped.find("//")
		if comment_idx != -1:
			stripped = stripped.substr(0, comment_idx).strip_edges()
		if stripped.is_empty():
			continue
		var current: String = ""
		for ch: String in stripped:
			if ch in ["{", "}", ":", ","]:
				if not current.strip_edges().is_empty():
					tokens.append(current.strip_edges())
					current = ""
				tokens.append(ch)
			elif ch == " " or ch == "\t":
				if not current.strip_edges().is_empty():
					tokens.append(current.strip_edges())
					current = ""
			else:
				current += ch
		if not current.strip_edges().is_empty():
			tokens.append(current.strip_edges())
	return tokens


func _ensure_selector(result: Dictionary, selector: String, known_states: PackedStringArray) -> void:
	if result.has(selector):
		return
	var entry: Dictionary = {"all": {}, "_classes": {}}
	for state: String in known_states:
		entry[state] = {}
	result[selector] = entry


func _parse_block(tokens: Array[String], pos: int, result: Dictionary, parent_selector: String, known_states: PackedStringArray) -> int:
	while pos < tokens.size():
		var token: String = tokens[pos]
		if token == "}":
			return pos + 1

		var next: String = tokens[pos + 1] if pos + 1 < tokens.size() else ""
		var next2: String = tokens[pos + 2] if pos + 2 < tokens.size() else ""

		var is_comma_group: bool = _has_comma_before_brace(tokens, pos)

		if is_comma_group:
			var collected: Array = _collect_selector_group(tokens, pos, known_states)
			var selectors: Array[String] = collected[0]
			var block_start: int = collected[1] + 1
			var block_end: int = _find_block_end(tokens, block_start)
			var block_tokens: Array[String] = tokens.slice(block_start, block_end - 1)
			for raw_selector: String in selectors:
				if raw_selector.begins_with(":"):
					var state: String = raw_selector.substr(1).to_lower()
					if not parent_selector.is_empty():
						_ensure_selector(result, parent_selector, known_states)
						_parse_props_into(block_tokens, 0, result, parent_selector, state, known_states)
				else:
					var child_container: Dictionary = _get_child_container(result, parent_selector)
					_ensure_selector(child_container, raw_selector, known_states)
					if not parent_selector.is_empty():
						_inherit(child_container, raw_selector, result[parent_selector])
					_parse_block(block_tokens, 0, child_container, raw_selector, known_states)
			pos = block_end
			continue

		if next == ":" and next2 != "" and next2 != "{" and pos + 3 < tokens.size() and tokens[pos + 3] == "{":
			var child_container: Dictionary = _get_child_container(result, parent_selector)
			_ensure_selector(child_container, token, known_states)
			pos = _parse_props_into(tokens, pos + 4, child_container, token, next2.to_lower(), known_states)
			continue

		if token == ":" and next2 == "{":
			if not parent_selector.is_empty():
				_ensure_selector(result, parent_selector, known_states)
				pos = _parse_props_into(tokens, pos + 3, result, parent_selector, next.to_lower(), known_states)
			else:
				pos += 3
			continue

		if next == "{":
			var child_container: Dictionary = _get_child_container(result, parent_selector)
			_ensure_selector(child_container, token, known_states)
			if not parent_selector.is_empty():
				_inherit(child_container, token, result[parent_selector])
			pos = _parse_block(tokens, pos + 2, child_container, token, known_states)
			continue

		if next == ":":
			if not parent_selector.is_empty() and next2 != "" and next2 != "{":
				_ensure_selector(result, parent_selector, known_states)
				var consumed: Array = _consume_value(tokens, pos + 2, known_states)
				_set_prop(result, parent_selector, "all", token, consumed[0])
				pos = consumed[1]
			else:
				pos += 2
			continue

		pos += 1

	return pos


func _get_child_container(result: Dictionary, parent_selector: String) -> Dictionary:
	if parent_selector.is_empty():
		return result
	if not result[parent_selector].has("_classes"):
		result[parent_selector]["_classes"] = {}
	return result[parent_selector]["_classes"]


func _has_comma_before_brace(tokens: Array[String], pos: int) -> bool:
	var i: int = pos
	while i < tokens.size():
		if tokens[i] == "{":
			return false
		if tokens[i] == "}":
			return false
		if tokens[i] == ":":
			var after: String = tokens[i + 1] if i + 1 < tokens.size() else ""
			if after != "{" and after != "":
				var after2: String = tokens[i + 2] if i + 2 < tokens.size() else ""
				if after2 != "{" and after2 != ",":
					return false
		if tokens[i] == ",":
			return true
		i += 1
	return false


func _find_block_end(tokens: Array[String], pos: int) -> int:
	var depth: int = 1
	while pos < tokens.size():
		if tokens[pos] == "{":
			depth += 1
		elif tokens[pos] == "}":
			depth -= 1
			if depth == 0:
				return pos + 1
		pos += 1
	return pos


func _parse_props_into(tokens: Array[String], pos: int, result: Dictionary, selector: String, state: String, known_states: PackedStringArray) -> int:
	while pos < tokens.size():
		var token: String = tokens[pos]
		if token == "}":
			return pos + 1

		var next: String = tokens[pos + 1] if pos + 1 < tokens.size() else ""
		var next2: String = tokens[pos + 2] if pos + 2 < tokens.size() else ""

		if next == ":":
			if next2 != "" and next2 != "{":
				var consumed: Array = _consume_value(tokens, pos + 2, known_states)
				_set_prop(result, selector, state, token, consumed[0])
				pos = consumed[1]
			else:
				pos += 2
			continue

		pos += 1

	return pos


func _consume_value(tokens: Array[String], pos: int, known_states: PackedStringArray) -> Array:
	var parts: Array[String] = []
	while pos < tokens.size():
		var t: String = tokens[pos]
		if t == "{" or t == "}":
			break
		var lookahead: String = tokens[pos + 1] if pos + 1 < tokens.size() else ""
		var lookahead2: String = tokens[pos + 2] if pos + 2 < tokens.size() else ""
		if lookahead == "{":
			break
		if lookahead == ":" and (lookahead2 == "{" or known_states.has(lookahead2.to_lower())):
			parts.append(t)
			pos += 1
			break
		if lookahead == ":" and not parts.is_empty():
			break
		parts.append(t)
		pos += 1
	return [_parse_value(parts), pos]


func _inherit(result: Dictionary, child: String, parent_data: Dictionary) -> void:
	for state: String in parent_data:
		if state == "_classes" or not result[child].has(state):
			continue
		if not parent_data[state] is Dictionary:
			continue
		for prop: String in parent_data[state]:
			if not result[child][state].has(prop):
				result[child][state][prop] = parent_data[state][prop]


func _parse_value(parts: Array[String]) -> Variant:
	if parts.is_empty():
		return ""
	if parts.size() == 4:
		var all_numeric: bool = true
		for p: String in parts:
			if not p.is_valid_int() and not p.is_valid_float():
				all_numeric = false
				break
		if all_numeric:
			return Vector4i(int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3]))
	if parts.size() == 1:
		var token: String = parts[0].trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'")
		if token.begins_with("#") and Color.html_is_valid(token):
			return Color.html(token)
		if parts[0].is_valid_int():
			return int(parts[0])
		if parts[0].is_valid_float():
			return float(parts[0])
	return " ".join(parts)


func _set_prop(result: Dictionary, selector: String, state: String, prop: String, value: Variant) -> void:
	var composite_map: Dictionary = _build_composite_map(selector)
	if composite_map.has(prop):
		var info: Dictionary = composite_map[prop]
		var parent_prop: String = info["prop"]
		var index: int = info["index"]
		if not result[selector][state].has(parent_prop):
			var gdss_node: GdssNode = GDSS._get_gdss_nodes().get(selector)
			for p: GdssProp in gdss_node.get_enabled_props():
				if p.name == parent_prop:
					result[selector][state][parent_prop] = p.get_default_value()
					break
		var vec: Vector4i = result[selector][state][parent_prop]
		match index:
			0: vec.x = int(value)
			1: vec.y = int(value)
			2: vec.z = int(value)
			3: vec.w = int(value)
		result[selector][state][parent_prop] = vec
		return
	result[selector][state][prop] = value
