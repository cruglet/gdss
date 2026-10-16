@tool
class_name GdssChecker
extends RefCounted

static var _re_bad_annotation: RegEx = RegEx.create_from_string(r"^@(\w+)")
var _check_resources: Dictionary = {}
var _errors: Array[Array] = []
var _known_selectors: Dictionary[String, GdssNodeType] = {}
var _known_states: PackedStringArray = []
var _known_methods: Dictionary = {}
var _brace_depth: int = 0
var _brace_open_lines: Array[int] = []
var _frames: Array[Frame] = []
var _declared_vars: Dictionary = {}
var _file_level_vars: Dictionary = {}
var _declared_globals: Dictionary = {}
var _declared_instances: Dictionary = {}


class Frame extends RefCounted:
	var selector: String
	var type: String
	var in_event: bool
	
	func _init(p_selector: String, p_type: String, p_in_event: bool) -> void:
		selector = p_selector
		type = p_type
		in_event = p_in_event


func check_errors(source: String) -> Array[Array]:
	_errors = []
	if source.contains("="):
		_check_separator_mix(GdssAnnotations.strip_blocks(source).get("cleaned"), _errors)
	var pre: Dictionary = GdssAnnotations.strip_blocks(GdssLexer.normalize_separators(source))
	_collect_check_resources(pre.get("blocks"))
	var lines: PackedStringArray = (pre.get("cleaned") as String).split("\n")
	_begin_scan(lines)
	for line_index: int in lines.size():
		var line_text: String = GdssLexer.strip_comment(lines.get(line_index).strip_edges())
		for statement: String in GdssLexer.split_statements(line_text):
			_check_statement(statement.strip_edges(), line_index)
	for line: int in _brace_open_lines:
		_errors.append(["Unclosed brace '{'", line])
	_check_annotation_blocks(pre.get("blocks"), _declared_globals, _declared_instances, _errors)
	_check_imports(source)
	return _errors


func _begin_scan(lines: PackedStringArray) -> void:
	_known_selectors = GDSS._get_node_types()
	_known_states = GdssParser.get_known_states()
	_known_methods = GDSS._get_gdss_methods()
	_brace_depth = 0
	_brace_open_lines = []
	_frames = []
	_declared_vars = {}
	_file_level_vars = {}
	_declared_globals = {}
	_declared_instances = {}
	for line: String in lines:
		var stripped: String = GdssLexer.strip_comment(line.strip_edges())
		for declaration: RegEx in [GdssAnnotations.local_var, GdssAnnotations.global_var, GdssAnnotations.instance_var]:
			var found: RegExMatch = declaration.search(stripped)
			if found:
				_declared_vars.set(found.get_string(1), true)
				break


func _check_statement(stripped: String, line: int) -> void:
	if stripped.is_empty():
		return
	if stripped.begins_with("@global") or stripped.begins_with("@instance"):
		_check_annotated_var(stripped, line)
		return
	if stripped.begins_with("var "):
		_check_local_var(stripped, line)
		return
	if stripped.begins_with("@"):
		var annotation: RegExMatch = _re_bad_annotation.search(stripped)
		_errors.append(["Unknown annotation '@%s'" % (annotation.get_string(1) if annotation else stripped), line])
		return
	_track_braces(stripped, line)
	if stripped.ends_with("{"):
		_open_block(stripped.trim_suffix("{").strip_edges(), line)
		return
	if stripped == "}":
		return
	if _brace_depth == 0:
		_errors.append(["Unexpected token outside of any block: '%s'" % stripped, line])
		return
	if stripped.contains(":"):
		_check_property(stripped, line)
		return
	var context: String = _frame().selector
	if context.is_empty():
		_errors.append(["Stray token '%s': expected a property or block" % stripped, line])
	else:
		_errors.append(["Stray token '%s' in '%s': expected a property or block" % [stripped, context], line])


