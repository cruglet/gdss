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

const FIXTURE_NESTED: String = """
@global var accent: "#3b82f6"
@global var bg: "#0d0d14"
@global var text: "#ffffff"
@scheme dark {
}
@scheme light {
	bg: "#e8eaf2"
	text: "#101018"
}
@scheme lightblue extends light {
	accent: "#0044ff"
}
@scheme deep extends lightblue {
	text: "#334455"
}
@scheme early extends late {
}
@scheme late {
	bg: "#222222"
}
Button {
	bg_color: $bg
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
	button.free()
	t.apply_fixture(FIXTURE_NESTED)
	var nested: Button = t.make_styled_button()
	var nested_handler: GdssPropHandler = GdssNodeHandler.get_primary_handler(nested)
	t.check_eq(GDSS.get_scheme_var("lightblue", "bg"), Color("#e8eaf2"), "child scheme inherits parent values")
	t.check_eq(GDSS.get_scheme_var("lightblue", "accent"), Color("#0044ff"), "child scheme keeps own values")
	t.check_eq(GDSS.get_scheme_var("deep", "bg"), Color("#e8eaf2"), "grandchild inherits through the chain")
	t.check_eq(GDSS.get_scheme_var("deep", "accent"), Color("#0044ff"), "grandchild inherits parent overrides")
	t.check_eq(GDSS.get_scheme_var("deep", "text"), Color("#334455"), "grandchild keeps own values")
	t.check_eq(GDSS.get_scheme_var("early", "bg"), Color("#222222"), "forward-declared parent resolves")
	GDSS.set_scheme("deep")
	await t.await_frames(1)
	t.check_eq(nested_handler._get_val("bg_color"), Color("#e8eaf2"), "applied nested scheme styles through inherited globals")
	t.check_eq(GdssInterpreter.globals.get("text"), Color("#334455"), "applied nested scheme layers own deltas last")
	GDSS.set_scheme("dark")
	await t.await_frames(1)
	t.check_eq(nested_handler._get_val("bg_color"), Color("#0d0d14"), "switching back restores the base palette")
	t.check(not GDSS.get_schemes().has(GdssInterpreter.SCHEME_PARENT_KEY), "parent marker never leaks as a scheme name")
	GdssInterpreter.schemes["loop_a"] = {GdssInterpreter.SCHEME_PARENT_KEY: "loop_b"}
	GdssInterpreter.schemes["loop_b"] = {GdssInterpreter.SCHEME_PARENT_KEY: "loop_a"}
	t.check_eq(GdssInterpreter._scheme_chain("loop_a").size(), 2, "runtime chain walk terminates on cycles")
	GdssInterpreter.schemes.erase("loop_a")
	GdssInterpreter.schemes.erase("loop_b")
	GdssInterpreter.current_scheme = ""
	var bytes: PackedByteArray = GdssStorage.compiled_bytes("src", {"parsed": {}}, 1)
	t.check(GdssStorage.is_current_format(bytes_to_var(bytes)), "compiled bytes carry the current format version")
	t.check(not GdssStorage.is_current_format({"source": "x", "data": {}}), "format-less bundle rejected")
	t.check(not GdssStorage.is_current_format({"format": 1}), "old format version rejected")
	t.check(not GdssInterpreter.parsed.is_empty(), "runtime bundle load or parse fallback populated the theme")
