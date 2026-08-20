extends RefCounted


const TC: GDScript = preload("res://tests/gdss_test_context.gd")

const FIXTURE: String = """
@global var accent: "#3b82f6"
Panel {
	border: 2 2 2 2
	border_color: RED
	border_color_top: $accent
	shadow_bottom: 5
	Ghost {
		border_color_left: alpha("#ffffff", 0.5)
	}
	:hover {
		border_color_right: LIME
	}
}
PanelContainer {
	border_color_top: RED
	border_color: LIME
}
"""


func run(t: TC) -> void:
	t.apply_fixture(FIXTURE)
	var parsed: Dictionary = t.parse_fixture(FIXTURE)
	var raw: Variant = t.entry_val(parsed, "Panel", "all", "border_color")
	t.check(raw is Dictionary and (raw as Dictionary).has(GdssInterpreter.COLOR4_KEY), "per-side color folds into the color4 sentinel")
	if raw is Dictionary:
		t.check_eq((raw as Dictionary)[GdssInterpreter.COLOR4_KEY], ["RED", "RED", "__gdss_global__accent", "RED"], "unnamed sides keep the shorthand value")
	t.check_eq(t.entry_val(parsed, "Panel", "all", "shadow"), Vector4i(0, 0, 0, 5), "a lone shadow side leaves the others at zero")
	t.check_eq(t.entry_val(parsed, "PanelContainer", "all", "border_color"), "LIME", "a later shorthand resets every side")

	var panel: Panel = Panel.new()
	t.add_styled(panel)
	var handler: GdssPropHandler = GdssNodeHandler.get_primary_handler(panel)
	t.check_eq(handler._get_val("border_color"), [Color.RED, Color.RED, Color("#3b82f6"), Color.RED], "per-side colors resolve to one color per side")
	t.check_eq(handler._get_val("shadow"), Vector4i(0, 0, 0, 5), "per-side shadow resolves to a single side")
	GDSS.add_class(panel, "Ghost")
	t.check_eq(handler._get_val("border_color"), [Color(1, 1, 1, 0.5), Color.RED, Color("#3b82f6"), Color.RED], "a class patches its own side onto the inherited sides")
	panel.free()

	var hovered: Panel = Panel.new()
	t.add_styled(hovered)
	var hover_handler: GdssPropHandler = GdssNodeHandler.get_primary_handler(hovered)
	t.check_eq(hover_handler._get_val_cached("border_color", hover_handler._resolve_entry(), "hover", null), [Color.RED, Color.LIME, Color("#3b82f6"), Color.RED], "a state patches its own side onto the base sides")
	hovered.free()

	var uniform: GdssPropHandler = GdssPropHandler.new()
	t.check(uniform._border_side_colors([Color.RED, Color.RED, Color.RED, Color.RED]).is_empty(), "four equal sides stay on the single-ring path")
	t.check(uniform._border_side_colors([Color.RED, Color.RED, GdssGradient.new(), Color.RED]).is_empty(), "a gradient among the sides drives the whole border")
	t.check_eq(uniform._border_base([Color.RED, Color.RED, Color.LIME, Color.RED]), Color.RED, "the shorthand value stays the fallback base")
	t.check_eq(uniform._corner_splits(Vector4.ZERO, 8), PackedInt32Array([0, 1, 2, 3]), "square corners split on the corner point itself")
	t.check_eq(uniform._corner_splits(Vector4(4, 4, 4, 4), 8), PackedInt32Array([4, 13, 22, 31]), "rounded corners split halfway through the arc")
	t.check_eq(GdssPropHandler._max_side(Vector4(0, 0, 0, 5)), 5.0, "the widest side drives the shadow quad")
