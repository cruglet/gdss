extends RefCounted


const TC: GDScript = preload("res://tests/gdss_test_context.gd")

const FIXTURE: String = """
Label {
	font_size: 21
}
"""


func run(t: TC) -> void:
	t.apply_fixture(FIXTURE)
	_check_strip(t)
	_check_unbind(t)


func _check_strip(t: TC) -> void:
	var host: Control = Control.new()
	t.add_styled(host)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 23)
	host.add_child(box)
	var label: Label = Label.new()
	label.add_theme_color_override(&"font_color", Color.RED)
	box.add_child(label)
	t.check(GdssNodeBinder.is_bound(label), "the label binds")
	t.check_eq(label.get_theme_font_size(&"font_size"), 21, "the stylesheet font size is applied")
	GdssNodeBinder.strip_overrides()
	t.check(box.has_theme_constant_override(&"separation"), "a container constant GDSS never set survives a strip")
	t.check_eq(box.get_theme_constant(&"separation"), 23, "the container constant keeps its value")
	t.check(label.has_theme_color_override(&"font_color"), "an unstyled author color survives a strip")
	t.check_eq(label.get_theme_color(&"font_color"), Color.RED, "the author color keeps its value")
	GdssNodeBinder.reapply_overrides()
	t.check_eq(label.get_theme_font_size(&"font_size"), 21, "reapply restores the stylesheet font size")
	t.check_eq(box.get_theme_constant(&"separation"), 23, "reapply leaves the author constant alone")
	host.free()


func _check_unbind(t: TC) -> void:
	var host: Control = Control.new()
	t.add_styled(host)
	var label: Label = Label.new()
	label.add_theme_color_override(&"font_color", Color.RED)
	host.add_child(label)
	t.check(GdssNodeBinder.is_bound(label), "the label binds before unbinding")
	GdssNodeBinder.unbind(label)
	t.check(not GdssNodeBinder.is_bound(label), "the label unbinds")
	t.check(not label.has_theme_font_size_override(&"font_size"), "unbinding drops the font size GDSS applied")
	t.check(label.has_theme_color_override(&"font_color"), "unbinding keeps the author color")
	t.check_eq(label.get_theme_color(&"font_color"), Color.RED, "the author color is untouched by unbind")
	host.free()
