extends RefCounted


const TC: GDScript = preload("res://tests/gdss_test_context.gd")

const FIXTURE_MAIN: String = """
@meta {
	default_scheme: dark
}
@global var accent: "#3b82f6"
@global var accent_dark: "#2563eb"
@instance var glass: 3.0
var border: 2
@scheme dark {
}
@scheme light extends dark {
	accent: "#111111"
}
Button {
	bg_color: $accent
	border: $border $border $border $border
	border_color: $accent_dark
	ZGhostButton {
		bg_color: lighten($accent, 0.1)
		:hover {
			bg_color: $accent
		}
	}
	%ZFlat {
		font_color: $glass
	}
	on_show() {
		opacity: 0
	}
}
"""

const FIXTURE_IMPORTED: String = """
@global var shared: 4
"""

const FIXTURE_IMPORTER: String = """
@import "res://imported.tgdss"
Panel {
	corner_radius: $shared $shared 0 0
}
"""

const FIXTURE_PROBLEMS: String = """
@global var zunused: 1
@global var zdup: 1
@global var zdup: 2
@global var zshadow: 1
var zshadow: 2
@scheme zmissing extends znope {
}
"""


func run(t: TC) -> void:
	var index: GdssSymbols.Index = GdssSymbols.build({GdssSymbols.DOC: FIXTURE_MAIN})
	_check_declarations(t, index)
	_check_references(t, index)
	_check_rename(t, index)
	_check_validation(t, index)
	_check_imports(t)
	_check_diagnostics(t)
	_check_project(t)


func _check_declarations(t: TC, index: GdssSymbols.Index) -> void:
	var accent: GdssSymbols.Symbol = index.get_symbol(GdssSymbols.Kind.GLOBAL_VAR, "accent")
	t.check(accent != null and accent.declaration() != null, "@global var declared")
	t.check_eq(accent.declaration().line, 4, "global declaration line")
	t.check(index.get_symbol(GdssSymbols.Kind.INSTANCE_VAR, "glass") != null, "@instance var declared")
	t.check(index.get_symbol(GdssSymbols.Kind.LOCAL_VAR, "border") != null, "local var declared")
	t.check(index.get_symbol(GdssSymbols.Kind.SCHEME, "light") != null, "scheme declared")
	t.check(index.get_symbol(GdssSymbols.Kind.CLASS, "ZGhostButton") != null, "nested class declared")
	t.check(index.get_symbol(GdssSymbols.Kind.VARIATION, "ZFlat") != null, "variation declared")
	t.check(index.get_symbol(GdssSymbols.Kind.CLASS, "Button") == null, "base type selector is not a symbol")
	t.check(index.get_symbol(GdssSymbols.Kind.CLASS, "hover") == null, "state is not a symbol")
	t.check(index.get_symbol(GdssSymbols.Kind.CLASS, "on_show") == null, "event block is not a symbol")


func _check_references(t: TC, index: GdssSymbols.Index) -> void:
	var accent: GdssSymbols.Symbol = index.get_symbol(GdssSymbols.Kind.GLOBAL_VAR, "accent")
	t.check_eq(accent.refs.size(), 5, "accent: declaration, scheme key and three uses")
	var accent_dark: GdssSymbols.Symbol = index.get_symbol(GdssSymbols.Kind.GLOBAL_VAR, "accent_dark")
	t.check_eq(accent_dark.refs.size(), 2, "accent_dark not swallowed by accent")
	var border: GdssSymbols.Symbol = index.get_symbol(GdssSymbols.Kind.LOCAL_VAR, "border")
	t.check_eq(border.refs.size(), 5, "border var: declaration plus four uses, property key excluded")
	var dark: GdssSymbols.Symbol = index.get_symbol(GdssSymbols.Kind.SCHEME, "dark")
	t.check_eq(dark.refs.size(), 3, "scheme: declaration, extends and default_scheme")
	var roles: PackedStringArray = []
	for entry: GdssSymbols.Ref in dark.refs:
		roles.append(entry.role)
	t.check(roles.has("extends") and roles.has("meta"), "scheme reference roles recorded")
	var use: GdssSymbols.Ref = null
	for entry: GdssSymbols.Ref in accent.refs:
		if entry.role == "var":
			use = entry
			break
	t.check(use != null, "variable use recorded")
	var located: GdssSymbols.Ref = index.find_at(GdssSymbols.DOC, use.line, use.from)
	t.check(located != null and located.name == "accent", "position lookup hits the reference")
	t.check(index.find_at(GdssSymbols.DOC, use.line, use.from - 2) == null, "position lookup misses outside the range")