func _check_annotated_var(stripped: String, line: int) -> void:
	var is_global: bool = stripped.begins_with("@global")
	var found: RegExMatch = (GdssAnnotations.global_var if is_global else GdssAnnotations.instance_var).search(stripped)
	if not found:
		var label: String = "@global" if is_global else "@instance"
		_errors.append(["Invalid %s var declaration. Expected: %s var name: value" % [label, label], line])
		return
	var name: String = found.get_string(1)
	var value: String = found.get_string(2).strip_edges()
	if value.is_empty():
		_errors.append(["Variable '%s' has no value" % name, line])
		return
	if _file_level_vars.has(name):
		_errors.append(["Variable '%s' is already declared" % name, line])
	_file_level_vars.set(name, true)
	_declared_vars.set(name, true)
	if is_global:
		_declared_globals.set(name, true)
	else:
		_declared_instances.set(name, true)
	_check_declared_value(value, line)


func _check_local_var(stripped: String, line: int) -> void:
	var found: RegExMatch = GdssAnnotations.local_var.search(stripped)
	if not found:
		_errors.append(["Invalid var declaration. Expected: var name: value", line])
		return
	var name: String = found.get_string(1)
	var value: String = found.get_string(2).strip_edges()
	if value.is_empty():
		_errors.append(["Variable '%s' has no value" % name, line])
		return
	if _brace_depth == 0:
		if _file_level_vars.has(name):
			_errors.append(["Variable '%s' is already declared" % name, line])
		_file_level_vars.set(name, true)
	_declared_vars.set(name, true)
	_check_declared_value(value, line)


func _check_declared_value(value: String, line: int) -> void:
	if not _is_quoted_literal(value) and value.contains("("):
		_check_method_call(value, _method_name_of(value), null, _known_methods, _errors, line)


func _track_braces(stripped: String, line: int) -> void:
	for i: int in stripped.length():
		var c: String = stripped.substr(i, 1)
		if c == "{":
			_brace_depth += 1
			_brace_open_lines.append(line)
		elif c == "}":
			_brace_depth -= 1
			if _brace_depth < 0:
				_errors.append(["Unexpected closing brace '}'", line])
				_brace_depth = 0
				continue
			if not _brace_open_lines.is_empty():
				_brace_open_lines.pop_back()
			if not _frames.is_empty():
				_frames.pop_back()


func _open_block(header: String, line: int) -> void:
	var colon: int = header.find(":")
	var base_part: String = header.substr(0, colon if colon != -1 else header.length()).strip_edges()
	var state_part: String = header.substr(colon + 1).strip_edges().to_lower() if colon != -1 else ""
	var enclosing: Frame = _frame()
	var selector: String = ""
	var matched_type: String = ""
	var is_combinator: bool = false
	for raw_selector: String in base_part.split(","):
		var candidate: String = raw_selector.strip_edges()
		if candidate.is_empty():
			continue
		if candidate.begins_with(">"):
			var combinator: String = ">>" if candidate.begins_with(">>") else ">"
			var target: String = candidate.substr(combinator.length()).strip_edges()
			if _brace_depth == 1:
				_errors.append(["Combinator '%s' needs an enclosing selector to be relative to" % combinator, line])
			elif target.is_empty():
				_errors.append(["Combinator '%s' names no node type" % combinator, line])
			elif not _known_selectors.has(target):
				_errors.append(["Unknown selector '%s'" % target, line])
			else:
				matched_type = target
			is_combinator = true
			selector = combinator + target
			continue
		if _brace_depth == 1 and not _known_selectors.has(candidate):
			_errors.append(["Unknown selector '%s'" % candidate, line])
		selector = candidate
	if selector.is_empty():
		_frames.append(Frame.new(enclosing.selector, enclosing.type, enclosing.in_event))
	elif is_combinator:
		_frames.append(Frame.new(selector, matched_type if not matched_type.is_empty() else enclosing.type, selector.ends_with("()")))
	elif _brace_depth == 1 and _known_selectors.has(selector):
		_frames.append(Frame.new(selector, selector, selector.ends_with("()")))
	else:
		_frames.append(Frame.new(selector, enclosing.type, selector.ends_with("()")))
	for raw_state: String in (":" + state_part).split(",", false):
		var state_name: String = raw_state.strip_edges().trim_prefix(":").strip_edges()
		if not state_name.is_empty() and not state_name.begins_with(":") and not _known_states.has(state_name):
			_errors.append(["Unknown state ':%s'" % state_name, line])


