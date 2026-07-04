extends RefCounted


const TC: GDScript = preload("res://tests/gdss_test_context.gd")

const FIXTURE: String = """
TabBar {
	font_color: "#ffffff"
	font_unselected_color: "#888888"
	icon_disabled_color: "#ff0000"
}
Button {
	font_color: "#101010"
	font_hover_color: "#00ff00"
}
"""


func run(t: TC) -> void:
	t.apply_fixture(FIXTURE)
	var bar: TabBar = TabBar.new()
	t.add_styled(bar)
	t.check_eq(bar.get_theme_color("font_selected_color"), Color("#ffffff"), "catch-all font_color sets the selected variant")
	t.check_eq(bar.get_theme_color("font_hovered_color"), Color("#ffffff"), "catch-all font_color sets the hovered variant")
	t.check_eq(bar.get_theme_color("font_unselected_color"), Color("#888888"), "font_unselected_color refines just the unselected variant")
	t.check_eq(bar.get_theme_color("icon_disabled_color"), Color("#ff0000"), "an individual icon sub-color applies on its own")
	t.check(bar.has_theme_color_override("font_unselected_color"), "the refined sub-color is a real override")
	bar.free()
	var button: Button = Button.new()
	t.add_styled(button)
	t.check_eq(button.get_theme_color("font_color"), Color("#101010"), "stateful base font_color still applies")
	t.check_eq(button.get_theme_color("font_hover_color"), Color("#00ff00"), "individual sub-color beats the catch-all regardless of theme color order")
	button.free()
