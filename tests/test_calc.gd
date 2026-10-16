extends RefCounted


const TC: GDScript = preload("res://tests/gdss_test_context.gd")


func _eval(expression: String, refs: Dictionary = {}) -> float:
	var tokens: Array[String] = GdssLexer.tokenize_value("calc(%s)" % expression)
	var ast: Variant = (GdssCalc.parse(tokens, 0).front() as Dictionary).get(GdssValue.CALC_KEY)
	return GdssCalc.evaluate(ast, func(ref: String) -> float: return float(refs.get(ref, 0.0)))


func run(t: TC) -> void:
	t.check_eq(_eval("2 + 3 * 4"), 14.0, "multiplication binds tighter than addition")
	t.check_eq(_eval("(2 + 3) * 4"), 20.0, "parentheses group first")
	t.check_eq(_eval("10 - 4 - 3"), 3.0, "subtraction associates left")
	t.check_eq(_eval("-2 * 3"), -6.0, "unary minus negates")
	t.check_eq(_eval("8 / 0"), 0.0, "division by zero yields zero")
	t.check_eq(_eval("$unit * 2 + 1", {"$unit": 4.0}), 9.0, "references resolve through the callback")
	t.check_eq(GdssCalc.lex("1+$a*(2-3)"), ["1", "+", "$a", "*", "(", "2", "-", "3", ")"] as Array[String], "operators split tokens without spaces")
	var dynamic: Variant = (GdssCalc.parse(GdssLexer.tokenize_value("calc($unit * 2)"), 0).front() as Dictionary).get(GdssValue.CALC_KEY)
	var constant: Variant = (GdssCalc.parse(GdssLexer.tokenize_value("calc(3 * 2)"), 0).front() as Dictionary).get(GdssValue.CALC_KEY)
	t.check(GdssCalc.has_dynamic_ref(dynamic), "a variable reference makes calc dynamic")
	t.check(not GdssCalc.has_dynamic_ref(constant), "pure numbers stay static")
