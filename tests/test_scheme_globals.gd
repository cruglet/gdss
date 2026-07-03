extends RefCounted


const TC: GDScript = preload("res://tests/gdss_test_context.gd")

const FIXTURE: String = """
@global var accent: "#3b82f6"
@instance var glow: 2.0
@scheme dark {
}
@scheme light {
	accent: "#dd4400"
}
Button {
	bg_color: $accent
	font_color: contrast($accent)
}
"""


func run(t: TC) -> void:
	t.apply_fixture(FIXTURE)
	var button: Button = t.make_styled_button()
	var handler: GdssPropHandler = GdssNodeHandler.get_primary_handler(button)
	t.check_eq(handler._get_val("bg_color"), Color("#3b82f6"), "global resolves through $ref")
	GDSS.set_global_var("accent", Color.RED)
	await t.await_frames(1)
	t.check_eq(handler._get_val("bg_color"), Color.RED, "set_global_var applies after deferred flush")
	GDSS.reset_global_var("accent")
	await t.await_frames(1)
	t.check_eq(handler._get_val("bg_color"), Color("#3b82f6"), "reset_global_var restores declared value")
	t.check(GDSS.has_scheme("light"), "schemes accumulate")
	GDSS.set_scheme("light")
	await t.await_frames(1)
	t.check_eq(handler._get_val("bg_color"), Color("#dd4400"), "scheme switch rebinds globals")
	GDSS.set_scheme("dark")
	await t.await_frames(1)
	t.check_eq(handler._get_val("bg_color"), Color("#3b82f6"), "empty scheme restores base palette")
	t.check_eq(GDSS.get_instance_var(button, "glow"), 2.0, "instance default resolves")
	GDSS.set_instance_var(button, "glow", 5.0)
	t.check_eq(GDSS.get_instance_var(button, "glow"), 5.0, "instance override wins")
	GDSS.clear_instance_var(button, "glow")
	t.check_eq(GDSS.get_instance_var(button, "glow"), 2.0, "cleared override falls back to default")
	button.disabled = true
	GDSS.refresh(button)
	t.check_eq(handler.current_state, "disabled", "refresh re-evaluates active state")
	GdssInterpreter.current_scheme = ""
	var bytes: PackedByteArray = GdssStorage.compiled_bytes("src", {"parsed": {}}, 1)
	t.check(GdssStorage.is_current_format(bytes_to_var(bytes)), "compiled bytes carry the current format version")
	t.check(not GdssStorage.is_current_format({"source": "x", "data": {}}), "format-less bundle rejected")
	t.check(not GdssStorage.is_current_format({"format": 1}), "old format version rejected")
	t.check(not GdssInterpreter.parsed.is_empty(), "runtime bundle load or parse fallback populated the theme")