func _check_rename(t: TC, index: GdssSymbols.Index) -> void:
	var accent: GdssSymbols.Symbol = index.get_symbol(GdssSymbols.Kind.GLOBAL_VAR, "accent")
	var renamed: String = GdssSymbols.apply(FIXTURE_MAIN, accent.refs, "brand")
	t.check(renamed.contains("@global var brand:"), "declaration renamed")
	t.check(renamed.contains("bg_color: $brand"), "use renamed")
	t.check(renamed.contains("lighten($brand, 0.1)"), "use inside a method renamed")
	t.check(renamed.contains("	brand: \"#111111\""), "scheme key renamed")
	t.check_eq(renamed.count("$accent"), 1, "only $accent_dark still matches $accent")
	t.check(renamed.contains("@global var accent_dark:"), "accent_dark declaration untouched")
	var border: GdssSymbols.Symbol = index.get_symbol(GdssSymbols.Kind.LOCAL_VAR, "border")
	var padded: String = GdssSymbols.apply(FIXTURE_MAIN, border.refs, "pad")
	t.check(padded.contains("var pad: 2"), "local declaration renamed")
	t.check(padded.contains("border: $pad $pad $pad $pad"), "property key kept while its values renamed")
	var widened: String = GdssSymbols.apply(FIXTURE_MAIN, border.refs, "outline_width")
	t.check(widened.contains("border: $outline_width $outline_width $outline_width $outline_width"), "repeated uses on one line all renamed with a longer name")
	var variation: GdssSymbols.Symbol = index.get_symbol(GdssSymbols.Kind.VARIATION, "ZFlat")
	var revariated: String = GdssSymbols.apply(FIXTURE_MAIN, variation.refs, "ZPlain")
	t.check(revariated.contains("%ZPlain {"), "variation renamed without losing its prefix")
	var override_text: String = "bg_color: complement($accent)\nfont_color: $accent_dark"
	t.check(GdssSymbols.text_has_var(override_text, "accent"), "override text variable detected")
	t.check(not GdssSymbols.text_has_var(override_text, "accen"), "partial variable name not detected")
	var override_renamed: String = GdssSymbols.rename_in_text(override_text, "accent", "brand")
	t.check_eq(override_renamed, "bg_color: complement($brand)\nfont_color: $accent_dark", "override text renamed without touching accent_dark")


func _check_validation(t: TC, index: GdssSymbols.Index) -> void:
	var accent: GdssSymbols.Symbol = index.get_symbol(GdssSymbols.Kind.GLOBAL_VAR, "accent")
	t.check(GdssSymbols.validate(index, accent, "brand").is_empty(), "fresh name accepted")
	t.check(not GdssSymbols.validate(index, accent, "accent_dark").is_empty(), "collision with another var rejected")
	t.check(not GdssSymbols.validate(index, accent, "border").is_empty(), "collision across var kinds rejected")
	t.check(not GdssSymbols.validate(index, accent, "2fast").is_empty(), "invalid identifier rejected")
	t.check(not GdssSymbols.validate(index, accent, "accent").is_empty(), "current name rejected")
	var cls: GdssSymbols.Symbol = index.get_symbol(GdssSymbols.Kind.CLASS, "ZGhostButton")
	t.check(not GdssSymbols.validate(index, cls, "Button").is_empty(), "class renamed onto a node type rejected")


