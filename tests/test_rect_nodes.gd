extends RefCounted


const TC: GDScript = preload("res://tests/gdss_test_context.gd")

const FIXTURE: String = """
ColorRect {
	color: "#ff0000"
	modulate: "#80ff80"
	transform_enabled: true
	transform_rotation: 0.25
}
TextureRect {
	texture: texture("res://meta/icon.png")
	opacity: 0.5
}
"""


func run(t: TC) -> void:
	t.apply_fixture(FIXTURE)
	var rect: ColorRect = t.add_styled(ColorRect.new()) as ColorRect
	t.check(GdssNodeHandler.is_bound(rect), "ColorRect binds")
	t.check_eq(rect.color, Color("#ff0000"), "ColorRect color applied from stylesheet")
	t.check_eq(rect.modulate, Color("#80ff80"), "ColorRect modulate applied")
	t.check_eq(rect.offset_transform_rotation, 0.25, "ColorRect transform applied")
	var tex_rect: TextureRect = t.add_styled(TextureRect.new()) as TextureRect
	t.check(GdssNodeHandler.is_bound(tex_rect), "TextureRect binds")
	t.check(tex_rect.texture != null, "TextureRect texture loaded via texture()")
	t.check_eq(tex_rect.modulate.a, 0.5, "TextureRect opacity applied")
	GdssNodeHandler.unbind(rect)
	t.check_eq(rect.color, Color.WHITE, "ColorRect color resets on unbind")
	t.check_eq(rect.modulate, Color.WHITE, "ColorRect modulate resets on unbind")
	t.check_eq(rect.offset_transform_rotation, 0.0, "ColorRect transform resets on unbind")
	GdssNodeHandler.unbind(tex_rect)
	t.check(tex_rect.texture == null, "TextureRect texture resets on unbind")
	t.check_eq(tex_rect.modulate.a, 1.0, "TextureRect opacity resets on unbind")
	rect.free()
	tex_rect.free()
	t.restore_theme()
