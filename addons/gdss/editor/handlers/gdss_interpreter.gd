@tool
class_name GdssInterpreter
extends Node

signal parsed_changed

static var parsed: Dictionary[String, Dictionary] = {}
static var globals: Dictionary = {}
static var _global_defaults: Dictionary = {}
static var _instance_vars: Dictionary = {}
static var _instance_defaults: Dictionary = {}
static var _local_vars: Dictionary = {}
var _last_modified: int = 0
var _saving: bool = false
var _cached_states: PackedStringArray = []
var _composite_map_cache: Dictionary = {}
static var _inst: GdssInterpreter

static var _re_global: RegEx = RegEx.create_from_string(r"^@global\s+var\s+(\w+)\s*:\s*(.+)")
static var _re_instance: RegEx = RegEx.create_from_string(r"^@instance\s+var\s+(\w+)\s*:\s*(.+)")
static var _re_local: RegEx = RegEx.create_from_string(r"^var\s+(\w+)\s*:\s*(.+)")
static var _re_bad_annotation: RegEx = RegEx.create_from_string(r"^@(\w+)")

@export var editor: GdssEditor

var _defaults: Dictionary[String, Dictionary] = {}
var _error_timer: Timer


static func get_instance() -> GdssInterpreter:
	return _inst


static func get_class_names(node_type: String) -> PackedStringArray:
	var names: PackedStringArray = []
	if not parsed.has(node_type):
		return names
	_collect_class_names(parsed[node_type].get("_classes", {}), names)
	names.sort()
	return names


static func _collect_class_names(classes: Dictionary, names: PackedStringArray) -> void:
	for class_key: String in classes:
		if not names.has(class_key):
			names.append(class_key)
		var entry: Variant = classes[class_key]
		if entry is Dictionary:
			_collect_class_names((entry as Dictionary).get("_classes", {}), names)


func _ready() -> void:
	if not editor.is_running_as_plugin():
		set_process(false)
		return
	
	_inst = self
	_build_defaults()
	_load_from_file()
	_error_timer = Timer.new()
	_error_timer.wait_time = 0.5
	_error_timer.one_shot = true
	_error_timer.timeout.connect(_on_error_check_timeout)
	add_child(_error_timer)
	if Engine.is_editor_hint():
		if not editor.get_code_edit().text_changed.is_connected(_on_text_changed):
			editor.get_code_edit().text_changed.connect(_on_text_changed)
		if OS.is_debug_build():
			EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_editor_file_saved)
	await get_tree().process_frame
	editor.display_errors(check_errors(editor.get_full_source()))


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and Engine.is_editor_hint():
		var modified: int = FileAccess.get_modified_time(GdssStorage.get_save_path())
		if modified == _last_modified:
			return
		_last_modified = modified
		_load_from_file()
		_force_viewport_redraw()


func _get_known_states() -> PackedStringArray:
	if not _cached_states.is_empty():
		return _cached_states
	_cached_states = _collect_states()
	return _cached_states


func _collect_states() -> PackedStringArray:
	var states: PackedStringArray = []
	for node: GdssNode in GDSS._get_gdss_nodes().values():
		for variant: String in node.states:
			if not states.has(variant):
				states.append(variant)
	return states


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
	_error_timer.start()


func _on_error_check_timeout() -> void:
	editor.display_errors(check_errors(editor.get_full_source()))


func _strip_line_comment(s: String) -> String:
	var in_quote: bool = false
	var quote_char: String = ""
	var i: int = 0
	while i < s.length():
		var c: String = s[i]
		if in_quote:
			if c == quote_char:
				in_quote = false
		elif c == "\"" or c == "'":
			in_quote = true
			quote_char = c
		elif c == "#":
			return s.substr(0, i).strip_edges()
		i += 1
	return s


# Splits a line into statements on unquoted semicolons, treating ";" like a newline.
func _split_statements(line: String) -> PackedStringArray:
	var result: PackedStringArray = []
	var current: String = ""
	var in_quote: bool = false
	var quote_char: String = ""
	for c: String in line:
		if in_quote:
			current += c
			if c == quote_char:
				in_quote = false
		elif c == "\"" or c == "'":
			in_quote = true
			quote_char = c
			current += c
		elif c == ";":
			result.append(current)
			current = ""
		else:
			current += c
	result.append(current)
	return result


func _method_name_of(call_text: String) -> String:
	return call_text.substr(0, call_text.find("(")).strip_edges()


