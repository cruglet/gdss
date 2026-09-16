@tool
class_name GdssSymbols
extends RefCounted

enum Kind { GLOBAL_VAR, INSTANCE_VAR, LOCAL_VAR, SCHEME, CLASS, VARIATION, IMPORT, RESOURCE }

const DOC: String = ""
const VAR_KINDS: Array[int] = [Kind.GLOBAL_VAR, Kind.INSTANCE_VAR, Kind.LOCAL_VAR]
const DOLLAR_KINDS: Array[int] = [Kind.GLOBAL_VAR, Kind.INSTANCE_VAR, Kind.LOCAL_VAR, Kind.RESOURCE]
const RENAMEABLE: Array[int] = [Kind.GLOBAL_VAR, Kind.INSTANCE_VAR, Kind.LOCAL_VAR, Kind.SCHEME, Kind.CLASS, Kind.VARIATION, Kind.RESOURCE]
const KIND_LABELS: Array[String] = ["global var", "instance var", "var", "scheme", "class", "variation", "import", "resource"]
const KIND_ICONS: Array[StringName] = [&"MemberAnnotation", &"NodeInfo", &"LocalVariable", &"BlitMaterial", &"Theme", &"StyleBoxLine", &"Load", &"ResourcePreloader"]

const SCRIPT_TRIGGERS: Dictionary = {
	Kind.GLOBAL_VAR: ["set_global_var", "get_global_var", "reset_global_var", "set_global_vars", "tween_global_vars", "get_scheme_var", "get_var", "set_override_text"],
	Kind.INSTANCE_VAR: ["set_instance_var", "get_instance_var", "clear_instance_var", "get_var", "set_override_text"],
	Kind.SCHEME: ["set_scheme", "has_scheme", "get_scheme_var"],
	Kind.CLASS: ["add_class", "remove_class", "has_class", "toggle_class", "set_classes"],
	Kind.VARIATION: ["theme_type_variation"],
}

static var _re_global: RegEx = RegEx.create_from_string(r"^[\t ]*@global[\t ]+var[\t ]+(\w+)")
static var _re_instance: RegEx = RegEx.create_from_string(r"^[\t ]*@instance[\t ]+var[\t ]+(\w+)")
static var _re_local: RegEx = RegEx.create_from_string(r"^[\t ]*var[\t ]+(\w+)")
static var _re_scheme: RegEx = RegEx.create_from_string(r"^[\t ]*@scheme[\t ]+(\w+)(?:[\t ]+extends[\t ]+(\w+))?")
static var _re_meta: RegEx = RegEx.create_from_string(r"^[\t ]*@meta\b")
static var _re_import: RegEx = RegEx.create_from_string(r"^[\t ]*@import[\t ]+[\"'](.+?)[\"']")
static var _re_resources: RegEx = RegEx.create_from_string(r"^[\t ]*@resources\b")
static var _re_entry: RegEx = RegEx.create_from_string(r"^[\t ]*(\w+)[\t ]*[:=]")
static var _re_dollar: RegEx = RegEx.create_from_string(r"\$(\w+)")
static var _re_event: RegEx = RegEx.create_from_string(r"^\w+[\t ]*\([\t ]*\)$")
static var _re_scene_classes: RegEx = RegEx.create_from_string(r"gdss_classes[\t ]*=[\t ]*PackedStringArray\(")
static var _re_scene_variation: RegEx = RegEx.create_from_string(r"theme_type_variation[\t ]*=[\t ]*&?\"([^\"]*)\"")
static var _re_scene_overrides: RegEx = RegEx.create_from_string(r"gdss_overrides[\t ]*=[\t ]*\"")
static var _re_literal: RegEx = RegEx.create_from_string(r"\"([^\"]*)\"")


class Ref extends RefCounted:
	var kind: GdssSymbols.Kind
	var name: String
	var file: String = ""
	var line: int
	var from: int
	var to: int
	var role: String = "use"
	var text: String
	var declaration: bool = false


	func is_editable() -> bool:
		return role != "script"


	func covers(at_line: int, column: int) -> bool:
		return at_line == line and column >= from and column <= to


