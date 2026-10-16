extends RefCounted


const TC: GDScript = preload("res://tests/gdss_test_context.gd")

const FIXTURE: String = """
@global var accent: "#3b82f6"
@instance var ink: "#000000"
@scheme dark {
}
@scheme light {
	accent: "#dd4400"
}
Button {
	bg_color: $accent
	border_color: mix($accent, $ink, 0.5)
	font_color: contrast($accent)
}
"""

const FULLY_SHARED_FIXTURE: String = """
@global var accent: "#3b82f6"
@global var spare: "#ffffff"
Button {
	bg_color: $accent
}
"""


func _vals(button: Button) -> Dictionary:
	var stylebox: GdssStylebox = GdssNodeBinder.get_primary_stylebox(button)
	return stylebox._build_style_vals(stylebox._resolve_gdss_node(), stylebox._resolve_entry(), stylebox._get_state())


func run(t: TC) -> void:
	t.apply_fixture(FIXTURE)
	var a: Button = t.make_styled_button()
	var b: Button = t.make_styled_button()
	GDSS.set_instance_var(b, "ink", Color.WHITE)
	var shared: GdssSharedEntry = GdssNodeBinder.get_primary_stylebox(a)._shared
	var state: String = GdssNodeBinder.get_primary_stylebox(a)._get_state()
	_vals(a)
	t.check(shared.is_global_only(state, "bg_color"), "a global-only value is shared")
	t.check(not shared.is_global_only(state, "border_color"), "a value that may read an instance var stays per node")
	GDSS.set_global_var("accent", Color.RED)
	await t.await_frames(1)
	t.check_eq(_vals(a).get("bg_color"), Color.RED, "first node sees the new global")
	t.check_eq(_vals(b).get("bg_color"), Color.RED, "second node sees the same shared global")
	t.check(_vals(a).get("border_color") != _vals(b).get("border_color"), "instance-dependent values differ per node")
	t.check_eq(a.get_theme_color("font_color"), GdssNodeBinder.get_primary_stylebox(a)._get_val("font_color"), "theme override follows the global")
	GDSS.set_global_var("accent", Color.BLUE)
	await t.await_frames(1)
	t.check_eq(_vals(b).get("bg_color"), Color.BLUE, "a later change is not served from the previous generation")
	GDSS.set_scheme("light", 0.1)
	await t.await_seconds(0.25)
	t.check_eq(_vals(a).get("bg_color"), Color("#dd4400"), "a scheme tween settles every node on the target")
	t.check_eq(_vals(b).get("bg_color"), Color("#dd4400"), "including nodes sharing the entry")
	t.check_eq(b.get_theme_color("font_color"), GdssNodeBinder.get_primary_stylebox(b)._get_val("font_color"), "theme overrides settle with the scheme")
	GDSS.set_scheme("dark")
	await t.await_frames(1)
	GDSS.reset_global_vars()
	await t.await_frames(1)
	await _run_fully_shared(t)


func _run_fully_shared(t: TC) -> void:
	t.apply_fixture(FULLY_SHARED_FIXTURE)
	var a: Button = t.make_styled_button()
	var b: Button = t.make_styled_button()
	var stylebox: GdssStylebox = GdssNodeBinder.get_primary_stylebox(a)
	var before: Dictionary = _vals(a)
	t.check(is_same(before, _vals(b)), "fully shared nodes point at one values dictionary")
	var revision: int = stylebox._style_revision
	GDSS.set_global_var("spare", Color.RED)
	await t.await_frames(1)
	t.check(is_same(_vals(a), before), "an unrelated global keeps the shared values")
	t.check_eq(stylebox._style_revision, revision, "an unrelated global does not force a redraw")
	GDSS.set_global_var("accent", Color.RED)
	await t.await_frames(1)
	t.check_eq(_vals(a).get("bg_color"), Color.RED, "a used global still updates the shared values")
	t.check(stylebox._style_revision != revision, "a used global forces a redraw")
	GDSS.reset_global_vars()
	await t.await_frames(1)