func _is_undefined_var(var_name: String, declared_vars: Dictionary) -> bool:
	return not declared_vars.has(var_name) and not _global_defaults.has(var_name) and not _instance_defaults.has(var_name)


const BUILTIN_COLORS: PackedStringArray = [
	"RED", "GREEN", "BLUE", "YELLOW", "WHITE", "BLACK",
	"TRANSPARENT", "ORANGE", "PURPLE", "CYAN", "MAGENTA", "GRAY"
]


func _is_valid_color_value(val: String) -> bool:
	var clean: String = val.trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'")
	if clean.begins_with("#") and Color.html_is_valid(clean):
		return true
	if val.contains("("):
		return true
	if BUILTIN_COLORS.has(val.to_upper()):
		return true
	return false


func _get_enum_keys_for_type(t: GDSS.Type) -> PackedStringArray:
	match t:
		GDSS.Type.CURSOR:
			return PackedStringArray(GDSS.CursorType.keys())
		GDSS.Type.TRANSITION_TYPE:
			return PackedStringArray(GDSS.TransitionType.keys())
		GDSS.Type.TRANSITION_FUNC:
			return PackedStringArray(GDSS.TransitionFunc.keys())
	return []


func _check_method_arg_type(arg: String, param: GdssMethod.Param, method_name: String, errors: Array[Array], line: int) -> void:
	if arg.begins_with("$") or arg == "pass":
		return
	match param.type:
		GdssMethod.ParamType.INT:
			if not arg.is_valid_int():
				errors.append(["Argument '%s' in '%s()' expects int, got '%s'" % [param.name, method_name, arg], line])
		GdssMethod.ParamType.FLOAT:
			if not arg.is_valid_float():
				errors.append(["Argument '%s' in '%s()' expects float, got '%s'" % [param.name, method_name, arg], line])
		GdssMethod.ParamType.BOOL:
			if arg.to_lower() not in ["true", "false", "1", "0"]:
				errors.append(["Argument '%s' in '%s()' expects bool, got '%s'" % [param.name, method_name, arg], line])
		GdssMethod.ParamType.COLOR:
			if not _is_valid_color_value(arg):
				errors.append(["Argument '%s' in '%s()' expects a color (#hex), got '%s'" % [param.name, method_name, arg], line])
		GdssMethod.ParamType.STRING:
			pass


func _check_method_call(value_str: String, method_name: String, prop: GdssProp, known_methods: Dictionary, errors: Array[Array], line: int) -> void:
	if not known_methods.has(method_name):
		errors.append(["Unknown method '%s()'" % method_name, line])
		return

	var gdss_method: GdssMethod = known_methods[method_name]

	if prop != null and not gdss_method.supported_prop_types.is_empty():
		if not gdss_method.supported_prop_types.has(prop.type):
			errors.append(["Method '%s()' cannot be used for property type '%s'" % [method_name, GDSS.Type.keys()[prop.type]], line])

	var args_start: int = value_str.find("(")
	var args_end: int = value_str.rfind(")")
	if args_start == -1 or args_end == -1 or args_end <= args_start:
		errors.append(["Malformed method call '%s'" % value_str, line])
		return

	var args_raw: String = value_str.substr(args_start + 1, args_end - args_start - 1).strip_edges()
	var args: Array[String] = []
	if not args_raw.is_empty():
		for arg: String in args_raw.split(","):
			args.append(arg.strip_edges())

	var required_count: int = 0
	for param: GdssMethod.Param in gdss_method.parameters:
		if not param.optional:
			required_count += 1
	var total_count: int = gdss_method.parameters.size()

	if args.size() < required_count or args.size() > total_count:
		if required_count == total_count:
			errors.append(["Method '%s()' expects %d argument(s), got %d" % [method_name, required_count, args.size()], line])
		else:
			errors.append(["Method '%s()' expects %d–%d argument(s), got %d" % [method_name, required_count, total_count, args.size()], line])
		return

	for ai: int in args.size():
		_check_method_arg_type(args[ai], gdss_method.parameters[ai], method_name, errors, line)


