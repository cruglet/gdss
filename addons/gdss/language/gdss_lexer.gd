@tool
class_name GdssLexer
extends RefCounted


static func strip_comment(s: String) -> String:
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


static func split_statements(line: String) -> PackedStringArray:
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


static func split_args(args_raw: String) -> Array[String]:
	var result: Array[String] = []
	if args_raw.is_empty():
		return result
	var current: String = ""
	var depth: int = 0
	var in_quote: bool = false
	var quote_char: String = ""
	for c: String in args_raw:
		if in_quote:
			current += c
			if c == quote_char:
				in_quote = false
		elif c == "\"" or c == "'":
			in_quote = true
			quote_char = c
			current += c
		elif c == "(":
			depth += 1
			current += c
		elif c == ")":
			depth -= 1
			current += c
		elif c == "," and depth == 0:
			result.append(current.strip_edges())
			current = ""
		else:
			current += c
	result.append(current.strip_edges())
	return result


static func brace_delta(s: String) -> int:
	var depth: int = 0
	var in_quote: bool = false
	var quote_char: String = ""
	for c: String in s:
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


static func normalize_separators(source: String) -> String:
	var out: PackedStringArray = []
	for line: String in source.split("\n"):
		out.append(_replace_eq_separators(line))
	return "\n".join(out)


static func _replace_eq_separators(line: String) -> String:
	var result: String = ""
	var in_quote: bool = false
	var quote_char: String = ""
	var depth: int = 0
	for i: int in line.length():
		var c: String = line[i]
		if in_quote:
			if c == quote_char:
				in_quote = false
			result += c
		elif c == "\"" or c == "'":
			in_quote = true
			quote_char = c
			result += c
		elif c == "#":
			result += line.substr(i)
			return result
		elif c == "(":
			depth += 1
			result += c
		elif c == ")":
			depth -= 1
			result += c
		elif c == "=" and depth == 0:
			result += ":"
		else:
			result += c
	return result


static func tokenize(source: String) -> Array[String]:
	var tokens: Array[String] = []
	for line: String in source.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("@global") or stripped.begins_with("@instance"):
			continue
		stripped = strip_comment(stripped)
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
			elif ch == ":" and current.strip_edges().is_empty() and not tokens.is_empty() and tokens.back() == ":":
				tokens.set(tokens.size() - 1, "::")
			elif ch in ["{", "}", ":", ",", "(", ")"]:
				if not current.strip_edges().is_empty():
					tokens.append(current.strip_edges())
					current = ""
				tokens.append(ch)
			elif ch == ">":
				if not current.strip_edges().is_empty():
					tokens.append(current.strip_edges())
					current = ""
				if not tokens.is_empty() and tokens.get(tokens.size() - 1) == ">":
					tokens.set(tokens.size() - 1, ">>")
				else:
					tokens.append(">")
			elif ch == " " or ch == "\t" or ch == ";":
				if not current.strip_edges().is_empty():
					tokens.append(current.strip_edges())
					current = ""
			else:
				current += ch
		if not current.strip_edges().is_empty():
			tokens.append(current.strip_edges())
	return tokens


static func tokenize_value(raw: String) -> Array[String]:
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
