@tool
class_name GdssCalc
extends RefCounted

const OP_KEY: String = "calc_op"
const LEFT_KEY: String = "l"
const RIGHT_KEY: String = "r"
const NEGATE_KEY: String = "calc_neg"
const NUMBER_KEY: String = "calc_num"
const REF_KEY: String = "calc_ref"
const _OPERATORS: String = "+-*/()"


class Cursor extends RefCounted:
	var tokens: Array[String]
	var index: int = 0
	
	func _init(p_tokens: Array[String]) -> void:
		tokens = p_tokens
	
	func peek() -> String:
		return tokens.get(index) if index < tokens.size() else ""
	
	func advance() -> String:
		var token: String = peek()
		index += 1
		return token


static func parse(tokens: Array[String], pos: int) -> Array:
	var depth: int = 0
	var close: int = pos + 1
	while close < tokens.size():
		if tokens.get(close) == "(":
			depth += 1
		elif tokens.get(close) == ")":
			depth -= 1
			if depth == 0:
				break
		close += 1
	var cursor: Cursor = Cursor.new(lex(" ".join(tokens.slice(pos + 2, close))))
	return [{GdssValue.CALC_KEY: _expr(cursor)}, close + 1]


static func lex(raw: String) -> Array[String]:
	var out: Array[String] = []
	var n: int = raw.length()
	var start: int = -1
	for i: int in n:
		var c: String = raw.substr(i, 1)
		var separator: bool = c == " " or c == "\t"
		var operator: bool = _OPERATORS.contains(c)
		if not separator and not operator:
			if start == -1:
				start = i
			continue
		if start != -1:
			out.append(raw.substr(start, i - start))
			start = -1
		if operator:
			out.append(c)
	if start != -1:
		out.append(raw.substr(start))
	return out


static func _expr(cursor: Cursor) -> Variant:
	var node: Variant = _term(cursor)
	while cursor.peek() == "+" or cursor.peek() == "-":
		var op: String = cursor.advance()
		node = {OP_KEY: op, LEFT_KEY: node, RIGHT_KEY: _term(cursor)}
	return node


static func _term(cursor: Cursor) -> Variant:
	var node: Variant = _factor(cursor)
	while cursor.peek() == "*" or cursor.peek() == "/":
		var op: String = cursor.advance()
		node = {OP_KEY: op, LEFT_KEY: node, RIGHT_KEY: _factor(cursor)}
	return node


static func _factor(cursor: Cursor) -> Variant:
	var token: String = cursor.advance()
	if token == "-":
		return {NEGATE_KEY: _factor(cursor)}
	if token == "(":
		var node: Variant = _expr(cursor)
		if cursor.peek() == ")":
			cursor.advance()
		return node
	if token.is_valid_float() or token.is_valid_int():
		return {NUMBER_KEY: float(token)}
	return {REF_KEY: token}


static func evaluate(node: Variant, resolve_ref: Callable) -> float:
	if not node is Dictionary:
		return 0.0
	var d: Dictionary = node as Dictionary
	if d.has(NUMBER_KEY):
		return float(d.get(NUMBER_KEY))
	if d.has(REF_KEY):
		return resolve_ref.call(d.get(REF_KEY))
	if d.has(NEGATE_KEY):
		return -evaluate(d.get(NEGATE_KEY), resolve_ref)
	if d.has(OP_KEY):
		var l: float = evaluate(d.get(LEFT_KEY), resolve_ref)
		var r: float = evaluate(d.get(RIGHT_KEY), resolve_ref)
		match d.get(OP_KEY):
			"+": return l + r
			"-": return l - r
			"*": return l * r
			"/": return l / r if r != 0.0 else 0.0
	return 0.0


static func has_dynamic_ref(node: Variant) -> bool:
	if not node is Dictionary:
		return false
	var d: Dictionary = node as Dictionary
	if d.has(REF_KEY):
		var r: String = d.get(REF_KEY)
		return r.begins_with(GdssValue.GLOBAL_REF) or r.begins_with(GdssValue.INSTANCE_REF) or r.begins_with("$")
	if d.has(NEGATE_KEY):
		return has_dynamic_ref(d.get(NEGATE_KEY))
	if d.has(OP_KEY):
		return has_dynamic_ref(d.get(LEFT_KEY)) or has_dynamic_ref(d.get(RIGHT_KEY))
	return false
