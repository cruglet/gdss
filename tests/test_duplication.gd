extends RefCounted


const TC: GDScript = preload("res://tests/gdss_test_context.gd")

const FIXTURE: String = """
Button {
	bg_color: "#334455"
	corner_radius: 10 10 10 10
	Ghost {
		bg_color: "#00ff00"
	}
}
Label {
	font_color: "#ffcc00"
}
"""


func run(t: TC) -> void:
	t.apply_fixture(FIXTURE)
	var original: Button = t.make_styled_button()
	var original_handler: GdssPropHandler = GdssNodeHandler.get_primary_handler(original)
	GDSS.add_class(original, "Ghost")
	var clone: Button = original.duplicate() as Button
	t.add_styled(clone)
	var clone_handler: GdssPropHandler = GdssNodeHandler.get_primary_handler(clone)
	t.check(clone_handler != null, "clone binds on enter")
	t.check(clone_handler != original_handler, "clone gets its own handler")
	t.check(original_handler.ref == original, "original keeps its handler binding")
	t.check(clone_handler.ref == clone, "clone handler binds the clone")
	t.check(original.get_theme_stylebox("normal") == original_handler, "original override intact")
	t.check(clone.get_theme_stylebox("normal") == clone_handler, "clone override replaced with own handler")
	t.check_eq(clone_handler._get_val("bg_color"), Color("#00ff00"), "duplicated gdss_classes meta styles the clone")
	var ci_a: RID = RenderingServer.canvas_item_create()
	var ci_b: RID = RenderingServer.canvas_item_create()
	original_handler.draw(ci_a, Rect2(0, 0, 100, 30))
	clone_handler.draw(ci_b, Rect2(0, 0, 100, 30))
	var clone_id: int = clone.get_instance_id()
	clone.free()
	await t.await_frames(2)
	t.check(not GdssNodeHandler._registry.has(clone_id), "freed clone purged")
	if GDSS.gpu_panels_enabled():
		t.check(original_handler._gpu_ci.is_valid(), "purging the clone leaves the original GPU item alive")
	RenderingServer.free_rid(ci_a)
	RenderingServer.free_rid(ci_b)
	original.free()
	var label: Label = Label.new()
	label.text = "static"
	t.add_styled(label)
	var label_clone: Label = label.duplicate() as Label
	t.add_styled(label_clone)
	var label_slots: Dictionary = GdssNodeHandler.get_slots(label)
	var clone_slots: Dictionary = GdssNodeHandler.get_slots(label_clone)
	t.check(not clone_slots.is_empty(), "static clone binds")
	var shared: bool = false
	for state: String in clone_slots:
		if label_slots.get(state) == clone_slots.get(state):
			shared = true
	t.check(not shared, "static clone shares no handler slot with its source")