func _check_property(stripped: String, line: int) -> void:
	var colon: int = stripped.find(":")
	var prop_name: String = stripped.substr(0, colon).strip_edges()
	var value: String = stripped.substr(colon + 1).strip_edges()
	if prop_name.is_empty():
		_errors.append(["Empty property name", line])
		return
	if value.is_empty():
		_errors.append(["Property '%s' has no value" % prop_name, line])
		return
	var frame: Frame = _frame()
	var node_type: GdssNodeType = _known_selectors.get(frame.type) if not frame.type.is_empty() else null
	if node_type == null:
		_check_untyped_value(value, line)
		return
	var resolved_name: String = GdssParser.resolve_deprecated(prop_name, line)
	var matched: GdssProp = null
	for prop: GdssProp in node_type.get_enabled_props():
		if prop.name == resolved_name or prop.composite_of.has(resolved_name) or prop.category_subproperties.has(resolved_name):
			matched = prop
			break
	if matched == null and frame.in_event and resolved_name.begins_with("transition_"):
		matched = GDSS.get_registry().property_list.get(resolved_name)
	if matched == null:
		_errors.append(["Unknown property '%s' for selector '%s'" % [prop_name, frame.selector], line])
		return
	_check_prop_value(value, matched, resolved_name, _known_methods, _declared_vars, _errors, line)


func _check_untyped_value(value: String, line: int) -> void:
	if value.begins_with("$"):
		var var_name: String = value.substr(1)
		if _is_undefined_var(var_name, _declared_vars):
			_errors.append(["Undefined variable '$%s'" % var_name, line])
	elif not _is_quoted_literal(value) and value.contains("("):
		var method_name: String = _method_name_of(value)
		if method_name == "calc":
			_check_calc_value(value, _declared_vars, _errors, line)
		else:
			_check_method_call(value, method_name, null, _known_methods, _errors, line)


func _check_imports(source: String) -> void:
	for entry: Dictionary in GdssAnnotations.collect_imports(source):
		var resolved: String = GdssAnnotations.resolve_import_path(entry.get("path"), GdssStorage.get_save_path().get_base_dir())
		if not FileAccess.file_exists(resolved):
			_errors.append(["Imported file not found: '%s'" % entry.get("path"), entry.get("line")])


func _frame() -> Frame:
	return _frames.back() if not _frames.is_empty() else Frame.new("", "", false)


func _method_name_of(call_text: String) -> String:
	return call_text.substr(0, call_text.find("(")).strip_edges()


func _is_quoted_literal(s: String) -> bool:
	return s.length() >= 2 and ((s.begins_with("\"") and s.ends_with("\"")) or (s.begins_with("'") and s.ends_with("'")))


func _is_undefined_var(var_name: String, declared_vars: Dictionary) -> bool:
	if GdssStylesheet.resources.has(var_name) or _check_resources.has(var_name):
		return false
	return not declared_vars.has(var_name) and not GdssStylesheet._global_defaults.has(var_name) and not GdssStylesheet._instance_defaults.has(var_name)


func _is_valid_color_value(val: String) -> bool:
	var clean: String = val.trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'")
	if clean.begins_with("#") and Color.html_is_valid(clean):
		return true
	if val.contains("("):
		return true
	if GdssColors.is_named(clean):
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
		GdssMethod.ParamType.ENUM:
			if not param.enum_keys.has(arg.to_upper()):
				errors.append(["Argument '%s' in '%s()' expects one of: %s, got '%s'" % [
					param.name, method_name, ", ".join(param.enum_keys), arg], line])


