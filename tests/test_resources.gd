extends RefCounted


const TC: GDScript = preload("res://tests/gdss_test_context.gd")
const LOGO_PATH: String = "res://meta/icon.png"

const FIXTURE: String = """
@resources {
	LOGO: texture("res://meta/icon.png")
}
@global var accent: "#3b82f6"
Button {
	bg_color: $accent
}
Panel {
	bg_color: $LOGO
}
"""

const FIXTURE_LITERAL: String = """
Panel {
	bg_color: texture("res://meta/icon.png")
}
"""

const FIXTURE_BAD: String = """
@resources {
	LOGO: texture("res://meta/icon.png")
	LOGO: texture("res://meta/icon.svg")
	GONE: texture("res://meta/nope.png")
	ODD: lighten("res://meta/icon.png")
	EMPTY:
	BROKEN: "res://meta/icon.png"
}
Label {
	font: $LOGO
}
Button {
	corner_radius: $LOGO $LOGO 0 0
}
"""


func run(t: TC) -> void:
	_check_declaration(t)
	_check_application(t)
	_check_validation(t)
	_check_symbols(t)
	t.restore_theme()


func _check_declaration(t: TC) -> void:
	var methods: PackedStringArray = GdssStylesheet.resource_methods()
	t.check(methods.has("font") and methods.has("texture"), "loader methods are discovered from the registry")
	t.check(not methods.has("lighten"), "methods that take no path are not loaders")
	var result: Dictionary = t.parse_fixture(FIXTURE)
	t.check(GdssStylesheet.resources.has("LOGO"), "the resource key is registered")
	var entry: Dictionary = GdssStylesheet.resources.get("LOGO")
	t.check_eq(entry.get("method"), "texture", "the declared loader is kept")
	t.check_eq(entry.get("path"), LOGO_PATH, "the declared path is kept")
	var used: Variant = t.entry_val(result, "Panel", "all", "bg_color")
	t.check(used is Dictionary, "a resource use parses to a method call")
	t.check_eq((used as Dictionary).get("__gdss_method__"), "texture", "the use expands to the declared loader")
	var literal: Variant = t.entry_val(t.parse_fixture(FIXTURE_LITERAL), "Panel", "all", "bg_color")
	t.check_eq((used as Dictionary).get("args"), (literal as Dictionary).get("args"), "the expansion matches a literal loader call")
	t.check(t.entry_val(result, "Button", "all", "bg_color") != null, "other values on the same block still parse")


func _check_application(t: TC) -> void:
	t.apply_fixture(FIXTURE)
	var panel: Panel = t.add_styled(Panel.new()) as Panel
	var stylebox: GdssStylebox = GdssNodeBinder.get_primary_stylebox(panel)
	t.check(stylebox != null, "the panel binds")
	t.check(stylebox._get_val("bg_color") is Texture2D, "the resource resolves to a loaded resource")
	t.check(stylebox._get_val("bg_color") == load(LOGO_PATH), "the resolved resource is the declared file")
	GdssNodeBinder.unbind(panel)
	panel.free()


func _check_validation(t: TC) -> void:
	var clean: Array[Array] = t.validate_fixture(FIXTURE)
	t.check(clean.is_empty(), "a valid resource fixture has zero errors (got: %s)" % ", ".join(t.error_messages(clean)))
	var errors: Array[Array] = t.validate_fixture(FIXTURE_BAD)
	t.check(t.has_error_containing(errors, "Resource 'LOGO' is already declared"), "duplicate key flagged")
	t.check(t.has_error_containing(errors, "points at a missing file"), "missing file flagged")
	t.check(t.has_error_containing(errors, "'lighten()' does not load a resource"), "non-loader method flagged")
	t.check(t.has_error_containing(errors, "Resource 'EMPTY' has no value"), "valueless entry flagged")
	t.check(t.has_error_containing(errors, "expects a loader call"), "a bare path instead of a loader flagged")
	t.check(t.has_error_containing(errors, "is a texture(), which property 'font' cannot take"), "type mismatch flagged")
	t.check(t.has_error_containing(errors, "cannot be a component of 'corner_radius'"), "a resource used as a number flagged")
	t.check(not t.has_error_containing(errors, "Unknown annotation"), "@resources is a known annotation")
	t.check(not t.has_error_containing(errors, "Undefined variable '$LOGO'"), "a declared resource is not an undefined variable")


func _check_symbols(t: TC) -> void:
	var index: GdssSymbols.Index = GdssSymbols.build({GdssSymbols.DOC: FIXTURE})
	var symbol: GdssSymbols.Symbol = index.get_symbol(GdssSymbols.Kind.RESOURCE, "LOGO")
	t.check(symbol != null, "the resource key is indexed as a symbol")
	t.check_eq(symbol.refs.size(), 2, "the declaration and the use are both indexed")
	t.check(symbol.declaration() != null, "the declaration is marked")
	t.check(GdssSymbols.RENAMEABLE.has(GdssSymbols.Kind.RESOURCE), "resources are renameable")
	var renamed: String = GdssSymbols.apply(FIXTURE, symbol.refs, "BRAND_LOGO")
	t.check(renamed.contains("\tBRAND_LOGO: texture("), "renaming rewrites the declaration")
	t.check(renamed.contains("bg_color: $BRAND_LOGO"), "renaming rewrites the use")
	t.check(renamed.contains(LOGO_PATH), "renaming leaves the path alone")
	t.check(not GdssSymbols.validate(index, symbol, "accent").is_empty(), "a resource cannot take a variable's name")
	t.check(GdssSymbols.validate(index, symbol, "OTHER_LOGO").is_empty(), "a free name is accepted")
	var use: GdssSymbols.Ref = null
	for entry: GdssSymbols.Ref in symbol.refs:
		if not entry.declaration:
			use = entry
			break
	t.check(use != null and index.find_at(GdssSymbols.DOC, use.line, use.from) != null, "a resource use resolves by position")
