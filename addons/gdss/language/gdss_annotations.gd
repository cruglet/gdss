@tool
class_name GdssAnnotations
extends RefCounted

static var global_var: RegEx = RegEx.create_from_string(r"^@global\s+var\s+(\w+)\s*:\s*(.+)")
static var instance_var: RegEx = RegEx.create_from_string(r"^@instance\s+var\s+(\w+)\s*:\s*(.+)")
static var local_var: RegEx = RegEx.create_from_string(r"^var\s+(\w+)\s*:\s*(.+)")
static var scheme_header: RegEx = RegEx.create_from_string(r"^@scheme\s+(\w+)(?:\s+extends\s+(\w+))?")
static var meta_header: RegEx = RegEx.create_from_string(r"^@meta\b")
static var import_line: RegEx = RegEx.create_from_string(r"^@import\s+([\"'])(.+?)\1")
static var resources_header: RegEx = RegEx.create_from_string(r"^@resources\b")
static var config_header: RegEx = RegEx.create_from_string(r"^@config\b")
static var resource_value: RegEx = RegEx.create_from_string(r"^(\w+)\s*\(\s*[\"'](.*?)[\"']\s*(?:,\s*(.*?))?\s*\)$")


static func strip_blocks(source: String) -> Dictionary:
	var lines: PackedStringArray = source.split("\n")
	var out_lines: PackedStringArray = []
	var blocks: Array[Dictionary] = []
	var i: int = 0
	while i < lines.size():
		var stripped: String = GdssLexer.strip_comment(lines.get(i).strip_edges())
		if import_line.search(stripped) != null:
			out_lines.append("")
			i += 1
			continue
		var scheme_match: RegExMatch = scheme_header.search(stripped)
		var is_meta: bool = meta_header.search(stripped) != null
		var is_resources: bool = resources_header.search(stripped) != null
		var is_config: bool = config_header.search(stripped) != null
		if scheme_match == null and not is_meta and not is_resources and not is_config:
			out_lines.append(lines.get(i))
			i += 1
			continue
		var kind: String = "scheme" if scheme_match != null else ("resources" if is_resources else ("config" if is_config else "meta"))
		var block_name: String = scheme_match.get_string(1) if scheme_match != null else ""
		var block_parent: String = scheme_match.get_string(2) if scheme_match != null else ""
		var header_line: int = i
		var entries: Array[Dictionary] = []
		out_lines.append("")
		if not stripped.contains("{"):
			i += 1
			while i < lines.size():
				var look: String = GdssLexer.strip_comment(lines.get(i).strip_edges())
				if look.is_empty() or look.begins_with("@"):
					break
				out_lines.append("")
				if look == "}":
					i += 1
					break
				i += 1
			blocks.append({"kind": kind, "name": block_name, "parent": block_parent, "header_line": header_line, "entries": [], "malformed": true, "unterminated": false})
			continue
		var depth: int = GdssLexer.brace_delta(stripped)
		var head_entry: Dictionary = extract_block_entry(stripped.substr(stripped.find("{") + 1), header_line)
		if not head_entry.is_empty():
			entries.append(head_entry)
		i += 1
		while i < lines.size() and depth > 0:
			var body: String = GdssLexer.strip_comment(lines.get(i).strip_edges())
			depth += GdssLexer.brace_delta(body)
			var entry: Dictionary = extract_block_entry(body, i)
			if not entry.is_empty():
				entries.append(entry)
			out_lines.append("")
			i += 1
		blocks.append({"kind": kind, "name": block_name, "parent": block_parent, "header_line": header_line, "entries": entries, "malformed": false, "unterminated": depth > 0})
	return {"cleaned": "\n".join(out_lines), "blocks": blocks}


static func extract_block_entry(content: String, line: int) -> Dictionary:
	var clean: String = content.trim_prefix("{").trim_suffix("}").strip_edges()
	var colon: int = clean.find(":")
	if colon <= 0:
		return {}
	return {
		"key": clean.substr(0, colon).strip_edges(),
		"value_str": clean.substr(colon + 1).strip_edges(),
		"line": line,
	}


static func accumulate_blocks(blocks: Array, known_states: PackedStringArray) -> void:
	for block: Dictionary in blocks:
		if block.get("malformed"):
			continue
		if block.get("kind") == "scheme":
			var name: String = block.get("name")
			if not GdssStylesheet.schemes.has(name):
				GdssStylesheet.schemes.set(name, {})
			var parent: String = str(block.get("parent", ""))
			if not parent.is_empty():
				GdssStylesheet.schemes.get(name).set(GdssValue.SCHEME_PARENT_KEY, parent)
			for entry: Dictionary in block.get("entries"):
				var value_str: String = entry.get("value_str")
				if value_str.is_empty():
					continue
				var tokens: Array[String] = GdssLexer.tokenize_value(value_str)
				var consumed: Array = GdssParser.consume_value(tokens, 0, known_states)
				GdssStylesheet.schemes.get(name).set(entry.get("key"), consumed.get(0))
		elif block.get("kind") == "config":
			for entry: Dictionary in block.get("entries"):
				GdssStylesheet.config.set(entry.get("key"), entry.get("value_str"))
		elif block.get("kind") == "resources":
			for entry: Dictionary in block.get("entries"):
				var value: RegExMatch = resource_value.search(str(entry.get("value_str")).strip_edges())
				if value != null:
					GdssStylesheet.resources.set(entry.get("key"), {"method": value.get_string(1), "path": value.get_string(2), "args": value.get_string(3)})
		else:
			for entry: Dictionary in block.get("entries"):
				GdssStylesheet.meta.set(entry.get("key"), parse_meta_value(entry.get("value_str")))


