extends RefCounted


const TC: GDScript = preload("res://tests/gdss_test_context.gd")

const FIXTURE_STATES: String = """
Button {
	bg_color: "#223344"
	:disabled {
		bg_color: "#ff0000"
	}
}
"""

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
	t.check(renderer._fade.tween != null, "a new bg_texture fades in")
	await t.await_seconds(0.25)
	t.check(renderer._fade == null or renderer._fade.tween == null, "a finished fade drops its tween so the renderer can be freed")
	var weak: WeakRef = weakref(renderer)
	stylebox._gpu = null
	renderer = null
	t.check(weak.get_ref() == null, "a dropped renderer is freed instead of kept alive by its fade tween")
	RenderingServer.free_rid(ci)
	button.free()
	await _check_fade_lifecycle(t)
	await _check_redraw_skip(t)
	_check_tree_exit_release(t)


func _check_fade_lifecycle(t: TC) -> void:
	var node: Control = Control.new()
	t.holder.add_child(node)
	var ci: RID = RenderingServer.canvas_item_create()
	var renderer: GdssGpuRenderer = GdssGpuRenderer.new(func() -> void: pass)
	renderer.draw(ci, Rect2(0, 0, 120, 40), {"bg_color": Color.RED}, node, 0.1, 0)
	t.check(renderer._fade == null, "a panel without bg_texture never creates a fade")
	var icon: Texture2D = load("res://meta/icon.png") as Texture2D
	renderer.draw(ci, Rect2(0, 0, 120, 40), {"bg_texture": icon}, node, 0.1, 1)
	t.check(renderer._fade != null and renderer._fade.tween != null, "a bg_texture creates a running fade")
	await t.await_seconds(0.2)
	var fade: WeakRef = weakref(renderer._fade)
	renderer.draw(ci, Rect2(0, 0, 120, 40), {}, node, 0.1, 2)
	t.check(renderer._fade.tween != null, "removing the texture fades it out")
	await t.await_seconds(0.2)
	renderer.draw(ci, Rect2(0, 0, 120, 40), {}, node, 0.1, 3)
	t.check(renderer._fade == null, "a fade that settles on no texture is dropped")
	t.check(fade.get_ref() == null, "the dropped fade is freed")
	renderer.release()
	RenderingServer.free_rid(ci)
	node.free()


func _check_tree_exit_release(t: TC) -> void:
	t.apply_fixture(FIXTURE_STATES)
	var button: Button = t.make_styled_button()
	var stylebox: GdssStylebox = GdssNodeBinder.get_primary_stylebox(button)
	var ci: RID = RenderingServer.canvas_item_create()
	stylebox.draw(ci, Rect2(0, 0, 120, 40))
	t.check(stylebox._gpu.canvas_item.is_valid(), "a drawn panel owns a GPU canvas item")
	t.holder.remove_child(button)
	t.check(not stylebox._gpu.canvas_item.is_valid(), "leaving the tree releases the GPU canvas item")
	t.check(GdssNodeBinder.is_bound(button), "a node that only left the tree stays bound")
	t.holder.add_child(button)
	RenderingServer.free_rid(ci)


func _check_redraw_skip(t: TC) -> void:
	t.apply_fixture(FIXTURE_STATES)
	var button: Button = t.make_styled_button()
	var stylebox: GdssStylebox = GdssNodeBinder.get_primary_stylebox(button)
	var ci: RID = RenderingServer.canvas_item_create()
	var rect: Rect2 = Rect2(0, 0, 120, 40)
	stylebox.draw(ci, rect)
	var renderer: GdssGpuRenderer = stylebox._gpu
	t.check(renderer.is_current(ci, rect, stylebox._style_revision), "an unchanged panel is current after drawing")
	stylebox.draw(ci, Rect2(0, 0, 200, 40))
	t.check(not renderer.is_current(ci, rect, stylebox._style_revision), "a resized panel is drawn again")
	stylebox.draw(ci, rect)
	button.disabled = true
	GDSS.refresh(button)
	stylebox.draw(ci, rect)
	t.check_eq(renderer.params().get(&"u_fill_a"), Color("#ff0000"), "a state change reaches the shader")
	var quality: GDSS.BlurQuality = GDSS.blur_quality
	GDSS.blur_quality = GDSS.BlurQuality.LOW
	t.check(not renderer.is_current(ci, rect, stylebox._style_revision), "a render setting change forces a redraw")
	GDSS.blur_quality = quality
	RenderingServer.free_rid(ci)
	button.free()
