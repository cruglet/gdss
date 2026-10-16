@tool
class_name GdssParser
extends RefCounted

const _OVERRIDE_SELECTOR: String = "__override__"

static var _cached_states: PackedStringArray = []
static var _composite_map: Dictionary = {}
static var _override_entry_cache: Dictionary = {}
static var _patch_composites: bool = false
const DEPRECATED_PROPERTIES: Dictionary[String, String] = {
	"font_skew": "char_skew",
	"font_skew_x": "char_skew_x",
	"font_skew_y": "char_skew_y",
}
static var _deprecation_notices: Dictionary[String, bool] = {}


static func get_known_states() -> PackedStringArray:
	if not _cached_states.is_empty():
		return _cached_states
	_cached_states = _collect_states()
	return _cached_states


static func _collect_states() -> PackedStringArray:
	var states: PackedStringArray = []
	for node: GdssNodeType in GDSS._get_node_types().values():
		for variant: String in node.states:
			if not states.has(variant):
				states.append(variant)
	return states


static func parse_override_entry(text: String) -> Dictionary:
	if text.strip_edges().is_empty():
		return {}
	var cached: Variant = _override_entry_cache.get(text)
	if cached is Dictionary:
		return cached
	var known_states: PackedStringArray = get_known_states()
	var tokens: Array[String] = _substitute_globals(GdssLexer.tokenize(GdssLexer.normalize_separators(text)), GdssStylesheet._local_vars)
	var container: Dictionary = {}
	_ensure_selector(container, _OVERRIDE_SELECTOR, known_states)
	_patch_composites = true
	_parse_block(tokens, 0, container, _OVERRIDE_SELECTOR, known_states, true)
	_patch_composites = false
	var entry: Dictionary = container.get(_OVERRIDE_SELECTOR, {})
	entry.erase(GdssValue.CLASSES_KEY)
	entry.erase(GdssValue.VARIATIONS_KEY)
	entry.erase(GdssValue.DESCENDANTS_KEY)
	entry.erase(GdssValue.VARS_KEY)
	if _override_entry_cache.size() > 512:
		_override_entry_cache.clear()
	_override_entry_cache.set(text, entry)
	return entry


static func _get_composite_map() -> Dictionary:
	if not _composite_map.is_empty():
		return _composite_map
	for prop: GdssProp in GDSS.get_registry().property_list.values():
		if not prop.is_composite():
			continue
		for i: int in prop.composite_of.size():
			_composite_map.set(prop.composite_of.get(i), {"prop": prop.name, "index": i})
	return _composite_map


static func parse(source: String) -> Dictionary[String, Dictionary]:
	var seen: Dictionary = {}
	return parse_all(GdssAnnotations.gather_import_sources(source, GdssStorage.get_save_path().get_base_dir(), seen))


static func parse_paths(paths: PackedStringArray) -> Dictionary[String, Dictionary]:
	var seen: Dictionary = {}
	var gathered: PackedStringArray = []
	for path: String in paths:
		gathered.append_array(GdssAnnotations.gather_import_sources(GdssStorage.read_source(path), path.get_base_dir(), seen))
	return parse_all(gathered)


static func parse_all(sources: PackedStringArray) -> Dictionary[String, Dictionary]:
	GdssStylesheet.has_descendant_rules = false
	GdssStylesheet.globals.clear()
	GdssStylesheet._global_defaults.clear()
	GdssStylesheet._instance_defaults.clear()
	GdssStylesheet._local_vars.clear()
	GdssStylesheet.schemes.clear()
	GdssStylesheet.resources.clear()
	GdssStylesheet.config.clear()
	GdssStylesheet.meta.clear()
	_override_entry_cache.clear()
	var known_states: PackedStringArray = get_known_states()
	var cleaned_sources: PackedStringArray = []
	for source: String in sources:
		var pre: Dictionary = GdssAnnotations.strip_blocks(GdssLexer.normalize_separators(source))
		cleaned_sources.append(pre.get("cleaned"))
		GdssAnnotations.accumulate_blocks(pre.get("blocks"), known_states)
	var local_vars: Dictionary = {}
	for source: String in cleaned_sources:
		var file_locals: Dictionary = GdssAnnotations.accumulate_globals(source)
		for key: String in file_locals:
			local_vars.set(key, file_locals.get(key))
	GdssStylesheet._instance_scheme_base = GdssStylesheet._instance_defaults.duplicate(true)
	var result: Dictionary[String, Dictionary] = {}
	_patch_composites = true
	for source: String in cleaned_sources:
		var tokens: Array[String] = GdssLexer.tokenize(source)
		tokens = _substitute_globals(tokens, local_vars)
		_parse_block(tokens, 0, result, "", known_states)
	_patch_composites = false
	for selector: String in result:
		GdssValue.resolve_base_composite_patches(result.get(selector))
	GDSS.reset_config()
	for key: String in GdssStylesheet.global_overrides:
		GdssStylesheet.globals.set(key, GdssStylesheet.global_overrides.get(key))
	return result