func _check_prop_value(value_str: String, prop: GdssProp, prop_name: String, known_methods: Dictionary, declared_vars: Dictionary, errors: Array[Array], line: int) -> void:
	if value_str.contains("("):
		var method_name: String = _method_name_of(value_str)
		_check_method_call(value_str, method_name, prop, known_methods, errors, line)
		return
	
	var actual_type: GDSS.Type = prop.type
	if prop.composite_of.has(prop_name):
		actual_type = GDSS.Type.INT
	
	if actual_type == GDSS.Type.COMPOSITE4:
		var parts: PackedStringArray = value_str.split(" ", false)
		if parts.size() != 4:
			errors.append(["Property '%s' expects 4 integer values, got %d" % [prop_name, parts.size()], line])
			return
		for part: String in parts:
			if part.begins_with("$"):
				var var_name: String = part.substr(1)
				if _is_undefined_var(var_name, declared_vars):
					errors.append(["Undefined variable '$%s'" % var_name, line])
			elif not part.is_valid_int():
				errors.append(["Property '%s' expects all integer components, got '%s'" % [prop_name, part], line])
		return
	
	if value_str.begins_with("$"):
		var var_name: String = value_str.substr(1)
		if _is_undefined_var(var_name, declared_vars):
			errors.append(["Undefined variable '$%s'" % var_name, line])
		return
	
	match actual_type:
		GDSS.Type.INT, GDSS.Type.CURSOR, GDSS.Type.TRANSITION_TYPE, GDSS.Type.TRANSITION_FUNC:
			if not value_str.is_valid_int():
				var enum_keys: PackedStringArray = _get_enum_keys_for_type(actual_type)
				if enum_keys.is_empty() or not enum_keys.has(value_str.to_upper()):
					errors.append(["Property '%s' expects an integer value, got '%s'" % [prop_name, value_str], line])
		GDSS.Type.FLOAT:
			if not value_str.is_valid_float():
				errors.append(["Property '%s' expects a float value, got '%s'" % [prop_name, value_str], line])
		GDSS.Type.BOOLEAN:
			if value_str.to_lower() not in ["true", "false", "1", "0"]:
				errors.append(["Property '%s' expects a boolean (true/false), got '%s'" % [prop_name, value_str], line])
		GDSS.Type.COLOR:
			if not _is_valid_color_value(value_str):
				errors.append(["Property '%s' expects a color value (#hex, named color, or method), got '%s'" % [prop_name, value_str], line])


