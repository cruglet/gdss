@tool
class_name GdssLexer
extends RefCounted

const _TAB: int = 9
const _SPACE: int = 32
const _QUOTE: int = 34
const _HASH: int = 35
const _APOSTROPHE: int = 39
const _OPEN_PAREN: int = 40
const _CLOSE_PAREN: int = 41
const _COMMA: int = 44
const _COLON: int = 58
const _SEMICOLON: int = 59
const _EQUALS: int = 61
const _GREATER: int = 62
const _OPEN_BRACE: int = 123
const _CLOSE_BRACE: int = 125


static func strip_comment(s: String) -> String:
	var hash: int = comment_start(s)
	return s if hash == -1 else s.substr(0, hash).strip_edges()


static func cut_comment(s: String) -> String:
	var hash: int = comment_start(s)
	return s if hash == -1 else s.substr(0, hash)


static func comment_start(s: String) -> int:
	return find_unquoted(s, "#")


static func find_unquoted(text: String, targets: String) -> int:
	var codes: PackedInt32Array = []
	for i: int in targets.length():
		if text.contains(targets.substr(i, 1)):
			codes.append(targets.unicode_at(i))
	if codes.is_empty():
		return -1
	var n: int = text.length()
	var i: int = 0
	while i < n:
		var c: int = text.unicode_at(i)
		if c == _QUOTE or c == _APOSTROPHE:
			i = _quote_end(text, i)
		elif codes.has(c):
			return i
		i += 1
	return -1


static func split_statements(line: String) -> PackedStringArray:
	if not line.contains(";"):
		return PackedStringArray([line])
	var result: PackedStringArray = []
	var start: int = 0
	var n: int = line.length()
	var i: int = 0
	while i < n:
		var c: int = line.unicode_at(i)
		if c == _QUOTE or c == _APOSTROPHE:
			i = _quote_end(line, i)
		elif c == _SEMICOLON:
			result.append(line.substr(start, i - start))
			start = i + 1
		i += 1
	result.append(line.substr(start))
	return result


static func split_args(args_raw: String) -> Array[String]:
	var result: Array[String] = []
	if args_raw.is_empty():
		return result
	var start: int = 0
	var depth: int = 0
	var n: int = args_raw.length()
	var i: int = 0
	while i < n:
		var c: int = args_raw.unicode_at(i)
		if c == _QUOTE or c == _APOSTROPHE:
			i = _quote_end(args_raw, i)
		elif c == _OPEN_PAREN:
			depth += 1
		elif c == _CLOSE_PAREN:
			depth -= 1
		elif c == _COMMA and depth == 0:
			result.append(args_raw.substr(start, i - start).strip_edges())
			start = i + 1
		i += 1
	result.append(args_raw.substr(start).strip_edges())
	return result


static func brace_delta(s: String) -> int:
	if not s.contains("{") and not s.contains("}"):
		return 0
	var depth: int = 0
	var n: int = s.length()
	var i: int = 0
	while i < n:
		var c: int = s.unicode_at(i)
		if c == _QUOTE or c == _APOSTROPHE:
			i = _quote_end(s, i)
		elif c == _OPEN_BRACE:
			depth += 1
		elif c == _CLOSE_BRACE:
			depth -= 1
		i += 1
	return depth


static func normalize_separators(source: String) -> String:
	if not source.contains("="):
		return source
	var out: PackedStringArray = []
	for line: String in source.split("\n"):
		out.append(_replace_eq_separators(line) if line.contains("=") else line)
	return "\n".join(out)


static func _replace_eq_separators(line: String) -> String:
	var pieces: PackedStringArray = []
	var start: int = 0
	var depth: int = 0
	var n: int = line.length()
	var i: int = 0
	while i < n:
		var c: int = line.unicode_at(i)
		if c == _QUOTE or c == _APOSTROPHE:
			i = _quote_end(line, i)
		elif c == _HASH:
			break
		elif c == _OPEN_PAREN:
			depth += 1
		elif c == _CLOSE_PAREN:
			depth -= 1
		elif c == _EQUALS and depth == 0:
			pieces.append(line.substr(start, i - start))
			start = i + 1
		i += 1
	if pieces.is_empty():
		return line
	pieces.append(line.substr(start))
	return ":".join(pieces)


static func tokenize(source: String) -> Array[String]:
	var tokens: Array[String] = []
	for line: String in source.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("@global") or stripped.begins_with("@instance"):
			continue
		stripped = strip_comment(stripped)
		if not stripped.is_empty():
			_scan_tokens(stripped, tokens, true)
	return tokens


static func tokenize_value(raw: String) -> Array[String]:
	var tokens: Array[String] = []
	_scan_tokens(raw, tokens, false)
	return tokens


static func _scan_tokens(text: String, tokens: Array[String], selectors: bool) -> void:
	var n: int = text.length()
	var start: int = -1
	var i: int = 0
	while i < n:
		var c: int = text.unicode_at(i)
		if c == _QUOTE or c == _APOSTROPHE:
			if start == -1:
				start = i
			i = _quote_end(text, i)
		elif c == _HASH and not selectors:
			break
		elif selectors and c == _COLON and _pending_is_blank(text, start, i) and not tokens.is_empty() and tokens.back() == ":":
			tokens.set(tokens.size() - 1, "::")
			start = -1
		elif c == _OPEN_BRACE or c == _CLOSE_BRACE or c == _COLON or c == _COMMA or c == _OPEN_PAREN or c == _CLOSE_PAREN:
			start = _flush(text, start, i, tokens)
			tokens.append(String.chr(c))
		elif selectors and c == _GREATER:
			start = _flush(text, start, i, tokens)
			if not tokens.is_empty() and tokens.back() == ">":
				tokens.set(tokens.size() - 1, ">>")
			else:
				tokens.append(">")
		elif c == _SPACE or c == _TAB or c == _SEMICOLON:
			start = _flush(text, start, i, tokens)
		elif start == -1:
			start = i
		i += 1
	_flush(text, start, i, tokens)


static func _flush(text: String, start: int, end: int, tokens: Array[String]) -> int:
	if start != -1:
		var token: String = text.substr(start, end - start).strip_edges()
		if not token.is_empty():
			tokens.append(token)
	return -1


static func _pending_is_blank(text: String, start: int, end: int) -> bool:
	return start == -1 or text.substr(start, end - start).strip_edges().is_empty()


static func _quote_end(text: String, i: int) -> int:
	var close: int = text.find(String.chr(text.unicode_at(i)), i + 1)
	return text.length() - 1 if close == -1 else close