class Symbol extends RefCounted:
	var kind: GdssSymbols.Kind
	var name: String
	var refs: Array[Ref] = []


	func label() -> String:
		return "%s %s" % [GdssSymbols.KIND_LABELS.get(kind), name]


	func declarations() -> Array[Ref]:
		var result: Array[Ref] = []
		for entry: Ref in refs:
			if entry.declaration:
				result.append(entry)
		return result


	func declaration() -> Ref:
		for entry: Ref in refs:
			if entry.declaration:
				return entry
		return null


	func in_file(file: String) -> Array[Ref]:
		var result: Array[Ref] = []
		for entry: Ref in refs:
			if entry.file == file:
				result.append(entry)
		return result


	func files() -> PackedStringArray:
		var result: PackedStringArray = []
		for entry: Ref in refs:
			if not result.has(entry.file):
				result.append(entry.file)
		return result


class Index extends RefCounted:
	var symbols: Dictionary = {}
	var by_line: Dictionary = {}


	func register(entry: Ref) -> void:
		var symbol_key: String = GdssSymbols.key(entry.kind, entry.name)
		var symbol: Symbol = symbols.get(symbol_key)
		if symbol == null:
			symbol = Symbol.new()
			symbol.kind = entry.kind
			symbol.name = entry.name
			symbols.set(symbol_key, symbol)
		symbol.refs.append(entry)
		var line_key: String = "%s|%d" % [entry.file, entry.line]
		var bucket: Array[Ref] = by_line.get(line_key, [] as Array[Ref])
		bucket.append(entry)
		by_line.set(line_key, bucket)


	func get_symbol(kind: GdssSymbols.Kind, name: String) -> Symbol:
		return symbols.get(GdssSymbols.key(kind, name))


	func find_at(file: String, line: int, column: int) -> Ref:
		var candidates: Array = by_line.get("%s|%d" % [file, line], [])
		for entry: Ref in candidates:
			if entry.covers(line, column):
				return entry
		return null


	func find_by_name(name: String) -> Symbol:
		for kind: int in GdssSymbols.RENAMEABLE:
			var symbol: Symbol = get_symbol(kind, name)
			if symbol != null:
				return symbol
		return null


	func of_kind(kind: GdssSymbols.Kind) -> Array[Symbol]:
		var result: Array[Symbol] = []
		for symbol: Symbol in symbols.values():
			if symbol.kind == kind:
				result.append(symbol)
		result.sort_custom(func(a: Symbol, b: Symbol) -> bool: return a.name < b.name)
		return result


	func names_of(kind: GdssSymbols.Kind) -> PackedStringArray:
		var result: PackedStringArray = []
		for symbol: Symbol in of_kind(kind):
			result.append(symbol.name)
		return result


	func declared_var(name: String) -> Symbol:
		for kind: int in GdssSymbols.DOLLAR_KINDS:
			var symbol: Symbol = get_symbol(kind, name)
			if symbol != null and symbol.declaration() != null:
				return symbol
		return null


class _Scanner extends RefCounted:
	var index: Index
	var file: String
	var line: int
	var text: String


	func emit(kind: GdssSymbols.Kind, name: String, from: int, to: int, role: String, declaration: bool) -> void:
		var entry: Ref = Ref.new()
		entry.kind = kind
		entry.name = name
		entry.file = file
		entry.line = line
		entry.from = from
		entry.to = to
		entry.role = role
		entry.text = text
		entry.declaration = declaration
		index.register(entry)


static func key(kind: Kind, name: String) -> String:
	return "%d:%s" % [kind, name]


static func sort_refs(refs: Array[Ref], descending: bool = false) -> Array[Ref]:
	refs.sort_custom(func(a: Ref, b: Ref) -> bool:
		if a.file != b.file:
			return a.file > b.file if descending else a.file < b.file
		if a.line != b.line:
			return a.line > b.line if descending else a.line < b.line
		return a.from > b.from if descending else a.from < b.from
	)
	return refs


static func build(sources: Dictionary) -> Index:
	var index: Index = Index.new()
	for file: String in sources:
		_scan(index, file, sources.get(file), true)
	for file: String in sources:
		_scan(index, file, sources.get(file), false)
	return index


