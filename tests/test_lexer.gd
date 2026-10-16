extends RefCounted


const TC: GDScript = preload("res://tests/gdss_test_context.gd")


func _tokens(source: String) -> Array[String]:
	return GdssLexer.tokenize(source)


func run(t: TC) -> void:
	t.check_eq(_tokens("Button { bg_color: \"#fff\" }"), ["Button", "{", "bg_color", ":", "\"#fff\"", "}"] as Array[String], "a hash inside quotes is not a comment")
	t.check_eq(_tokens("Button:hover { } # trailing"), ["Button", ":", "hover", "{", "}"] as Array[String], "a trailing comment is dropped")
	t.check_eq(_tokens("Button :: focus"), ["Button", "::", "focus"] as Array[String], "two colons merge across whitespace")
	t.check_eq(_tokens(":\r:("), ["::", "("] as Array[String], "a stray carriage return does not split a merged colon")
	t.check_eq(_tokens("Panel { > > Label }"), ["Panel", "{", ">>", "Label", "}"] as Array[String], "two combinators merge into >>")
	t.check_eq(_tokens("font: font(\"a b.ttf\"); size: 2"), ["font", ":", "font", "(", "\"a b.ttf\"", ")", "size", ":", "2"] as Array[String], "quoted spaces stay inside one token")
	t.check_eq(_tokens("@global var accent: red\nLabel {}"), ["Label", "{", "}"] as Array[String], "global declarations are skipped")
	t.check_eq(GdssLexer.tokenize_value("mix(a, b) # note"), ["mix", "(", "a", ",", "b", ")"] as Array[String], "value tokens stop at a comment")
	t.check_eq(GdssLexer.normalize_separators("a = 1\nb = f(x = 2) # c = d\ns = \"e = f\""), "a : 1\nb : f(x = 2) # c = d\ns : \"e = f\"", "only top-level equals outside quotes and comments become colons")
	t.check_eq(GdssLexer.split_statements("a: 1; b: \"x;y\"; c"), PackedStringArray(["a: 1", " b: \"x;y\"", " c"]), "statements split on unquoted semicolons")
	t.check_eq(GdssLexer.split_args("a, f(b, c), \"d, e\""), ["a", "f(b, c)", "\"d, e\""] as Array[String], "arguments split at top-level commas")
	t.check_eq(GdssLexer.brace_delta("{ \"}\" {"), 2, "quoted braces do not count")
	t.check_eq(GdssLexer.strip_comment("a: '#x' # y"), "a: '#x'", "comments strip after quoted hashes")