func _check_method_call(value_str: String, method_name: String, prop: GdssProp, known_methods: Dictionary, errors: Array[Array], line: int) -> void:
	if method_name == "calc":
		return
	if not known_methods.has(method_name):
		errors.append(["Unknown method '%s()'" % method_name, line])
		return
	
	var gdss_method: GdssMethod = known_methods.get(method_name)
	
	if prop != null and not gdss_method.supported_prop_types.is_empty():
		if not gdss_method.supported_prop_types.has(prop.type):
			errors.append(["Method '%s()' cannot be used for property type '%s'" % [method_name, GDSS.Type.find_key(prop.type)], line])
	
	var args_start: int = value_str.find("(")
	var args_end: int = value_str.rfind(")")
	if args_start == -1 or args_end == -1 or args_end <= args_start:
		errors.append(["Malformed method call '%s'" % value_str, line])
		return
	
	var args_raw: String = value_str.substr(args_start + 1, args_end - args_start - 1).strip_edges()
	var args: Array[String] = GdssLexer.split_args(args_raw)
	
	var required_count: int = 0
	for param: GdssMethod.Param in gdss_method.parameters:
		if not param.optional:
			required_count += 1
	var total_count: int = gdss_method.parameters.size()
	
	if args.size() < required_count or (not gdss_method.variadic and args.size() > total_count):
		if gdss_method.variadic:
			errors.append(["Method '%s()' expects at least %d argument(s), got %d" % [method_name, required_count, args.size()], line])
		elif required_count == total_count:
			errors.append(["Method '%s()' expects %d argument(s), got %d" % [method_name, required_count, args.size()], line])
		else:
			errors.append(["Method '%s()' expects %d-%d argument(s), got %d" % [method_name, required_count, total_count, args.size()], line])
		return
	
	for ai: int in args.size():
		if args.get(ai).contains("("):
			_check_method_call(args.get(ai), _method_name_of(args.get(ai)), null, known_methods, errors, line)
		elif not gdss_method.parameters.is_empty():
			var param_index: int = mini(ai, gdss_method.parameters.size() - 1)
			_check_method_arg_type(args.get(ai), gdss_method.parameters.get(param_index), method_name, errors, line)


func _check_calc_value(value_str: String, declared_vars: Dictionary, errors: Array[Array], line: int) -> void:
	var open_count: int = value_str.count("(")
	var close_count: int = value_str.count(")")
	if open_count != close_count:
		errors.append(["Unbalanced parentheses in calc() expression", line])
		return
	var body_start: int = value_str.find("(")
	var body: String = value_str.substr(body_start + 1, value_str.rfind(")") - body_start - 1)
	if body.strip_edges().is_empty():
		errors.append(["calc() expression is empty", line])
		return
	var tokens: Array[String] = GdssCalc.lex(body)
	if tokens.is_empty():
		errors.append(["calc() expression is empty", line])
		return
	var expect_operand: bool = true
	for t: String in tokens:
		if t == "(":
			expect_operand = true
			continue
		if t == ")":
			expect_operand = false
			continue
		if t == "+" or t == "-" or t == "*" or t == "/":
			if expect_operand and t != "+" and t != "-":
				errors.append(["calc() has a misplaced '%s' operator" % t, line])
			expect_operand = true
			continue
		if t.begins_with("$"):
			var var_name: String = t.substr(1)
			if _is_undefined_var(var_name, declared_vars):
				errors.append(["Undefined variable '$%s' in calc()" % var_name, line])
		elif not t.is_valid_float():
			errors.append(["calc() operand '%s' must be a number or $variable" % t, line])
		expect_operand = false
	if expect_operand:
		errors.append(["calc() expression is incomplete", line])


func _collect_check_resources(blocks: Array) -> void:
	_check_resources.clear()
	for block: Dictionary in blocks:
		if block.get("kind") != "resources" or block.get("malformed"):
			continue
		for entry: Dictionary in block.get("entries"):
			var value: RegExMatch = GdssAnnotations.resource_value.search(str(entry.get("value_str")).strip_edges())
			if value != null:
				_check_resources.set(entry.get("key"), {"method": value.get_string(1), "path": value.get_string(2), "args": value.get_string(3)})


