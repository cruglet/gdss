@tool
class_name GdssCalc
extends RefCounted


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
	var inner: Array[String] = tokens.slice(pos + 2, close)
	var lexed: Array[String] = lex(" ".join(inner))
	var state: Dictionary = {"toks": lexed, "i": 0}
	var ast: Variant = _expr(state)
	return [{"__gdss_calc__": ast}, close + 1]


static func lex(raw: String) -> Array[String]:
	var out: Array[String] = []
	var i: int = 0
	var n: int = raw.length()
	while i < n:
		var ch: String = raw[i]
		if ch == " " or ch == "\t":
			i += 1
			continue
		if ch == "+" or ch == "-" or ch == "*" or ch == "/" or ch == "(" or ch == ")":
			out.append(ch)
			i += 1
			continue
		var start: int = i
		while i < n:
			var c: String = raw[i]
			if c == " " or c == "\t" or c == "+" or c == "-" or c == "*" or c == "/" or c == "(" or c == ")":
				break
			i += 1
		out.append(raw.substr(start, i - start))
	return out


static func _peek(state: Dictionary) -> String:
	return state.get("toks").get(state.get("i")) if state.get("i") < (state.get("toks") as Array).size() else ""


static func _advance(state: Dictionary) -> String:
	var t: String = _peek(state)
	state.set("i", state.get("i") + 1)
	return t


static func _expr(state: Dictionary) -> Variant:
	var node: Variant = _term(state)
	while _peek(state) == "+" or _peek(state) == "-":
		var op: String = _advance(state)
		node = {"calc_op": op, "l": node, "r": _term(state)}
	return node


static func _term(state: Dictionary) -> Variant:
	var node: Variant = _factor(state)
	while _peek(state) == "*" or _peek(state) == "/":
		var op: String = _advance(state)
		node = {"calc_op": op, "l": node, "r": _factor(state)}
	return node


static func _factor(state: Dictionary) -> Variant:
	var t: String = _peek(state)
	if t == "-":
		_advance(state)
		return {"calc_neg": _factor(state)}
	if t == "(":
		_advance(state)
		var node: Variant = _expr(state)
		if _peek(state) == ")":
			_advance(state)
		return node
	_advance(state)
	if t.is_valid_float() or t.is_valid_int():
		return {"calc_num": float(t)}
	return {"calc_ref": t}


static func evaluate(node: Variant, resolve_ref: Callable) -> float:
	if not node is Dictionary:
		return 0.0
	var d: Dictionary = node as Dictionary
	if d.has("calc_num"):
		return float(d.get("calc_num"))
	if d.has("calc_ref"):
		return resolve_ref.call(d.get("calc_ref"))
	if d.has("calc_neg"):
		return -evaluate(d.get("calc_neg"), resolve_ref)
	if d.has("calc_op"):
		var l: float = evaluate(d.get("l"), resolve_ref)
		var r: float = evaluate(d.get("r"), resolve_ref)
		match d.get("calc_op"):
			"+": return l + r
			"-": return l - r
			"*": return l * r
			"/": return l / r if r != 0.0 else 0.0
	return 0.0


static func has_dynamic_ref(node: Variant) -> bool:
	if not node is Dictionary:
		return false
	var d: Dictionary = node as Dictionary
	if d.has("calc_ref"):
		var r: String = d.get("calc_ref")
		return r.begins_with("__gdss_global__") or r.begins_with("__gdss_instance__") or r.begins_with("$")
	if d.has("calc_neg"):
		return has_dynamic_ref(d.get("calc_neg"))
	if d.has("calc_op"):
		return has_dynamic_ref(d.get("l")) or has_dynamic_ref(d.get("r"))
	return false
