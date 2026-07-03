extends RefCounted


const TC: GDScript = preload("res://tests/gdss_test_context.gd")

const FIXTURE_STATE: String = """
Button {
	bg_color: "#181818"
	:disabled {
		modulate: "#ff0000"
		opacity: 0.5
		transform_scale: 1.2 1.2
		cursor: POINTING
		font: font("res://_local/jetbrains_mono.ttf")
	}
}
"""

const FIXTURE_BASE: String = """
Button {
	bg_color: "#181818"
	modulate: "#00ff00"
}
"""

const FIXTURE_PLAIN: String = """
Button {
	bg_color: "#181818"
}
"""


func run(t: TC) -> void:
	t.apply_fixture(FIXTURE_STATE)
	var button: Button = t.make_styled_button()
	var handler: GdssPropHandler = GdssNodeHandler.get_primary_handler(button)
	button.disabled = true
	GDSS.refresh(button)
	t.check_eq(handler.current_state, "disabled", "disabled state active")
	t.check_eq(button.modulate, Color(1, 0, 0, 0.5), "modulate supplies rgb, opacity owns alpha")
	t.check_eq(button.offset_transform_scale, Vector2(1.2, 1.2), "transform prop applied")
	t.check_eq(int(button.mouse_default_cursor_shape), int(Control.CURSOR_POINTING_HAND), "cursor applied")
	t.check(button.has_theme_font_override("font"), "state font override applied")
	button.disabled = false
	GDSS.refresh(button)
	t.check_eq(handler.current_state, "normal", "back to normal state")
	t.check_eq(button.modulate, Color.WHITE, "modulate resets when the state stops styling it")
	t.check_eq(button.offset_transform_scale, Vector2.ONE, "transform resets on state exit")
	t.check_eq(int(button.mouse_default_cursor_shape), int(Control.CURSOR_ARROW), "cursor resets on state exit")
	t.check(not button.has_theme_font_override("font"), "font override removed on state exit")
	button.free()
	t.apply_fixture(FIXTURE_BASE)
	var base_button: Button = t.make_styled_button()
	t.check_eq(base_button.modulate, Color(0, 1, 0, 1), "base-state modulate applied")
	GdssNodeHandler.unbind(base_button)
	t.check_eq(base_button.modulate, Color.WHITE, "unbind resets node properties")
	base_button.free()
	t.apply_fixture(FIXTURE_BASE)
	var reparse_button: Button = t.make_styled_button()
	t.check_eq(reparse_button.modulate, Color(0, 1, 0, 1), "modulate applied before reparse")
	t.apply_fixture(FIXTURE_PLAIN)
	t.check_eq(reparse_button.modulate, Color.WHITE, "reparse without modulate resets it")
	t.check_eq(GdssNodeHandler.get_primary_handler(reparse_button)._get_val("bg_color"), Color("#181818"), "restyled value still applies after reparse")