static func parse_meta_value(value_str: String) -> String:
	return value_str.trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'")


static func accumulate_globals(source: String) -> Dictionary:
	var local_vars: Dictionary = {}
	var known_states: PackedStringArray = GdssParser.get_known_states()
	var depth: int = 0
	for line: String in source.split("\n"):
		var stripped: String = GdssLexer.strip_comment(line.strip_edges())
		if stripped.is_empty():
			continue
		var line_depth: int = depth
		depth += stripped.count("{") - stripped.count("}")
		if line_depth > 0 or depth > 0:
			continue
		var gm: RegExMatch = global_var.search(stripped)
		if gm:
			var name: String = gm.get_string(1)
			var raw: String = gm.get_string(2).strip_edges()
			var tokens: Array[String] = GdssLexer.tokenize_value(raw)
			var consumed: Array = GdssParser.consume_value(tokens, 0, known_states)
			var val: Variant = consumed.get(0)
			GdssStylesheet.globals.set(name, val)
			GdssStylesheet._global_defaults.set(name, val)
			continue
		var im: RegExMatch = instance_var.search(stripped)
		if im:
			var name: String = im.get_string(1)
			var raw: String = im.get_string(2).strip_edges()
			var tokens: Array[String] = GdssLexer.tokenize_value(raw)
			var consumed: Array = GdssParser.consume_value(tokens, 0, known_states)
			GdssStylesheet._instance_defaults.set(name, consumed.get(0))
			continue
		var lm: RegExMatch = local_var.search(stripped)
		if lm:
			var raw: String = lm.get_string(2).strip_edges()
			var tokens: Array[String] = GdssLexer.tokenize_value(raw)
			var consumed: Array = GdssParser.consume_value(tokens, 0, known_states)
			local_vars.set(lm.get_string(1), consumed.get(0))
			GdssStylesheet._local_vars.set(lm.get_string(1), consumed.get(0))
	return local_vars


static func collect_imports(source: String) -> Array:
	var result: Array = []
	var lines: PackedStringArray = source.split("\n")
	for i: int in lines.size():
		var stripped: String = GdssLexer.strip_comment(lines.get(i).strip_edges())
		var m: RegExMatch = import_line.search(stripped)
		if m != null:
			result.append({"path": m.get_string(2), "line": i})
	return result


static func resolve_import_path(path: String, base_dir: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://") or path.is_absolute_path():
		return path
	return base_dir.path_join(path)


static func gather_import_sources(source: String, base_dir: String, seen: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = []
	for entry: Dictionary in collect_imports(source):
		var resolved: String = resolve_import_path(entry.get("path"), base_dir).simplify_path()
		if resolved.is_empty() or seen.has(resolved) or not FileAccess.file_exists(resolved):
			continue
		seen.set(resolved, true)
		var imported: String = GdssStorage.read_source(resolved)
		result.append_array(gather_import_sources(imported, resolved.get_base_dir(), seen))
	result.append(source)
	return result


static func replace_meta_block(source: String, new_block: String) -> Dictionary:
	var lines: PackedStringArray = source.split("\n")
	var out: PackedStringArray = []
	var found: bool = false
	var i: int = 0
	while i < lines.size():
		var stripped: String = GdssLexer.strip_comment(lines.get(i).strip_edges())
		if not found and meta_header.search(stripped) != null and stripped.contains("{"):
			out.append_array(new_block.split("\n"))
			found = true
			var depth: int = GdssLexer.brace_delta(stripped)
			i += 1
			while i < lines.size() and depth > 0:
				depth += GdssLexer.brace_delta(GdssLexer.strip_comment(lines.get(i).strip_edges()))
				i += 1
			continue
		out.append(lines.get(i))
		i += 1
	return {"found": found, "source": "\n".join(out)}


static func resource_methods() -> PackedStringArray:
	var result: PackedStringArray = []
	for method: GdssMethod in GDSS._get_gdss_methods().values():
		if method.parameters.is_empty():
			continue
		if method.parameters.get(0).type != GdssMethod.ParamType.STRING:
			continue
		var callable_with_path: bool = true
		for i: int in range(1, method.parameters.size()):
			if not method.parameters.get(i).optional:
				callable_with_path = false
				break
		if callable_with_path:
			result.append(method.method_name)
	result.sort()
	return result