func _check_config_entries(block: Dictionary, errors: Array[Array]) -> void:
	var seen: Dictionary = {}
	for entry: Dictionary in block.get("entries"):
		var key: String = entry.get("key")
		var line: int = entry.get("line")
		var raw: String = str(entry.get("value_str")).strip_edges()
		var kind: String = GDSS.CONFIG_KEYS.get(key, "")
		if kind.is_empty():
			errors.append(["Unknown @config key '%s'. Expected one of: %s" % [key, ", ".join(GDSS.CONFIG_KEYS.keys())], line])
			continue
		if seen.has(key):
			errors.append(["@config key '%s' is set more than once" % key, line])
		seen.set(key, true)
		if raw.is_empty():
			errors.append(["@config key '%s' has no value" % key, line])
			continue
		match kind:
			"bool":
				if not ["true", "false", "1", "0"].has(raw.to_lower()):
					errors.append(["@config '%s' expects true or false, got '%s'" % [key, raw], line])
			"float":
				if not GDSS.config_string(raw).is_valid_float():
					errors.append(["@config '%s' expects a number, got '%s'" % [key, raw], line])
			"BlurQuality":
				if not GDSS.BlurQuality.keys().has(GDSS.config_string(raw).to_upper()):
					errors.append(["@config '%s' expects one of: %s" % [key, ", ".join(GDSS.BlurQuality.keys())], line])


func _check_resource_entries(block: Dictionary, errors: Array[Array]) -> void:
	var methods: PackedStringArray = GdssAnnotations.resource_methods()
	var seen: Dictionary = {}
	for entry: Dictionary in block.get("entries"):
		var key: String = entry.get("key")
		var line: int = entry.get("line")
		var raw_value: String = str(entry.get("value_str")).strip_edges()
		if not key.is_valid_identifier():
			errors.append(["'%s' is not a valid resource key" % key, line])
			continue
		if seen.has(key):
			errors.append(["Resource '%s' is already declared" % key, line])
		seen.set(key, true)
		if raw_value.is_empty():
			errors.append(["Resource '%s' has no value. Expected: %s: font(\"res://...\")" % [key, key], line])
			continue
		var value: RegExMatch = GdssAnnotations.resource_value.search(raw_value)
		if value == null:
			errors.append(["Resource '%s' expects a loader call, like font(\"res://...\")" % key, line])
			continue
		var method_name: String = value.get_string(1)
		var path: String = value.get_string(2)
		if not methods.has(method_name):
			errors.append(["'%s()' does not load a resource. Expected one of: %s" % [method_name, ", ".join(methods)], line])
			continue
		if path.is_empty():
			errors.append(["Resource '%s' has no path" % key, line])
		elif not ResourceLoader.exists(path):
			errors.append(["Resource '%s' points at a missing file: %s" % [key, path], line])
		elif not _loads_as(path, method_name):
			errors.append(["Resource '%s' is not a valid %s(): %s" % [key, method_name, path], line])


func _loads_as(path: String, method_name: String) -> bool:
	var method: GdssMethod = GDSS._get_gdss_methods().get(method_name)
	if method == null:
		return false
	var args: Array[Variant] = [path]
	return method.call_method(args) != null


func _resource_entry(name: String) -> Dictionary:
	if _check_resources.has(name):
		return _check_resources.get(name)
	return GdssStylesheet.resources.get(name, {})


func _check_resource_use(name: String, entry: Dictionary, prop_name: String, actual_type: GDSS.Type, known_methods: Dictionary, errors: Array[Array], line: int) -> void:
	var method: GdssMethod = known_methods.get(entry.get("method"))
	if method == null or method.supported_prop_types.has(actual_type):
		return
	errors.append(["Resource '$%s' is a %s(), which property '%s' cannot take" % [name, method.method_name, prop_name], line])