func check_errors(source: String) -> Array[Array]:
	var errors: Array[Array] = []
	var lines: PackedStringArray = source.split("\n")
	var known_selectors: Array = GDSS._get_gdss_nodes().keys()
	var known_states: PackedStringArray = _get_known_states()
	var known_methods: Dictionary = GDSS._get_gdss_methods()
	var brace_depth: int = 0
	var brace_open_lines: Array[int] = []
	var selector_stack: Array[String] = []
	var declared_vars: Dictionary = {}

	var statements: Array[Array] = []
	for line_idx: int in lines.size():
		var line_text: String = _strip_line_comment(lines[line_idx].strip_edges())
		for raw_stmt: String in _split_statements(line_text):
			statements.append([raw_stmt.strip_edges(), line_idx])

	for entry: Array in statements:
		var stripped: String = entry[0]
		var i: int = entry[1]

		if stripped.is_empty():
			continue

		if stripped.begins_with("@global") or stripped.begins_with("@instance"):
			var is_global: bool = stripped.begins_with("@global")
			var rx: RegEx = _re_global if is_global else _re_instance
			var m: RegExMatch = rx.search(stripped)
			if not m:
				var label: String = "@global" if is_global else "@instance"
				errors.append(["Invalid %s var declaration. Expected: %s var name: value" % [label, label], i])
			else:
				var val_str: String = m.get_string(2).strip_edges()
				if val_str.is_empty():
					errors.append(["Variable '%s' has no value" % m.get_string(1), i])
				else:
					declared_vars[m.get_string(1)] = true
					if val_str.contains("("):
						var method_name: String = _method_name_of(val_str)
						_check_method_call(val_str, method_name, null, known_methods, errors, i)
			continue

		if stripped.begins_with("var "):
			var m: RegExMatch = _re_local.search(stripped)
			if not m:
				errors.append(["Invalid var declaration. Expected: var name: value", i])
			else:
				var val_str: String = m.get_string(2).strip_edges()
				if val_str.is_empty():
					errors.append(["Variable '%s' has no value" % m.get_string(1), i])
				else:
					declared_vars[m.get_string(1)] = true
					if val_str.contains("("):
						var method_name: String = _method_name_of(val_str)
						_check_method_call(val_str, method_name, null, known_methods, errors, i)
			continue

		if stripped.begins_with("@"):
			var am: RegExMatch = _re_bad_annotation.search(stripped)
			var annotation_name: String = am.get_string(1) if am else stripped
			errors.append(["Unknown annotation '@%s'" % annotation_name, i])
			continue

		for ch: String in stripped:
			if ch == "{":
				brace_depth += 1
				brace_open_lines.append(i)
			elif ch == "}":
				brace_depth -= 1
				if brace_depth < 0:
					errors.append(["Unexpected closing brace '}'", i])
					brace_depth = 0
				else:
					if not brace_open_lines.is_empty():
						brace_open_lines.pop_back()
					if not selector_stack.is_empty():
						selector_stack.pop_back()

		if stripped.ends_with("{"):
			var selector_part: String = stripped.trim_suffix("{").strip_edges()
			var colon_pos: int = -1
			for ci: int in selector_part.length():
				if selector_part[ci] == ":":
					colon_pos = ci
					break

			var base_part: String = selector_part.substr(0, colon_pos if colon_pos != -1 else selector_part.length()).strip_edges()
			var state_part: String = selector_part.substr(colon_pos + 1).strip_edges().to_lower() if colon_pos != -1 else ""

			for sel: String in base_part.split(","):
				var s: String = sel.strip_edges()
				if s.is_empty():
					continue
				if brace_depth == 1:
					if not known_selectors.has(s):
						errors.append(["Unknown selector '%s'" % s, i])
				selector_stack.append(s)

			for raw_state: String in state_part.split(",", false):
				var state_name: String = raw_state.strip_edges().trim_prefix(":").strip_edges()
				if not state_name.is_empty() and not known_states.has(state_name):
					errors.append(["Unknown state ':%s'" % state_name, i])
			continue

		if stripped == "}":
			continue

		if brace_depth == 0:
			errors.append(["Unexpected token outside of any block: '%s'" % stripped, i])
			continue

		if stripped.contains(":"):
			var colon_idx: int = stripped.find(":")
			var prop_name: String = stripped.substr(0, colon_idx).strip_edges()
			var value_str: String = stripped.substr(colon_idx + 1).strip_edges()

			if prop_name.is_empty():
				errors.append(["Empty property name", i])
				continue

			if value_str.is_empty():
				errors.append(["Property '%s' has no value" % prop_name, i])
				continue

			var current_selector: String = selector_stack.back() if not selector_stack.is_empty() else ""
			var gdss_node: GdssNode = GDSS._get_gdss_nodes().get(current_selector) if not current_selector.is_empty() else null

			if gdss_node != null:
				var all_props: Array[GdssProp] = gdss_node.get_enabled_props()
				var matched_prop: GdssProp = null
				for p: GdssProp in all_props:
					if p.name == prop_name or p.composite_of.has(prop_name):
						matched_prop = p
						break

				if matched_prop == null:
					errors.append(["Unknown property '%s' for selector '%s'" % [prop_name, current_selector], i])
				else:
					_check_prop_value(value_str, matched_prop, prop_name, known_methods, declared_vars, errors, i)
			else:
				if value_str.begins_with("$"):
					var var_name: String = value_str.substr(1)
					if _is_undefined_var(var_name, declared_vars):
						errors.append(["Undefined variable '$%s'" % var_name, i])
				elif value_str.contains("("):
					var method_name: String = _method_name_of(value_str)
					_check_method_call(value_str, method_name, null, known_methods, errors, i)
		else:
			errors.append(["Stray token '%s': expected a property or block" % stripped, i])

	for line: int in brace_open_lines:
		errors.append(["Unclosed brace '{'", line])

	return errors


func save_current() -> void:
	if editor == null:
		return
	_saving = true
	var source: String = editor.get_full_source()
	GdssStorage.write_source(GdssStorage.get_save_path(), source)
	parsed = interpret(source)
	GdssStorage.write_cache(parsed, _global_defaults, _instance_defaults, _local_vars)
	_last_modified = FileAccess.get_modified_time(GdssStorage.get_save_path())
	editor._user_saved()
	parsed_changed.emit()
	if Engine.is_editor_hint():
		_force_viewport_redraw()
	_saving = false


func _force_viewport_redraw() -> void:
	var viewport_container: Control = EditorInterface.get_editor_viewport_2d().get_parent() as Control
	if viewport_container == null:
		return
	var original_size: Vector2 = viewport_container.size
	viewport_container.size = original_size + Vector2(1, 0)
	viewport_container.size = original_size


