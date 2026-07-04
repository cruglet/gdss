extends RefCounted


const TC: GDScript = preload("res://tests/gdss_test_context.gd")

const FIXTURE: String = """
PopupPanel {
	bg_color: "#111111"
	corner_radius: 6 6 6 6
}
AcceptDialog {
	bg_color: "#222222"
}
ConfirmationDialog {
	bg_color: "#333333"
}
FileDialog {
	bg_color: "#444444"
}
"""


func run(t: TC) -> void:
	t.apply_fixture(FIXTURE)
	_check(t, PopupPanel.new(), "PopupPanel", Color("#111111"))
	_check(t, AcceptDialog.new(), "AcceptDialog", Color("#222222"))
	_check(t, ConfirmationDialog.new(), "ConfirmationDialog", Color("#333333"))
	_check(t, FileDialog.new(), "FileDialog", Color("#444444"))


func _check(t: TC, node: Window, type_name: String, bg: Color) -> void:
	t.add_styled(node)
	var handler: GdssPropHandler = GdssNodeHandler.get_primary_handler(node)
	t.check(handler != null, "%s binds" % type_name)
	t.check(node.has_theme_stylebox_override("panel"), "%s targets its panel stylebox" % type_name)
	t.check(node.get_theme_stylebox("panel") is GdssPropHandler, "%s panel override is the GDSS handler" % type_name)
	if handler != null:
		t.check_eq(handler._get_val("bg_color"), bg, "%s panel bg resolves" % type_name)
	node.free()
