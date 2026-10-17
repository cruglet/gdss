extends RefCounted


const TC: GDScript = preload("res://tests/gdss_test_context.gd")

const FIXTURE: String = """
Button {
	bg_color: "#202020"
	transition_time: 0.2
	Popping {
		on_show() {
			opacity: 0.0
		}
		on_hide() {
			opacity: 0.0
		}
		pressed() {
			bg_color: "#ff0000"
		}
	}
}
"""


func _gdss_listens(node: Node, sig: StringName) -> bool:
	for connection: Dictionary in node.get_signal_connection_list(sig):
		var target: Object = (connection.get("callable") as Callable).get_object()
		if target is GdssStylebox or target == GDSS._runtime:
			return true
	return false


func run(t: TC) -> void:
	t.apply_fixture(FIXTURE)
	var button: Button = await t.make_drawn_button()
	t.check(not _gdss_listens(button, &"visibility_changed"), "a node without show or hide rules has no visibility hook")
	GDSS.add_class(button, "Popping")
	t.check(_gdss_listens(button, &"visibility_changed"), "adding a class with show or hide rules hooks visibility")
	t.check(_gdss_listens(button, &"pressed"), "adding a class with a signal event hooks that signal")
	button.visible = false
	t.check(button.visible, "on_hide keeps the node visible while it animates out")
	await t.await_seconds(0.35)
	t.check(not button.visible, "the node hides once on_hide finishes")
	button.visible = true
	t.check(GdssNodeBinder.get_primary_stylebox(button)._transition != null, "showing plays on_show")
	await t.await_seconds(0.35)
	GDSS.remove_class(button, "Popping")
	t.check(not _gdss_listens(button, &"visibility_changed"), "removing the class drops the visibility hook")
	t.check(not _gdss_listens(button, &"pressed"), "removing the class drops the signal event hook")
	button.visible = false
	t.check(not button.visible, "without on_hide a node hides immediately")
	button.visible = true
	GDSS.add_class(button, "Popping")
	GdssNodeBinder.unbind(button)
	t.check(not _gdss_listens(button, &"visibility_changed"), "unbinding drops the visibility hook")
	t.check(not _gdss_listens(button, &"pressed"), "unbinding drops signal event hooks")
