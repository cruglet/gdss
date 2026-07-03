extends RefCounted


const TC: GDScript = preload("res://tests/gdss_test_context.gd")

const FIXTURE: String = """
@global var accent: "#3b82f6"
Button {
	bg_color: "#181818"
	corner_radius: 4 4 4 4
	:disabled {
		bg_color: "#303030"
	}
	Ghost {
		bg_color: "#00ff00"
	}
}
"""


func run(t: TC) -> void:
	t.apply_fixture(FIXTURE)
	var button: Button = t.make_styled_button()
	var handler: GdssPropHandler = GdssNodeHandler.get_primary_handler(button)
	GDSS.set_override_text(button, "bg_color: \"#ffaa00\"")
	t.check_eq(handler._get_val("bg_color"), Color("#ffaa00"), "text override beats the base entry")
	GDSS.add_class(button, "Ghost")
	t.check_eq(handler._get_val("bg_color"), Color("#ffaa00"), "text override beats classes")
	button.disabled = true
	GDSS.refresh(button)
	t.check_eq(handler._get_val("bg_color"), Color("#ffaa00"), "all-state override wins inside states")
	button.disabled = false
	GDSS.refresh(button)
	GDSS.set_override_text(button, "bg_color: $accent")
	t.check_eq(handler._get_val("bg_color"), Color("#3b82f6"), "override resolves globals")
	GDSS.set_global_var("accent", Color.RED)
	await t.await_frames(1)
	t.check_eq(handler._get_val("bg_color"), Color.RED, "override tracks live global changes")
	GDSS.reset_global_var("accent")
	await t.await_frames(1)
	GDSS.set_override_text(button, ":disabled { bg_color: \"#112233\" }")
	t.check_eq(handler._get_val("bg_color"), Color("#00ff00"), "state-scoped override leaves other states on the class value")
	button.disabled = true
	GDSS.refresh(button)
	t.check_eq(handler._get_val("bg_color"), Color("#112233"), "state-scoped override applies in its state")
	button.disabled = false
	GDSS.refresh(button)
	GDSS.set_override_text(button, "corner_radius_top_left: 30\npadding: 2 2 2 2")
	t.check_eq(handler._get_val("corner_radius"), Vector4i(30, 4, 4, 4), "per-side key folds onto the styled composite")
	t.check_eq(handler.get_content_margin(SIDE_LEFT), 2.0, "override padding applies as content margin")
	GDSS.clear_overrides(button)
	t.check(not button.has_meta(GDSS.OVERRIDES_META), "clear_overrides removes the meta")
	t.check_eq(handler._get_val("bg_color"), Color("#00ff00"), "cleared override falls back to class value")
	GDSS.remove_class(button, "Ghost")
	GDSS.set_prop_override(button, "bg_color", Color("#8800ff"))
	t.check_eq(handler._get_val("bg_color"), Color("#8800ff"), "dictionary override applies")
	GDSS.set_prop_override(button, "font_size", 22)
	t.check_eq(button.get_theme_font_size("font_size"), 22, "dictionary override reaches theme overrides")
	GDSS.clear_prop_override(button, "bg_color")
	t.check_eq(handler._get_val("bg_color"), Color("#181818"), "cleared dictionary key falls back")
	GDSS.clear_overrides(button)
	var clone_source: Button = t.make_styled_button()
	GDSS.set_override_text(clone_source, "bg_color: \"#ff00ff\"")
	var clone: Button = clone_source.duplicate() as Button
	t.add_styled(clone)
	var clone_handler: GdssPropHandler = GdssNodeHandler.get_primary_handler(clone)
	t.check_eq(clone_handler._get_val("bg_color"), Color("#ff00ff"), "overrides survive duplicate()")
	GdssInterpreter._override_entry_cache.clear()
	GDSS.set_override_text(clone_source, "bg_color: \"#010203\"")
	GDSS.set_override_text(clone, "bg_color: \"#010203\"")
	clone_handler._resolve_entry()
	GdssNodeHandler.get_primary_handler(clone_source)._resolve_entry()
	t.check_eq(GdssInterpreter._override_entry_cache.size(), 1, "identical override text parses once")
	var label: Label = Label.new()
	label.text = "plain"
	t.add_styled(label)
	GDSS.set_override_text(label, "font_color: \"#123456\"")
	t.check_eq(label.get_theme_color("font_color"), Color("#123456"), "override styles a selector with no stylesheet entry")