static func _scan(index: Index, file: String, source: String, declaring: bool) -> void:
	var scanner: _Scanner = _Scanner.new()
	scanner.index = index
	scanner.file = file
	var frames: Array[String] = []
	var lines: PackedStringArray = source.split("\n")
	for line_number: int in lines.size():
		var raw: String = strip_comment(lines.get(line_number))
		scanner.line = line_number
		scanner.text = lines.get(line_number)
		var frame: String = frames.back() if not frames.is_empty() else ""
		var scheme_match: RegExMatch = _re_scheme.search(raw)
		var is_meta: bool = _re_meta.search(raw) != null
		var is_resources: bool = _re_resources.search(raw) != null
		if declaring:
			_scan_declarations(scanner, raw, frame, frames.size(), scheme_match, is_meta or is_resources)
		else:
			_scan_references(scanner, raw, frame, scheme_match, is_meta or is_resources)
		var opened: int = _brace_delta(raw)
		if opened > 0:
			var kind: String = "scheme" if scheme_match != null else ("resources" if is_resources else ("meta" if is_meta else "selector"))
			for i: int in opened:
				frames.push_back(kind)
		elif opened < 0:
			for i: int in -opened:
				if not frames.is_empty():
					frames.pop_back()


static func _scan_declarations(scanner: _Scanner, raw: String, frame: String, depth: int, scheme_match: RegExMatch, is_meta: bool) -> void:
	if frame == "resources":
		var resource_entry: RegExMatch = _re_entry.search(raw)
		if resource_entry != null:
			scanner.emit(Kind.RESOURCE, resource_entry.get_string(1), resource_entry.get_start(1), resource_entry.get_end(1), "decl", true)
		return
	if frame == "scheme" or frame == "meta" or is_meta:
		return
	if scheme_match != null:
		scanner.emit(Kind.SCHEME, scheme_match.get_string(1), scheme_match.get_start(1), scheme_match.get_end(1), "decl", true)
		return
	var global_match: RegExMatch = _re_global.search(raw)
	if global_match != null:
		scanner.emit(Kind.GLOBAL_VAR, global_match.get_string(1), global_match.get_start(1), global_match.get_end(1), "decl", true)
		return
	var instance_match: RegExMatch = _re_instance.search(raw)
	if instance_match != null:
		scanner.emit(Kind.INSTANCE_VAR, instance_match.get_string(1), instance_match.get_start(1), instance_match.get_end(1), "decl", true)
		return
	var local_match: RegExMatch = _re_local.search(raw)
	if local_match != null:
		scanner.emit(Kind.LOCAL_VAR, local_match.get_string(1), local_match.get_start(1), local_match.get_end(1), "decl", true)
		return
	if depth < 1 or _re_import.search(raw) != null:
		return
	var brace: int = raw.find("{")
	if brace == -1:
		return
	for piece: Vector2i in _selector_pieces(raw.substr(0, brace)):
		_emit_selector(scanner, raw, piece)


static func _emit_selector(scanner: _Scanner, raw: String, piece: Vector2i) -> void:
	var from: int = piece.x
	var to: int = piece.y
	var text: String = raw.substr(from, to - from)
	if text.begins_with(":") or _re_event.search(text) != null:
		return
	var colon: int = text.find(":")
	if colon != -1:
		to = from + colon
		text = text.substr(0, colon)
	var kind: Kind = Kind.CLASS
	if text.begins_with("%"):
		kind = Kind.VARIATION
		from += 1
		text = text.substr(1)
	if not text.is_valid_identifier():
		return
	scanner.emit(kind, text, from, to, "decl", true)


static func _scan_references(scanner: _Scanner, raw: String, frame: String, scheme_match: RegExMatch, is_meta: bool) -> void:
	var import_match: RegExMatch = _re_import.search(raw)
	if import_match != null:
		scanner.emit(Kind.IMPORT, import_match.get_string(1), import_match.get_start(1), import_match.get_end(1), "import", false)
		return
	if scheme_match != null:
		if not scheme_match.get_string(2).is_empty():
			scanner.emit(Kind.SCHEME, scheme_match.get_string(2), scheme_match.get_start(2), scheme_match.get_end(2), "extends", false)
		_scan_block_head(scanner, raw, "scheme")
		return
	if is_meta:
		_scan_block_head(scanner, raw, "meta")
		return
	if frame == "scheme" or frame == "meta":
		_scan_entry(scanner, raw, frame, 0)
	for dollar: RegExMatch in _re_dollar.search_all(raw):
		var symbol: Symbol = scanner.index.declared_var(dollar.get_string(1))
		if symbol != null:
			scanner.emit(symbol.kind, symbol.name, dollar.get_start(1), dollar.get_end(1), "var", false)