func _load_from_file() -> void:
	_cached_states.clear()
	_composite_map_cache.clear()
	_last_modified = FileAccess.get_modified_time(GdssStorage.get_save_path())
	var source: String = GdssStorage.read_source(GdssStorage.get_save_path())
	if Engine.is_editor_hint() and is_instance_valid(editor) and editor.is_running_as_plugin():
		if editor.get_code_edit().text_changed.is_connected(_on_text_changed):
			editor.get_code_edit().text_changed.disconnect(_on_text_changed)
		editor.set_full_source(source)
		editor.get_code_edit().text_changed.connect(_on_text_changed)
	parsed = interpret(source)
	parsed_changed.emit()


func _build_defaults() -> void:
	_composite_map_cache.clear()
	_cached_states.clear()
	var db: GdssDB = GDSS.get_db()
	if db.node_list.is_empty():
		db.repopulate()
	var known_states: PackedStringArray = _collect_states()
	_cached_states = known_states
	for selector: String in GDSS._get_gdss_nodes():
		var node: GdssNode = GDSS._get_gdss_nodes().get(selector)
		_ensure_selector(_defaults, selector, known_states)
		if node.base_type != StringName("") and node.base_type != StringName(selector):
			_defaults[selector]["base"] = String(node.base_type)
		for prop: GdssProp in node.get_enabled_props():
			_defaults[selector]["all"][prop.name] = prop.get_default_value()


func _build_composite_map(selector: String) -> Dictionary:
	if _composite_map_cache.has(selector):
		return _composite_map_cache[selector]
	var map: Dictionary = {}
	var gdss_node: GdssNode = GDSS._get_gdss_nodes().get(selector)
	if gdss_node != null:
		for prop: GdssProp in gdss_node.get_enabled_props():
			if not prop.is_composite():
				continue
			for i: int in prop.composite_of.size():
				map[prop.composite_of[i]] = {"prop": prop.name, "index": i}
	_composite_map_cache[selector] = map
	return map


func interpret(source: String) -> Dictionary[String, Dictionary]:
	return interpret_all(PackedStringArray([source]))


func interpret_all(sources: PackedStringArray) -> Dictionary[String, Dictionary]:
	globals.clear()
	_global_defaults.clear()
	_instance_defaults.clear()
	_local_vars.clear()
	var known_states: PackedStringArray = _get_known_states()
	var local_vars: Dictionary = {}
	for source: String in sources:
		var file_locals: Dictionary = _accumulate_globals(source)
		for key: String in file_locals:
			local_vars[key] = file_locals[key]
	var result: Dictionary[String, Dictionary] = {}
	for selector: String in _defaults:
		result[selector] = {}
		for state: String in _defaults[selector]:
			if _defaults[selector][state] is Dictionary:
				result[selector][state] = _defaults[selector][state].duplicate()
			else:
				result[selector][state] = _defaults[selector][state]
	for source: String in sources:
		var tokens: Array[String] = _tokenize(source)
		tokens = _substitute_globals(tokens, local_vars)
		_parse_block(tokens, 0, result, "", known_states)
	return result


func _accumulate_globals(source: String) -> Dictionary:
	var local_vars: Dictionary = {}
	var known_states: PackedStringArray = _get_known_states()
	for line: String in source.split("\n"):
		var stripped: String = _strip_line_comment(line.strip_edges())
		if stripped.is_empty():
			continue
		var gm: RegExMatch = _re_global.search(stripped)
		if gm:
			var name: String = gm.get_string(1)
			var raw: String = gm.get_string(2).strip_edges()
			var tokens: Array[String] = _tokenize_value(raw)
			var consumed: Array = _consume_value(tokens, 0, known_states)
			var val: Variant = consumed[0]
			globals[name] = val
			_global_defaults[name] = val
			continue
		var im: RegExMatch = _re_instance.search(stripped)
		if im:
			var name: String = im.get_string(1)
			var raw: String = im.get_string(2).strip_edges()
			var tokens: Array[String] = _tokenize_value(raw)
			var consumed: Array = _consume_value(tokens, 0, known_states)
			_instance_defaults[name] = consumed[0]
			continue
		var lm: RegExMatch = _re_local.search(stripped)
		if lm:
			var raw: String = lm.get_string(2).strip_edges()
			var tokens: Array[String] = _tokenize_value(raw)
			var consumed: Array = _consume_value(tokens, 0, known_states)
			local_vars[lm.get_string(1)] = consumed[0]
			_local_vars[lm.get_string(1)] = consumed[0]
	return local_vars


