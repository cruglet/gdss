extends RefCounted


const TC: GDScript = preload("res://tests/gdss_test_context.gd")

const FIXTURE: String = """
Button {
	bg_color: "#223344"
	bg_texture: texture("res://meta/icon.png")
	transition_time: 0.1
}
"""


func run(t: TC) -> void:
	if not GDSS.gpu_panels_enabled():
		return
	t.apply_fixture(FIXTURE)
	var button: Button = t.make_styled_button()
	var stylebox: GdssStylebox = GdssNodeBinder.get_primary_stylebox(button)
	var ci: RID = RenderingServer.canvas_item_create()
	stylebox.draw(ci, Rect2(0, 0, 120, 40))
	var renderer: GdssGpuRenderer = stylebox._gpu
	t.check(renderer != null and renderer.canvas_item.is_valid(), "a GPU draw creates the renderer and its canvas item")
	t.check(renderer._fade_tween != null, "a new bg_texture fades in")
	await t.await_seconds(0.25)
	t.check(renderer._fade_tween == null, "a finished fade drops its tween so the renderer can be freed")
	var weak: WeakRef = weakref(renderer)
	stylebox._gpu = null
	renderer = null
	t.check(weak.get_ref() == null, "a dropped renderer is freed instead of kept alive by its fade tween")
	RenderingServer.free_rid(ci)
	button.free()