static func _substitute_globals(tokens: Array[String], local_vars: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for token: String in tokens:
		if token.begins_with("$"):
			var key: String = token.substr(1)
			if GdssStylesheet.resources.has(key):
				var entry: Dictionary = GdssStylesheet.resources.get(key)
				result.append(str(entry.get("method")))
				result.append("(")
				result.append("\"%s\"" % entry.get("path"))
				for part: String in str(entry.get("args", "")).split(",", false):
					result.append(",")
					result.append(part.strip_edges())
				result.append(")")
				continue
			if local_vars.has(key):
				var val: Variant = local_vars.get(key)
				if val is Dictionary:
					result.append(GdssValue.LOCAL_METHOD_REF + key)
				else:
					result.append(GdssValue.LOCAL_REF + key)
				continue
			if GdssStylesheet.globals.has(key):
				result.append(GdssValue.GLOBAL_REF + key)
				continue
			if GdssStylesheet._instance_defaults.has(key):
				result.append(GdssValue.INSTANCE_REF + key)
				continue
			result.append(GdssValue.LOCAL_REF + key)
			continue
		result.append(token)
	return result


static func _collect_selector_group(tokens: Array[String], pos: int, known_states: PackedStringArray) -> Array:
	var selectors: Array[String] = []
	while pos < tokens.size():
		var token: String = tokens.get(pos)
		if token == "{":
			break
		if token == ",":
			pos += 1
			continue
		if token == ":" or token == "::":
			var next: String = tokens.get(pos + 1) if pos + 1 < tokens.size() else ""
			selectors.append(token + next)
			pos += 2
			continue
		if token == ">" or token == ">>":
			var next: String = tokens.get(pos + 1) if pos + 1 < tokens.size() else ""
			selectors.append(token + next)
			pos += 2
			continue
		selectors.append(token)
		pos += 1
	return [selectors, pos]


static func _ensure_selector(result: Dictionary, selector: String, _known_states: PackedStringArray) -> void:
	if result.has(selector):
		return
	result.set(selector, {"all": {}, GdssValue.CLASSES_KEY: {}})


static func _parse_block(tokens: Array[String], pos: int, result: Dictionary, parent_selector: String, known_states: PackedStringArray, owner_is_base_type: bool = false) -> int:
	while pos < tokens.size():
		var token: String = tokens.get(pos)
		if token == "}":
			return pos + 1
		
		var next: String = tokens.get(pos + 1) if pos + 1 < tokens.size() else ""
		var next2: String = tokens.get(pos + 2) if pos + 2 < tokens.size() else ""
		
		if token == "var" and next2 == ":" and not next.is_empty():
			if parent_selector.is_empty():
				var skip: Array = consume_value(tokens, pos + 3, known_states)
				pos = skip.get(1)
				continue
			_ensure_selector(result, parent_selector, known_states)
			var declared: Array = consume_value(tokens, pos + 3, known_states)
			_get_vars_container(result, parent_selector).set(next, declared.get(0))
			pos = declared.get(1)
			continue
		
		var is_comma_group: bool = _has_comma_before_brace(tokens, pos)
		
		if is_comma_group:
			var collected: Array = _collect_selector_group(tokens, pos, known_states)
			var selectors: Array[String] = collected.get(0)
			var block_start: int = collected.get(1) + 1
			var block_end: int = _find_block_end(tokens, block_start)
			var block_tokens: Array[String] = tokens.slice(block_start, block_end - 1)
			for raw_selector: String in selectors:
				if raw_selector.begins_with(":"):
					var state: String = raw_selector.substr(1).to_lower()
					if not parent_selector.is_empty():
						_ensure_selector(result, parent_selector, known_states)
						_parse_props_into(block_tokens, 0, result, parent_selector, state, known_states)
				elif raw_selector.begins_with(">"):
					if not parent_selector.is_empty():
						var desc_container: Dictionary = _get_descendant_container(result, parent_selector)
						_ensure_selector(desc_container, raw_selector, known_states)
						_parse_block(block_tokens, 0, desc_container, raw_selector, known_states, true)
						GdssStylesheet.has_descendant_rules = true
				else:
					var child_container: Dictionary = _get_child_container(result, parent_selector)
					_ensure_selector(child_container, raw_selector, known_states)
					if not parent_selector.is_empty() and not owner_is_base_type:
						_inherit(child_container, raw_selector, result.get(parent_selector))
					_parse_block(block_tokens, 0, child_container, raw_selector, known_states, parent_selector.is_empty())
			pos = block_end
			continue
		
		if token == ">" or token == ">>":
			if parent_selector.is_empty() or next.is_empty() or next == "{":
				var stray: int = pos + 1 if next == "{" else pos + 2
				if stray < tokens.size() and tokens.get(stray) == "{":
					pos = _find_block_end(tokens, stray + 1)
				else:
					pos += 1
				continue
			var desc_key: String = token + next
			var after: String = tokens.get(pos + 2) if pos + 2 < tokens.size() else ""
			var desc_container: Dictionary = _get_descendant_container(result, parent_selector)
			_ensure_selector(desc_container, desc_key, known_states)
			GdssStylesheet.has_descendant_rules = true
			if after == "{":
				pos = _parse_block(tokens, pos + 3, desc_container, desc_key, known_states, true)
			elif after == ":" and pos + 4 < tokens.size() and tokens.get(pos + 4) == "{":
				pos = _parse_props_into(tokens, pos + 5, desc_container, desc_key, tokens.get(pos + 3).to_lower(), known_states)
			else:
				pos += 2
			continue
		
		if next == "(":
			var close: int = pos + 2
			while close < tokens.size() and tokens.get(close) != ")":
				close += 1
			if not parent_selector.is_empty() and close + 1 < tokens.size() and tokens.get(close + 1) == "{":
				_ensure_selector(result, parent_selector, known_states)
				pos = _parse_props_into(tokens, close + 2, result, parent_selector, token + "()", known_states)
			else:
				pos = close + 1
			continue
		
		if (next == ":" or next == "::") and next2 != "" and next2 != "{" and pos + 3 < tokens.size() and tokens.get(pos + 3) == "{":
			var is_variation: bool = token.begins_with("%") and not parent_selector.is_empty()
			var child_name: String = token.substr(1) if is_variation else token
			var child_container: Dictionary = _get_variation_container(result, parent_selector) if is_variation else _get_child_container(result, parent_selector)
			_ensure_selector(child_container, child_name, known_states)
			pos = _parse_props_into(tokens, pos + 4, child_container, child_name, next.trim_prefix(":") + next2.to_lower(), known_states)
			continue
		
		if (token == ":" or token == "::") and next2 == "{":
			if not parent_selector.is_empty():
				_ensure_selector(result, parent_selector, known_states)
				pos = _parse_props_into(tokens, pos + 3, result, parent_selector, token.trim_prefix(":") + next.to_lower(), known_states)
			else:
				pos += 3
			continue
		
		if next == "{":
			var is_variation: bool = token.begins_with("%") and not parent_selector.is_empty()
			var child_name: String = token.substr(1) if is_variation else token
			var child_container: Dictionary = _get_variation_container(result, parent_selector) if is_variation else _get_child_container(result, parent_selector)
			_ensure_selector(child_container, child_name, known_states)
			if not parent_selector.is_empty() and not owner_is_base_type:
				_inherit(child_container, child_name, result.get(parent_selector))
			pos = _parse_block(tokens, pos + 2, child_container, child_name, known_states, parent_selector.is_empty())
			continue
		
		if next == ":":
			if not parent_selector.is_empty() and next2 != "" and next2 != "{":
				_ensure_selector(result, parent_selector, known_states)
				var consumed: Array = consume_value(tokens, pos + 2, known_states)
				_set_prop(result, parent_selector, "all", token, consumed.get(0))
				pos = consumed.get(1)
			else:
				pos += 2
			continue
		
		pos += 1
	
	return pos


static func _get_child_container(result: Dictionary, parent_selector: String) -> Dictionary:
	if parent_selector.is_empty():
		return result
	if not result.get(parent_selector).has(GdssValue.CLASSES_KEY):
		result.get(parent_selector).set(GdssValue.CLASSES_KEY, {})
	return result.get(parent_selector).get(GdssValue.CLASSES_KEY)


static func _get_variation_container(result: Dictionary, parent_selector: String) -> Dictionary:
	if parent_selector.is_empty():
		return result
	if not result.get(parent_selector).has(GdssValue.VARIATIONS_KEY):
		result.get(parent_selector).set(GdssValue.VARIATIONS_KEY, {})
	return result.get(parent_selector).get(GdssValue.VARIATIONS_KEY)


static func _get_vars_container(result: Dictionary, parent_selector: String) -> Dictionary:
	if parent_selector.is_empty():
		return {}
	if not result.get(parent_selector).has(GdssValue.VARS_KEY):
		result.get(parent_selector).set(GdssValue.VARS_KEY, {})
	return result.get(parent_selector).get(GdssValue.VARS_KEY)


static func _get_descendant_container(result: Dictionary, parent_selector: String) -> Dictionary:
	if parent_selector.is_empty():
		return result
	if not result.get(parent_selector).has(GdssValue.DESCENDANTS_KEY):
		result.get(parent_selector).set(GdssValue.DESCENDANTS_KEY, {})
	return result.get(parent_selector).get(GdssValue.DESCENDANTS_KEY)


static func _has_comma_before_brace(tokens: Array[String], pos: int) -> bool:
	var i: int = pos
	while i < tokens.size():
		if tokens.get(i) == "{":
			return false
		if tokens.get(i) == "}":
			return false
		if tokens.get(i) == ":":
			var after: String = tokens.get(i + 1) if i + 1 < tokens.size() else ""
			if after != "{" and after != "":
				var after2: String = tokens.get(i + 2) if i + 2 < tokens.size() else ""
				if after2 != "{" and after2 != ",":
					return false
		if tokens.get(i) == ",":
			return true
		i += 1
	return false


static func _find_block_end(tokens: Array[String], pos: int) -> int:
	var depth: int = 1
	while pos < tokens.size():
		if tokens.get(pos) == "{":
			depth += 1
		elif tokens.get(pos) == "}":
			depth -= 1
			if depth == 0:
				return pos + 1
		pos += 1
	return pos


static func _parse_props_into(tokens: Array[String], pos: int, result: Dictionary, selector: String, state: String, known_states: PackedStringArray) -> int:
	while pos < tokens.size():
		var token: String = tokens.get(pos)
		if token == "}":
			return pos + 1
		
		var next: String = tokens.get(pos + 1) if pos + 1 < tokens.size() else ""
		var next2: String = tokens.get(pos + 2) if pos + 2 < tokens.size() else ""
		
		if (token == ">" or token == ">>") and next2 == "{" and not next.is_empty():
			var desc_container: Dictionary = _get_descendant_container(result, selector)
			var desc_key: String = token + next
			_ensure_selector(desc_container, desc_key, known_states)
			GdssStylesheet.has_descendant_rules = true
			pos = _parse_props_into(tokens, pos + 3, desc_container, desc_key, GdssValue.ANCESTOR_STATE_PREFIX + state, known_states)
			continue
		
		if next == "{":
			pos = _find_block_end(tokens, pos + 2)
			continue
		
		if next == ":":
			if next2 != "" and next2 != "{":
				var consumed: Array = consume_value(tokens, pos + 2, known_states)
				_set_prop(result, selector, state, token, consumed.get(0))
				pos = consumed.get(1)
			else:
				pos += 2
			continue
		
		pos += 1
	
	return pos


static func consume_value(tokens: Array[String], pos: int, known_states: PackedStringArray) -> Array:
	var parts: Array[String] = []
	while pos < tokens.size():
		var t: String = tokens.get(pos)
		if t == "{" or t == "}":
			break
		if t == ">" or t == ">>":
			break
		if t == "var" and not parts.is_empty() and pos + 2 < tokens.size() and tokens.get(pos + 2) == ":":
			break
		var lookahead: String = tokens.get(pos + 1) if pos + 1 < tokens.size() else ""
		var lookahead2: String = tokens.get(pos + 2) if pos + 2 < tokens.size() else ""
		if lookahead == "(":
			if parts.is_empty():
				if t == "calc":
					return GdssCalc.parse(tokens, pos)
				return _parse_method_call(tokens, pos)
			break
		if lookahead == "{":
			break
		if lookahead == ",":
			break
		if lookahead == "::" or (lookahead == ":" and (lookahead2 == "{" or known_states.has(lookahead2.to_lower()))):
			parts.append(t)
			pos += 1
			break
		if lookahead == ":" and not parts.is_empty():
			break
		parts.append(t)
		pos += 1
	return [_parse_value(parts), pos]


static func _parse_method_call(tokens: Array[String], pos: int) -> Array:
	var method_name: String = tokens.get(pos)
	pos += 2
	var args: Array = []
	var current_parts: Array[String] = []
	while pos < tokens.size():
		var tok: String = tokens.get(pos)
		if tok == ")":
			pos += 1
			break
		if tok == ",":
			if not current_parts.is_empty():
				args.append(" ".join(current_parts))
				current_parts = []
			pos += 1
			continue
		var nxt: String = tokens.get(pos + 1) if pos + 1 < tokens.size() else ""
		if nxt == "(":
			var nested: Array = _parse_method_call(tokens, pos)
			args.append(nested.get(0))
			pos = nested.get(1)
			continue
		current_parts.append(tok)
		pos += 1
	if not current_parts.is_empty():
		args.append(" ".join(current_parts))
	return [{GdssValue.METHOD_KEY: method_name, "args": args}, pos]


static func _inherit(result: Dictionary, child: String, parent_data: Dictionary) -> void:
	for state: String in parent_data:
		if state == GdssValue.CLASSES_KEY or state == GdssValue.VARIATIONS_KEY or state == GdssValue.DESCENDANTS_KEY or state == GdssValue.VARS_KEY:
			continue
		if not parent_data.get(state) is Dictionary:
			continue
		if not result.get(child).has(state):
			result.get(child).set(state, {})
		for prop: String in parent_data.get(state):
			if prop == "transition_time":
				result.get(child).get(state).set(prop, GdssValue.merge_scoped_time(
					parent_data.get(state).get(prop), result.get(child).get(state).get(prop)))
				continue
			if not result.get(child).get(state).has(prop):
				result.get(child).get(state).set(prop, parent_data.get(state).get(prop))


static func _parse_value(parts: Array[String]) -> Variant:
	if parts.is_empty():
		return ""
	var scoped: Variant = scoped_duration(parts)
	if scoped != null:
		return scoped
	if parts.size() == 4:
		var all_numeric: bool = true
		var all_int_resolvable: bool = true
		for p: String in parts:
			if not p.is_valid_int() and not p.is_valid_float():
				all_numeric = false
			if not p.is_valid_int() and not p.begins_with(GdssValue.GLOBAL_REF) and not p.begins_with(GdssValue.LOCAL_REF) and not p.begins_with(GdssValue.INSTANCE_REF):
				all_int_resolvable = false
		if all_numeric:
			return Vector4i(int(parts.get(0)), int(parts.get(1)), int(parts.get(2)), int(parts.get(3)))
		if all_int_resolvable:
			return {GdssValue.COMPOSITE4_KEY: [parts.get(0), parts.get(1), parts.get(2), parts.get(3)]}
	if parts.size() == 2:
		var both_numeric: bool = true
		var both_float_resolvable: bool = true
		for p: String in parts:
			if not p.is_valid_float():
				both_numeric = false
				if not p.begins_with(GdssValue.GLOBAL_REF) and not p.begins_with(GdssValue.LOCAL_REF) and not p.begins_with(GdssValue.INSTANCE_REF):
					both_float_resolvable = false
		if both_numeric:
			return Vector2(float(parts.front()), float(parts.back()))
		if both_float_resolvable:
			return {GdssValue.COMPOSITE2_KEY: [parts.front(), parts.back()]}
	if parts.size() == 1:
		var token: String = parts.get(0).trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'")
		if token.to_lower() == "true":
			return true
		if token.to_lower() == "false":
			return false
		if token.begins_with("#") and Color.html_is_valid(token):
			return Color.html(token)
		var angle: Variant = _angle_literal(token)
		if angle != null:
			return angle
		if token.is_valid_int():
			return int(token)
		if token.is_valid_float():
			return float(token)
		return token
	return " ".join(parts)


static func scoped_duration(parts: Array[String]) -> Variant:
	if parts.size() != 2 or not is_numeric_token(parts.get(0)):
		return null
	var listed: String = parts.get(1)
	var quoted: bool = (listed.begins_with("\"") and listed.ends_with("\"")) \
		or (listed.begins_with("'") and listed.ends_with("'"))
	if not quoted or listed.length() < 2:
		return null
	var seconds: float = float(_angle_literal(parts.get(0)) if _angle_literal(parts.get(0)) != null else parts.get(0).to_float())
	var map: Dictionary = {}
	for name: String in listed.substr(1, listed.length() - 2).split(" ", false):
		map.set(resolve_property(name.strip_edges()), seconds)
	return null if map.is_empty() else {GdssValue.SCOPED_TIME_KEY: map}


static func _angle_literal(token: String) -> Variant:
	for suffix: String in ["deg", "rad"]:
		if not token.ends_with(suffix):
			continue
		var number: String = token.substr(0, token.length() - suffix.length())
		if number.is_empty() or not number.is_valid_float():
			continue
		return deg_to_rad(float(number)) if suffix == "deg" else float(number)
	return null


static func is_numeric_token(token: String) -> bool:
	return token.is_valid_float() or _angle_literal(token) != null


static func resolve_property(name: String) -> String:
	return DEPRECATED_PROPERTIES.get(name, name)


static func resolve_deprecated(name: String, line: int) -> String:
	if not DEPRECATED_PROPERTIES.has(name):
		return name
	var replacement: String = DEPRECATED_PROPERTIES.get(name)
	if not _deprecation_notices.has(name):
		_deprecation_notices.set(name, true)
		push_warning("[GDSS] '%s' is deprecated, use '%s' instead (line %d)." % [name, replacement, line + 1])
	return replacement


static func _set_prop(result: Dictionary, selector: String, state: String, prop: String, value: Variant) -> void:
	prop = resolve_property(prop)
	if not result.has(selector):
		return
	if not result.get(selector).has(state):
		result.get(selector).set(state, {})
	var composite_map: Dictionary = _get_composite_map()
	if composite_map.has(prop):
		var info: Dictionary = composite_map.get(prop)
		GdssValue.fold_composite_component(result.get(selector).get(state), info.get("prop"), info.get("index"), value, _patch_composites)
		return
	var registered: GdssProp = GDSS.get_registry().property_list.get(prop)
	if registered != null:
		if value is String and not (value as String).begins_with(GdssValue.REF_PREFIX):
			match registered.type:
				GDSS.Type.CURSOR, GDSS.Type.TRANSITION_TYPE, GDSS.Type.TRANSITION_FUNC:
					value = (value as String).to_upper()
		elif registered.type == GDSS.Type.VECTOR2 and (value is int or value is float):
			value = Vector2(float(value), float(value))
		elif registered.type == GDSS.Type.COMPOSITE4 and (value is int or value is float):
			value = Vector4i(int(value), int(value), int(value), int(value))
	if prop == "transition_time":
		value = GdssValue.merge_scoped_time(result.get(selector).get(state).get(prop), value)
	result.get(selector).get(state).set(prop, value)


static func reset_known_states() -> void:
	_cached_states.clear()
