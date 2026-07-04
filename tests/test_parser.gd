extends RefCounted


const TC: GDScript = preload("res://tests/gdss_test_context.gd")

const FIXTURE_BASIC: String = """
Button {
	bg_color: "#112233"
	corner_radius: 8 8 8 8
	font_size: 15
	:hover {
		bg_color: RED
	}
}
Panel, PanelContainer {
	bg_color: "#0000ff"
}
"""

const FIXTURE_CLASSES: String = """
Button {
	bg_color: "#101010"
	Ghost {
		border: 1 2 3 4
		Inner {
			corner_radius: 9 9 9 9
		}
	}
	%Flat {
		bg_color: TRANSPARENT
	}
	on_show() {
		opacity: 0
	}
}
"""

const FIXTURE_COMPOSITE_CLASS: String = """
var pad: 6
Button {
	corner_radius: 2 2 2 2
	Card {
		corner_radius_top_left: 30
		padding_left: $pad
	}
	%Fancy {
		border_top: 3
	}
	transition_func: quint
	transition_type: ease_in
	cursor: pointing
}
"""

const FIXTURE_VEC2: String = """
@global var lift: -4.0
Button {
	transform_scale: 1.5
	transform_position: 0 $lift
	transform_pivot_ratio_y: 1.0
	Lift {
		transform_scale_x: 2
	}
}
"""

const FIXTURE_VALUES: String = """
var unit: 12
@global var accent: "#3b82f6"
Button {
	font_size: calc($unit * 2)
	bg_color: rgba(1, 0, 0, 1)
	border_color: $accent
	padding_left: 4
	corner_radius: $unit $unit $unit $unit
	transform_scale: 2 3
	anti_aliasing: false
}
Label {
	:hover, :focus {
		font_size: 20
	}
}
"""