func _check_prop_value(value_str: String, prop: GdssProp, prop_name: String, known_methods: Dictionary, declared_vars: Dictionary, errors: Array[Array], line: int) -> void:
	var is_component: bool = prop.composite_of.has(prop_name)
	var is_color_component: bool = is_component and prop.type == GDSS.Type.COLOR
	if not _is_quoted_literal(value_str) and value_str.contains("("):
		if is_component and not is_color_component:
			errors.append(["Component property '%s' expects a plain value, not a method call" % prop_name, line])
			return
		var method_name: String = _method_name_of(value_str)
		if method_name == "calc":
			_check_calc_value(value_str, declared_vars, errors, line)
			return
		_check_method_call(value_str, method_name, prop, known_methods, errors, line)
		return
	
	var actual_type: GDSS.Type = prop.type
	if is_component and not is_color_component:
		actual_type = GDSS.Type.FLOAT if prop.type == GDSS.Type.VECTOR2 else GDSS.Type.INT
	
	if actual_type == GDSS.Type.COMPOSITE4:
		var parts: PackedStringArray = value_str.replace("\t", " ").split(" ", false)
		if parts.size() != 1 and parts.size() != 4:
			errors.append(["Property '%s' expects 1 or 4 integer values, got %d" % [prop_name, parts.size()], line])
			return
		for part: String in parts:
			if part.begins_with("$"):
				var var_name: String = part.substr(1)
				if not _resource_entry(var_name).is_empty():
					errors.append(["Resource '$%s' cannot be a component of '%s'" % [var_name, prop_name], line])
				elif _is_undefined_var(var_name, declared_vars):
					errors.append(["Undefined variable '$%s'" % var_name, line])
			elif not part.is_valid_int():
				errors.append(["Property '%s' expects all integer components, got '%s'" % [prop_name, part], line])
		return
	
	if actual_type == GDSS.Type.VECTOR2:
		var parts: PackedStringArray = value_str.replace("\t", " ").split(" ", false)
		if parts.is_empty() or parts.size() > 2:
			errors.append(["Property '%s' expects 1 or 2 numeric values, got %d" % [prop_name, parts.size()], line])
			return
		for part: String in parts:
			if part.begins_with("$"):
				var var_name: String = part.substr(1)
				if not _resource_entry(var_name).is_empty():
					errors.append(["Resource '$%s' cannot be a component of '%s'" % [var_name, prop_name], line])
				elif _is_undefined_var(var_name, declared_vars):
					errors.append(["Undefined variable '$%s'" % var_name, line])
			elif not GdssParser.is_numeric_token(part):
				errors.append(["Property '%s' expects numeric components, got '%s'" % [prop_name, part], line])
		return
	
	if value_str.begins_with("$"):
		var var_name: String = value_str.substr(1)
		var entry: Dictionary = _resource_entry(var_name)
		if not entry.is_empty():
			_check_resource_use(var_name, entry, prop_name, actual_type, known_methods, errors, line)
			return
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
			if prop_name == "transition_time" and GdssParser.scoped_duration(GdssLexer.tokenize_value(value_str)) != null:
				pass
			elif not GdssParser.is_numeric_token(value_str):
				errors.append(["Property '%s' expects a float value, got '%s'" % [prop_name, value_str], line])
		GDSS.Type.AUDIO:
			errors.append(["Property '%s' expects sound(\"res://...\") or a $resource, got '%s'" % [prop_name, value_str], line])
		GDSS.Type.BOOLEAN:
			if value_str.to_lower() not in ["true", "false", "1", "0"]:
				errors.append(["Property '%s' expects a boolean (true/false), got '%s'" % [prop_name, value_str], line])
		GDSS.Type.COLOR:
			if not _is_valid_color_value(value_str):
				errors.append(["Property '%s' expects a color value (#hex, named color, or method), got '%s'" % [prop_name, value_str], line])