func _check_imports(t: TC) -> void:
	var index: GdssSymbols.Index = GdssSymbols.build({
		GdssSymbols.DOC: FIXTURE_IMPORTER,
		"res://imported.tgdss": FIXTURE_IMPORTED,
	})
	var shared: GdssSymbols.Symbol = index.get_symbol(GdssSymbols.Kind.GLOBAL_VAR, "shared")
	t.check(shared != null, "variable declared in an imported file is indexed")
	t.check_eq(shared.declaration().file, "res://imported.tgdss", "declaration keeps its file")
	t.check_eq(shared.in_file(GdssSymbols.DOC).size(), 2, "uses in the importing file are indexed")
	var import_ref: GdssSymbols.Symbol = index.get_symbol(GdssSymbols.Kind.IMPORT, "res://imported.tgdss")
	t.check(import_ref != null, "@import path indexed for navigation")


func _check_diagnostics(t: TC) -> void:
	var index: GdssSymbols.Index = GdssSymbols.build({GdssSymbols.DOC: FIXTURE_PROBLEMS})
	var items: Array[Dictionary] = GdssSymbols.diagnostics(index)
	t.check(_has(items, "Unused global var 'zunused'"), "unused variable reported")
	t.check(_has(items, "Duplicate declaration of global var 'zdup'"), "duplicate declaration reported")
	t.check(_has(items, "'zshadow' shadows the global var"), "shadowed variable reported")
	t.check(_has(items, "Scheme 'znope' is referenced but never declared"), "undeclared scheme parent reported")


func _check_project(t: TC) -> void:
	var usage: Dictionary = GdssSymbols.scene_usage()
	var scene_classes: Dictionary = usage.get("classes")
	if scene_classes.is_empty():
		print("SKIP no scene in this project assigns a gdss class")
	else:
		var class_name_used: String = str((scene_classes.keys() as Array).front())
		var class_index: GdssSymbols.Index = GdssSymbols.build({GdssSymbols.DOC: "Panel {\n\t%s {\n\t\tbg_color: RED\n\t}\n}" % class_name_used})
		var declared: GdssSymbols.Symbol = class_index.get_symbol(GdssSymbols.Kind.CLASS, class_name_used)
		t.check(declared != null, "a nested class name is indexed")
		var scene_refs: Array[GdssSymbols.Ref] = GdssSymbols.scan_scenes(declared)
		t.check(not scene_refs.is_empty(), "scan_scenes finds the nodes that assign '%s'" % class_name_used)
		t.check_eq(scene_refs.front().role, "scene", "scene hits are tagged as scene refs")
		t.check_eq(scene_refs.front().text.substr(scene_refs.front().from, scene_refs.front().to - scene_refs.front().from), class_name_used, "the scene range covers the bare class name")
	var scene_vars: Dictionary = usage.get("variables")
	if scene_vars.is_empty():
		print("SKIP no scene in this project references a $var in override text")
		return
	var var_used: String = str((scene_vars.keys() as Array).front())
	var var_index: GdssSymbols.Index = GdssSymbols.build({GdssSymbols.DOC: "@global var %s: RED" % var_used})
	var declared_var: GdssSymbols.Symbol = var_index.get_symbol(GdssSymbols.Kind.GLOBAL_VAR, var_used)
	var override_refs: Array[GdssSymbols.Ref] = GdssSymbols.scan_scenes(declared_var)
	t.check(not override_refs.is_empty(), "scan_scenes finds '$%s' inside node override text" % var_used)
	t.check_eq(override_refs.front().text.substr(override_refs.front().from, override_refs.front().to - override_refs.front().from), var_used, "the override range covers the bare name")


func _has(items: Array[Dictionary], needle: String) -> bool:
	for item: Dictionary in items:
		if str(item.get("message")).contains(needle):
			return true
	return false