static func _scan_block_head(scanner: _Scanner, raw: String, frame: String) -> void:
	var brace: int = raw.find("{")
	if brace == -1 or raw.substr(brace + 1).strip_edges().is_empty():
		return
	_scan_entry(scanner, raw.substr(brace + 1), frame, brace + 1)


static func _scan_entry(scanner: _Scanner, segment: String, frame: String, offset: int) -> void:
	var entry_match: RegExMatch = _re_entry.search(segment)
	if entry_match == null:
		return
	var name: String = entry_match.get_string(1)
	var from: int = offset + entry_match.get_start(1)
	var to: int = offset + entry_match.get_end(1)
	if frame == "meta":
		if name != "default_scheme":
			return
		var value: String = segment.substr(entry_match.get_end(0)).strip_edges().trim_suffix("}").strip_edges()
		if not value.is_valid_identifier():
			return
		var value_from: int = offset + segment.find(value, entry_match.get_end(0))
		scanner.emit(Kind.SCHEME, value, value_from, value_from + value.length(), "meta", false)
		return
	var symbol: Symbol = scanner.index.declared_var(name)
	if symbol != null:
		scanner.emit(symbol.kind, symbol.name, from, to, "scheme_key", false)


static func _selector_pieces(head: String) -> Array[Vector2i]:
	var pieces: Array[Vector2i] = []
	var cursor: int = 0
	for part: String in head.split(","):
		var from: int = cursor + part.length() - part.lstrip(" \t").length()
		var to: int = cursor + part.rstrip(" \t").length()
		if to > from:
			pieces.append(Vector2i(from, to))
		cursor += part.length() + 1
	return pieces


static func strip_comment(line: String) -> String:
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


static func _brace_delta(line: String) -> int:
	var depth: int = 0
	var in_quote: bool = false
	var quote_char: String = ""
	for c: String in line:
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


static func apply(source: String, refs: Array[Ref], new_name: String) -> String:
	var ordered: Array[Ref] = sort_refs(refs.duplicate(), true)
	var lines: PackedStringArray = source.split("\n")
	for entry: Ref in ordered:
		if entry.line < 0 or entry.line >= lines.size():
			continue
		var line: String = lines.get(entry.line)
		if entry.to > line.length() or line.substr(entry.from, entry.to - entry.from) != entry.name:
			continue
		lines.set(entry.line, line.substr(0, entry.from) + new_name + line.substr(entry.to))
	return "\n".join(lines)


static func text_has_var(text: String, name: String) -> bool:
	return RegEx.create_from_string("\\$(" + name + ")\\b").search(text) != null


static func rename_in_text(text: String, name: String, new_name: String) -> String:
	var pattern: RegEx = RegEx.create_from_string("\\$(" + name + ")\\b")
	var matches: Array[RegExMatch] = pattern.search_all(text)
	var result: String = text
	for i: int in range(matches.size() - 1, -1, -1):
		var found: RegExMatch = matches.get(i)
		result = result.substr(0, found.get_start(1)) + new_name + result.substr(found.get_end(1))
	return result


static func validate(index: Index, symbol: Symbol, new_name: String) -> String:
	if new_name.is_empty():
		return "Enter a name."
	if not new_name.is_valid_identifier():
		return "'%s' is not a valid identifier." % new_name
	if new_name == symbol.name:
		return "That is the current name."
	if DOLLAR_KINDS.has(symbol.kind):
		for kind: int in DOLLAR_KINDS:
			var clash: Symbol = index.get_symbol(kind, new_name)
			if clash != null and clash.declaration() != null:
				return "A %s named '%s' already exists." % [KIND_LABELS.get(kind), new_name]
		return ""
	var existing: Symbol = index.get_symbol(symbol.kind, new_name)
	if existing != null:
		return "A %s named '%s' already exists." % [KIND_LABELS.get(symbol.kind), new_name]
	if symbol.kind == Kind.CLASS or symbol.kind == Kind.VARIATION:
		if GDSS._get_node_types().has(new_name):
			return "'%s' is already a styled node type." % new_name
	return ""


