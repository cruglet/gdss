extends RefCounted


const TC: GDScript = preload("res://tests/gdss_test_context.gd")

const FIXTURE: String = """
Button {
	bg_color: "#000000"
}
PanelContainer {
	> Button {
		bg_color: "#00ff00"
	}
}
"""


func run(t: TC) -> void:
	t.apply_fixture(FIXTURE)
	t.check(GdssStylesheet.has_descendant_rules, "a combinator marks the sheet as position dependent")
	var panel: PanelContainer = t.add_styled(PanelContainer.new()) as PanelContainer
	var outside: Control = t.add_styled(Control.new()) as Control
	var button: Button = Button.new()
	panel.add_child(button)
	var stylebox: GdssStylebox = GdssNodeBinder.get_primary_stylebox(button)
	t.check_eq(stylebox._get_val("bg_color"), Color("#00ff00"), "a direct child takes the combinator rule")
	button.reparent(outside)
	t.check_eq(GdssNodeBinder.get_primary_stylebox(button)._get_val("bg_color"), Color("#000000"), "moving out of the parent drops the combinator rule")
	button.reparent(panel)
	t.check_eq(GdssNodeBinder.get_primary_stylebox(button)._get_val("bg_color"), Color("#00ff00"), "moving back in restores it")