func run(t: TC) -> void:
	var basic: Dictionary = t.parse_fixture(FIXTURE_BASIC)
	var basic_all: Dictionary = (basic.get("Button", {}) as Dictionary).get("all", {})
	t.check_eq(basic_all.size(), 3, "entries store only user-written props, no injected defaults")
	t.check(not basic.has("Label"), "unstyled selectors get no entry")
	t.check_eq(t.entry_val(basic, "Button", "all", "bg_color"), Color("#112233"), "hex color parses to Color")
	t.check_eq(t.entry_val(basic, "Button", "all", "corner_radius"), Vector4i(8, 8, 8, 8), "composite4 shorthand parses to Vector4i")
	t.check_eq(t.entry_val(basic, "Button", "all", "font_size"), 15, "int prop parses to int")
	t.check_eq(t.entry_val(basic, "Button", "hover", "bg_color"), "RED", "named color stays a string for late resolve")
	t.check_eq(t.entry_val(basic, "Panel", "all", "bg_color"), Color("#0000ff"), "comma group styles first selector")
	t.check_eq(t.entry_val(basic, "PanelContainer", "all", "bg_color"), Color("#0000ff"), "comma group styles second selector")
	var classes: Dictionary = t.parse_fixture(FIXTURE_CLASSES)
	var ghost: Dictionary = t.class_entry(classes, "Button", "Ghost")
	t.check_eq((ghost.get("all", {}) as Dictionary).get("border"), Vector4i(1, 2, 3, 4), "class block stores own props")
	t.check(not (ghost.get("all", {}) as Dictionary).has("bg_color"), "top-level class does not flatten base props")
	var inner: Variant = (ghost.get("_classes", {}) as Dictionary).get("Inner")
	t.check(inner is Dictionary, "nested class parses")
	if inner is Dictionary:
		t.check_eq(((inner as Dictionary).get("all", {}) as Dictionary).get("border"), Vector4i(1, 2, 3, 4), "nested class inherits outer class props")
		t.check_eq(((inner as Dictionary).get("all", {}) as Dictionary).get("corner_radius"), Vector4i(9, 9, 9, 9), "nested class keeps own props")
	var variations: Variant = (classes.get("Button", {}) as Dictionary).get("_variations")
	t.check(variations is Dictionary and (variations as Dictionary).has("Flat"), "%Variation routed to _variations")
	t.check_eq(t.entry_val(classes, "Button", "on_show", "opacity"), 0, "event block stored under event key")
	var values: Dictionary = t.parse_fixture(FIXTURE_VALUES)
	var calc_val: Variant = t.entry_val(values, "Button", "all", "font_size")
	t.check(calc_val is Dictionary and (calc_val as Dictionary).has("__gdss_calc__"), "calc() stored as calc AST")
	var method_val: Variant = t.entry_val(values, "Button", "all", "bg_color")
	t.check(method_val is Dictionary and (method_val as Dictionary).get("__gdss_method__") == "rgba", "method call stored as descriptor")
	t.check_eq(t.entry_val(values, "Button", "all", "border_color"), "__gdss_global__accent", "global ref substituted to sentinel")
	var padding: Variant = t.entry_val(values, "Button", "all", "padding")
	t.check_eq(padding, Vector4i(4, 0, 0, 0), "per-side key folds into composite in node block")
	var radius: Variant = t.entry_val(values, "Button", "all", "corner_radius")
	t.check(radius is Dictionary and (radius as Dictionary).has("__gdss_composite4__"), "var-ref composite deferred as sentinel")
	t.check_eq(t.entry_val(values, "Button", "all", "transform_scale"), Vector2(2, 3), "two numeric tokens parse to Vector2")
	t.check_eq(t.entry_val(values, "Button", "all", "anti_aliasing"), false, "boolean parses")
	t.check_eq(t.entry_val(values, "Label", "hover", "font_size"), 20, "comma state group styles first state")
	t.check_eq(t.entry_val(values, "Label", "focus", "font_size"), 20, "comma state group styles second state")
	t.check_eq(GdssInterpreter.globals.get("accent"), Color("#3b82f6"), "global var accumulates as Color")
	t.check_eq(GdssInterpreter._local_vars.get("unit"), 12, "local var accumulates")
	var composite: Dictionary = t.parse_fixture(FIXTURE_COMPOSITE_CLASS)
	var card: Dictionary = t.class_entry(composite, "Button", "Card")
	var card_radius: Variant = (card.get("all", {}) as Dictionary).get("corner_radius")
	t.check(card_radius is Dictionary and (card_radius as Dictionary).has("__gdss_composite4_patch__"), "per-side key in a class defers as a patch")
	if card_radius is Dictionary:
		t.check_eq(((card_radius as Dictionary)["__gdss_composite4_patch__"] as Dictionary).get(0), 30, "class patch records only the set side")
	var card_padding: Variant = (card.get("all", {}) as Dictionary).get("padding")
	t.check(card_padding is Dictionary and (card_padding as Dictionary).has("__gdss_composite4_patch__"), "per-side var ref in a class defers as a patch")
	if card_padding is Dictionary:
		var patch: Dictionary = (card_padding as Dictionary)["__gdss_composite4_patch__"]
		t.check_eq(patch.get(0), "__gdss_local__pad", "class patch keeps the var sentinel")
	var fancy: Variant = ((composite.get("Button", {}) as Dictionary).get("_variations", {}) as Dictionary).get("Fancy")
	t.check(fancy is Dictionary, "variation block parses")
	if fancy is Dictionary:
		var fancy_border: Variant = ((fancy as Dictionary).get("all", {}) as Dictionary).get("border")
		t.check(fancy_border is Dictionary and (fancy_border as Dictionary).has("__gdss_composite4_patch__"), "per-side key in a variation defers as a patch")
		if fancy_border is Dictionary:
			t.check_eq(((fancy_border as Dictionary)["__gdss_composite4_patch__"] as Dictionary).get(2), 3, "variation patch records only the top side")
	t.check_eq(t.entry_val(composite, "Button", "all", "transition_func"), "QUINT", "transition_func normalized to upper case")
	t.check_eq(t.entry_val(composite, "Button", "all", "transition_type"), "EASE_IN", "transition_type normalized to upper case")
	t.check_eq(t.entry_val(composite, "Button", "all", "cursor"), "POINTING", "cursor normalized to upper case")
	t.check_eq(GdssPropHandler._resolve_ease_val(1), Tween.EASE_OUT, "int transition_type resolves through enum keys")
	t.check_eq(GdssPropHandler._resolve_ease_val("nonsense"), Tween.EASE_OUT, "unknown transition_type falls back to declared default")
	t.check_eq(GdssPropHandler._resolve_trans_val(6), Tween.TRANS_ELASTIC, "int transition_func resolves through enum keys")
	var vec2: Dictionary = t.parse_fixture(FIXTURE_VEC2)
	t.check_eq(t.entry_val(vec2, "Button", "all", "transform_scale"), Vector2(1.5, 1.5), "single vector2 value splats to both components")
	var lift_pos: Variant = t.entry_val(vec2, "Button", "all", "transform_position")
	t.check(lift_pos is Dictionary and (lift_pos as Dictionary).has("__gdss_composite2__"), "var-ref vector2 deferred as composite2 sentinel")
	if lift_pos is Dictionary:
		var lift_parts: Array = (lift_pos as Dictionary).get("__gdss_composite2__", [])
		t.check_eq(lift_parts.back(), "__gdss_global__lift", "deferred vector2 component keeps the var sentinel")
	t.check_eq(t.entry_val(vec2, "Button", "all", "transform_pivot_ratio"), Vector2(0.5, 1.0), "vector2 component key folds onto the prop default")
	var lift_class: Dictionary = t.class_entry(vec2, "Button", "Lift")
	var lift_scale: Variant = (lift_class.get("all", {}) as Dictionary).get("transform_scale")
	t.check(lift_scale is Dictionary and (lift_scale as Dictionary).has("__gdss_composite4_patch__"), "vector2 component in a class defers as a patch")
	if lift_scale is Dictionary:
		t.check_eq(((lift_scale as Dictionary)["__gdss_composite4_patch__"] as Dictionary).get(0), 2, "vector2 class patch records only the x side")