static func scan_scenes(symbol: Symbol) -> Array[Ref]:
	var result: Array[Ref] = []
	if symbol.kind == Kind.IMPORT:
		return result
	var dollar: RegEx = _name_regex(symbol) if DOLLAR_KINDS.has(symbol.kind) else null
	for path: String in collect_files(PackedStringArray(["tscn"])):
		var source: String = FileAccess.get_file_as_string(path)
		if not source.contains(symbol.name):
			continue
		var lines: PackedStringArray = source.split("\n")
		var regions: Dictionary = _override_regions(lines) if dollar != null else {}
		for line_number: int in lines.size():
			var line: String = lines.get(line_number)
			var hits: Array[Vector2i] = []
			if dollar != null:
				if regions.has(line_number):
					hits = _group_ranges(dollar.search_all(line))
			else:
				hits = _scene_hits(line, symbol)
			for located: Vector2i in hits:
				result.append(_make_ref(symbol, path, line_number, located, "scene", line))
	return result


static func _scene_hits(line: String, symbol: Symbol) -> Array[Vector2i]:
	var hits: Array[Vector2i] = []
	if symbol.kind == Kind.VARIATION:
		var variation: RegExMatch = _re_scene_variation.search(line)
		if variation != null and variation.get_string(1) == symbol.name:
			hits.append(Vector2i(variation.get_start(1), variation.get_end(1)))
		return hits
	if _re_scene_classes.search(line) == null:
		return hits
	for literal: RegExMatch in _re_literal.search_all(line):
		if literal.get_string(1) == symbol.name:
			hits.append(Vector2i(literal.get_start(1), literal.get_end(1)))
	return hits


static func scan_scripts(symbol: Symbol) -> Array[Ref]:
	var result: Array[Ref] = []
	var triggers: Array = SCRIPT_TRIGGERS.get(symbol.kind, [])
	if triggers.is_empty():
		return result
	var dollar: RegEx = _name_regex(symbol) if DOLLAR_KINDS.has(symbol.kind) else null
	for path: String in collect_files(PackedStringArray(["gd"])):
		var source: String = FileAccess.get_file_as_string(path)
		if not source.contains(symbol.name):
			continue
		var lines: PackedStringArray = source.split("\n")
		for line_number: int in lines.size():
			var line: String = lines.get(line_number)
			var triggered: bool = false
			for trigger: String in triggers:
				if line.contains(trigger):
					triggered = true
					break
			if not triggered:
				continue
			var hits: Array[Vector2i] = []
			for literal: RegExMatch in _re_literal.search_all(line):
				if literal.get_string(1) == symbol.name:
					hits.append(Vector2i(literal.get_start(1), literal.get_end(1)))
			if dollar != null:
				hits.append_array(_group_ranges(dollar.search_all(line)))
			for located: Vector2i in hits:
				result.append(_make_ref(symbol, path, line_number, located, "script", line))
	return result


static func _name_regex(symbol: Symbol) -> RegEx:
	return RegEx.create_from_string("\\$(" + symbol.name + ")\\b")


static func _group_ranges(matches: Array[RegExMatch]) -> Array[Vector2i]:
	var ranges: Array[Vector2i] = []
	for found: RegExMatch in matches:
		ranges.append(Vector2i(found.get_start(1), found.get_end(1)))
	return ranges


static func _make_ref(symbol: Symbol, file: String, line: int, span: Vector2i, role: String, text: String) -> Ref:
	var entry: Ref = Ref.new()
	entry.kind = symbol.kind
	entry.name = symbol.name
	entry.file = file
	entry.line = line
	entry.from = span.x
	entry.to = span.y
	entry.role = role
	entry.text = text
	return entry


static func _override_regions(lines: PackedStringArray) -> Dictionary:
	var regions: Dictionary = {}
	var inside: bool = false
	for line_number: int in lines.size():
		var line: String = lines.get(line_number)
		if not inside and _re_scene_overrides.search(line) == null:
			continue
		regions.set(line_number, true)
		if line.count("\"") % 2 == 1:
			inside = not inside
	return regions


static func collect_files(extensions: PackedStringArray, root: String = "res://") -> PackedStringArray:
	var result: PackedStringArray = []
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return result
	if dir.file_exists(".gdignore"):
		return result
	for file: String in dir.get_files():
		if extensions.has(file.get_extension().to_lower()):
			result.append(root.path_join(file))
	for sub: String in dir.get_directories():
		if sub.begins_with("."):
			continue
		result.append_array(collect_files(extensions, root.path_join(sub)))
	return result


