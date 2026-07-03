extends RefCounted


const TC: GDScript = preload("res://tests/gdss_test_context.gd")

const FIXTURE: String = """
Button {
	bg_color: "#223344"
	corner_radius: 6 6 6 6
	padding: 10 10 6 6
	font_color: "#ffffff"
}
"""


func run(t: TC) -> void:
	t.apply_fixture(FIXTURE)
	var button: Button = t.make_styled_button()
	t.check(GdssNodeHandler.is_bound(button), "add_child under ENABLE binds the node")
	var handler: GdssPropHandler = GdssNodeHandler.get_primary_handler(button)
	t.check(handler != null, "primary handler exists")
	t.check(button.has_theme_stylebox_override("normal"), "stylebox override installed")
	t.check(button.get_theme_stylebox("normal") == handler, "override is the handler itself")
	t.check(button.get_theme_stylebox("hover") == handler, "stateful node shares one handler across slots")
	t.check_eq(handler._get_val("bg_color"), Color("#223344"), "handler resolves styled value")
	t.check_eq(handler.get_content_margin(SIDE_LEFT), 10.0, "padding applied as content margin")
	var ci: RID = RenderingServer.canvas_item_create()
	handler.draw(ci, Rect2(0, 0, 120, 40))
	if GDSS.gpu_panels_enabled():
		t.check(handler._gpu_ci.is_valid(), "draw creates the GPU child canvas item")
	var id: int = button.get_instance_id()
	GdssNodeHandler.unbind(button)
	t.check(not GdssNodeHandler.is_bound(button), "unbind clears the registry slot")
	t.check(not button.has_theme_stylebox_override("normal"), "unbind removes stylebox overrides")
	t.check(not handler._gpu_ci.is_valid(), "unbind frees the GPU canvas item")
	GdssNodeHandler.purge(id)
	GdssNodeHandler.purge(id)
	t.check(true, "purge is idempotent")
	RenderingServer.free_rid(ci)
	button.free()
	var freed: Button = t.make_styled_button()
	var freed_id: int = freed.get_instance_id()
	freed.free()
	await t.await_frames(2)
	t.check(not GdssNodeHandler._registry.has(freed_id), "freeing a styled node purges its registry slot")
	var orphans_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var objects_before: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	for cycle: int in 3:
		var batch: Array[Button] = []
		for i: int in 60:
			batch.append(t.make_styled_button("b%d" % i))
		await t.await_frames(1)
		for node: Button in batch:
			node.free()
		await t.await_frames(2)
	var orphans_after: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var objects_after: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	t.check_eq(orphans_after - orphans_before, 0, "bind/free cycles leave zero orphan nodes")
	t.check(objects_after - objects_before <= 20, "bind/free cycles do not leak objects (delta %d)" % (objects_after - objects_before))