func _check_annotation_blocks(blocks: Array, declared_globals: Dictionary, declared_instances: Dictionary, errors: Array[Array]) -> void:
	var scheme_names: Dictionary = {}
	var scheme_parents: Dictionary = {}
	var scheme_lines: Dictionary = {}
	var default_scheme: String = ""
	var default_line: int = -1
	for block: Dictionary in blocks:
		var label: String = "@" + str(block.get("kind")) if block.get("kind") != "meta" else "@meta"
		if block.get("malformed"):
			errors.append(["Expected '{' on the same line as %s" % label, block.get("header_line")])
			continue
		if block.get("unterminated", false):
			errors.append(["Unclosed brace '{' on %s block" % label, block.get("header_line")])
			continue
		if block.get("kind") == "config":
			_check_config_entries(block, errors)
			continue
		if block.get("kind") == "resources":
			_check_resource_entries(block, errors)
			continue
		if block.get("kind") == "scheme":
			scheme_names.set(block.get("name"), true)
			var block_parent: String = str(block.get("parent", ""))
			if not block_parent.is_empty():
				scheme_parents.set(block.get("name"), block_parent)
				scheme_lines.set(block.get("name"), block.get("header_line"))
			for entry: Dictionary in block.get("entries"):
				var value_str: String = entry.get("value_str")
				if value_str.is_empty():
					errors.append(["Scheme variable '%s' has no value" % entry.get("key"), entry.get("line")])
					continue
				if not declared_globals.has(entry.get("key")) and not declared_instances.has(entry.get("key")) and not GdssStylesheet._global_defaults.has(entry.get("key")) and not GdssStylesheet._instance_defaults.has(entry.get("key")):
					errors.append(["Scheme '%s' overrides '%s', which is not an @global or @instance var." % [block.get("name"), entry.get("key")], entry.get("line")])
				if value_str.begins_with("$"):
					errors.append(["Scheme value for '%s' must be a literal; variable references aren't supported inside schemes." % entry.get("key"), entry.get("line")])
		else:
			for entry: Dictionary in block.get("entries"):
				if (entry.get("value_str") as String).is_empty():
					errors.append(["Metadata key '%s' has no value" % entry.get("key"), entry.get("line")])
				elif entry.get("key") == "default_scheme":
					default_scheme = GdssAnnotations.parse_meta_value(entry.get("value_str"))
					default_line = entry.get("line")
	for scheme_name: String in scheme_parents:
		var parent: String = str(scheme_parents.get(scheme_name))
		var line: int = int(scheme_lines.get(scheme_name, 0))
		if parent == scheme_name:
			errors.append(["@scheme '%s' cannot extend itself" % scheme_name, line])
			continue
		if not scheme_names.has(parent):
			errors.append(["@scheme '%s' extends unknown scheme '%s'" % [scheme_name, parent], line])
			continue
		var seen: Dictionary = {scheme_name: true}
		var current: String = parent
		while scheme_parents.has(current):
			if seen.has(current):
				errors.append(["@scheme '%s' has a circular extends chain" % scheme_name, line])
				break
			seen.set(current, true)
			current = str(scheme_parents.get(current))
	if not default_scheme.is_empty() and not scheme_names.has(default_scheme):
		errors.append(["@meta default_scheme '%s' is not a defined @scheme" % default_scheme, default_line])


func _line_separator(stripped: String) -> String:
	if stripped.is_empty() or stripped.ends_with("{") or stripped == "}":
		return ""
	var at: int = GdssLexer.find_unquoted(stripped, ":=")
	if at <= 0 or stripped.substr(0, at).strip_edges().is_empty():
		return ""
	return stripped.substr(at, 1)


func _check_separator_mix(source: String, errors: Array[Array]) -> void:
	var uses_colon: bool = false
	var uses_equals: bool = false
	var mix_line: int = -1
	var lines: PackedStringArray = source.split("\n")
	for i: int in lines.size():
		for stmt: String in GdssLexer.split_statements(GdssLexer.strip_comment(lines.get(i).strip_edges())):
			var sep: String = _line_separator(stmt.strip_edges())
			if sep == ":":
				uses_colon = true
			elif sep == "=":
				uses_equals = true
		if uses_colon and uses_equals and mix_line == -1:
			mix_line = i
	if uses_colon and uses_equals:
		errors.append(["This file mixes ':' and '=' separators. Use one or the other.", maxi(mix_line, 0)])