static func scene_usage() -> Dictionary:
	var classes: Dictionary = {}
	var variables: Dictionary = {}
	for path: String in collect_files(PackedStringArray(["tscn"])):
		var source: String = FileAccess.get_file_as_string(path)
		if not source.contains("gdss_"):
			continue
		var lines: PackedStringArray = source.split("\n")
		var regions: Dictionary = _override_regions(lines)
		for line_number: int in lines.size():
			var line: String = lines.get(line_number)
			if regions.has(line_number):
				for dollar: RegExMatch in _re_dollar.search_all(line):
					variables.set(dollar.get_string(1), true)
			if _re_scene_classes.search(line) == null:
				continue
			for literal: RegExMatch in _re_literal.search_all(line):
				var name: String = literal.get_string(1)
				if name.is_empty():
					continue
				var sites: Array[Dictionary] = classes.get(name, [] as Array[Dictionary])
				sites.append({"file": path, "line": line_number})
				classes.set(name, sites)
	return {"classes": classes, "variables": variables}


static func script_literal_usage() -> Dictionary:
	var usage: Dictionary = {}
	for path: String in collect_files(PackedStringArray(["gd"])):
		var source: String = FileAccess.get_file_as_string(path)
		if not source.contains("GDSS.") and not source.contains("theme_type_variation"):
			continue
		var lines: PackedStringArray = source.split("\n")
		for line_number: int in lines.size():
			var line: String = lines.get(line_number)
			if not line.contains("GDSS.") and not line.contains("theme_type_variation"):
				continue
			for literal: RegExMatch in _re_literal.search_all(line):
				var name: String = literal.get_string(1)
				if not name.is_empty():
					usage.set(name, true)
	return usage


static func diagnostics(index: Index) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var usage: Dictionary = scene_usage()
	var scene_classes: Dictionary = usage.get("classes")
	var scene_variables: Dictionary = usage.get("variables")
	var script_usage: Dictionary = script_literal_usage()
	var class_names: PackedStringArray = index.names_of(Kind.CLASS)
	for name: String in scene_classes:
		if class_names.has(name):
			continue
		for site: Dictionary in scene_classes.get(name):
			result.append(_diagnostic("Node uses GDSS class '%s', which no block declares." % name, site.get("file"), site.get("line"), name))
	for symbol: Symbol in index.symbols.values():
		var label: String = KIND_LABELS.get(symbol.kind)
		var decls: Array[Ref] = symbol.declarations()
		if decls.is_empty():
			if symbol.kind == Kind.SCHEME:
				for entry: Ref in symbol.refs:
					result.append(_diagnostic("Scheme '%s' is referenced but never declared." % symbol.name, entry.file, entry.line, symbol.name))
			continue
		var first: Ref = decls.get(0)
		var nestable: bool = symbol.kind == Kind.CLASS or symbol.kind == Kind.VARIATION
		if decls.size() > 1 and not nestable:
			for entry: Ref in decls.slice(1):
				result.append(_diagnostic("Duplicate declaration of %s '%s'." % [label, symbol.name], entry.file, entry.line, symbol.name))
		if symbol.kind == Kind.LOCAL_VAR:
			for kind: int in [Kind.GLOBAL_VAR, Kind.INSTANCE_VAR]:
				var shadowed: Symbol = index.get_symbol(kind, symbol.name)
				if shadowed != null and shadowed.declaration() != null:
					result.append(_diagnostic("'%s' shadows the %s of the same name." % [symbol.name, KIND_LABELS.get(kind)], first.file, first.line, symbol.name))
		if decls.size() == symbol.refs.size() and symbol.kind != Kind.VARIATION:
			var used: bool = scene_classes.has(symbol.name) or scene_variables.has(symbol.name) or script_usage.has(symbol.name)
			if not used:
				result.append(_diagnostic("Unused %s '%s'." % [label, symbol.name], first.file, first.line, symbol.name))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.get("file") != b.get("file"):
			return a.get("file") < b.get("file")
		return int(a.get("line")) < int(b.get("line"))
	)
	return result


static func _diagnostic(message: String, file: String, line: int, name: String) -> Dictionary:
	return {"message": message, "file": file, "line": line, "name": name}