func _tokenize_value(raw: String) -> Array[String]:
	var tokens: Array[String] = []
	var current: String = ""
	var in_quote: bool = false
	var quote_char: String = ""
	for ch: String in raw:
		if in_quote:
			if ch == quote_char:
				in_quote = false
			current += ch
		elif ch == "\"" or ch == "'":
			in_quote = true
			quote_char = ch
			current += ch
		elif ch == "#" and not in_quote:
			break
		elif ch in ["{", "}", ":", ",", "(", ")"]:
			if not current.strip_edges().is_empty():
				tokens.append(current.strip_edges())
				current = ""
			tokens.append(ch)
		elif ch == " " or ch == "\t" or ch == ";":
			if not current.strip_edges().is_empty():
				tokens.append(current.strip_edges())
				current = ""
		else:
			current += ch
	if not current.strip_edges().is_empty():
		tokens.append(current.strip_edges())
	return tokens


func _substitute_globals(tokens: Array[String], local_vars: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for token: String in tokens:
		if token.begins_with("$"):
			var key: String = token.substr(1)
			if local_vars.has(key):
				var val: Variant = local_vars[key]
				if val is Dictionary:
					result.append("__gdss_local_method__" + key)
				else:
					result.append("__gdss_local__" + key)
				continue
			if globals.has(key):
				result.append("__gdss_global__" + key)
				continue
			if _instance_defaults.has(key):
				result.append("__gdss_instance__" + key)
				continue
		result.append(token)
	return result


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
		stripped = _strip_line_comment(stripped)
		if stripped.is_empty():
			continue
		var current: String = ""
		var in_quote: bool = false
		var quote_char: String = ""
		for ch: String in stripped:
			if in_quote:
				if ch == quote_char:
					in_quote = false
				current += ch
			elif ch == "\"" or ch == "'":
				in_quote = true
				quote_char = ch
				current += ch
			elif ch in ["{", "}", ":", ",", "(", ")"]:
				if not current.strip_edges().is_empty():
					tokens.append(current.strip_edges())
					current = ""
				tokens.append(ch)
			elif ch == " " or ch == "\t" or ch == ";":
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
		if lookahead == "(":
			var method_name: String = t
			pos += 2
			var raw_args: Array[String] = []
			var current_arg: String = ""
			var depth: int = 1
			var in_quote: bool = false
			var quote_char: String = ""
			while pos < tokens.size() and depth > 0:
				var tok: String = tokens[pos]
				if in_quote:
					if tok == quote_char:
						in_quote = false
					current_arg += tok
				elif tok == "\"" or tok == "'":
					in_quote = true
					quote_char = tok
					current_arg += tok
				elif tok == "(":
					depth += 1
					current_arg += tok
				elif tok == ")":
					depth -= 1
					if depth == 0:
						if not current_arg.strip_edges().is_empty():
							raw_args.append(current_arg.strip_edges())
					else:
						current_arg += tok
				elif tok == ",":
					if not current_arg.strip_edges().is_empty():
						raw_args.append(current_arg.strip_edges())
					current_arg = ""
				else:
					if not current_arg.is_empty():
						current_arg += " "
					current_arg += tok
				pos += 1
			return [{"__gdss_method__": method_name, "args": raw_args}, pos]
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
		var all_int_resolvable: bool = true
		for p: String in parts:
			if not p.is_valid_int() and not p.is_valid_float():
				all_numeric = false
			if not p.is_valid_int() and not p.begins_with("__gdss_global__") and not p.begins_with("__gdss_local__") and not p.begins_with("__gdss_instance__"):
				all_int_resolvable = false
		if all_numeric:
			return Vector4i(int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3]))
		if all_int_resolvable:
			return {"__gdss_composite4__": [parts[0], parts[1], parts[2], parts[3]]}
	if parts.size() == 1:
		var token: String = parts[0].trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'")
		if token.to_lower() == "true":
			return true
		if token.to_lower() == "false":
			return false
		if token.begins_with("#") and Color.html_is_valid(token):
			return Color.html(token)
		if token.is_valid_int():
			return int(token)
		if token.is_valid_float():
			return float(token)
		return token
	return " ".join(parts)


func _set_prop(result: Dictionary, selector: String, state: String, prop: String, value: Variant) -> void:
	if not result.has(selector):
		return
	if not result[selector].has(state):
		result[selector][state] = {}
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
