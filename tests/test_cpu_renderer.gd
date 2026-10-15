extends RefCounted


const TC: GDScript = preload("res://tests/gdss_test_context.gd")


func run(t: TC) -> void:
	GdssCpuRenderer._rr_cache.clear()
	var radii: Vector4 = Vector4(4, 4, 4, 4)
	var here: PackedVector2Array = GdssCpuRenderer._get_rounded_rect(Rect2(0, 0, 50, 20), radii, 4)
	var there: PackedVector2Array = GdssCpuRenderer._get_rounded_rect(Rect2(300, 100, 50, 20), radii, 4)
	t.check_eq(GdssCpuRenderer._rr_cache.size(), 1, "moving a panel reuses its cached shape")
	t.check(there.get(0).is_equal_approx(here.get(0) + Vector2(300, 100)), "the cached shape is placed at the panel's position")
	var rect: Rect2 = Rect2(10, 10, 60, 30)
	var first: PackedVector2Array = GdssCpuRenderer._apply_skew(GdssCpuRenderer._get_rounded_rect(rect, radii, 4), rect, 0.3, 0.0)
	var second: PackedVector2Array = GdssCpuRenderer._apply_skew(GdssCpuRenderer._get_rounded_rect(rect, radii, 4), rect, 0.3, 0.0)
	t.check_eq(first, second, "skewing the same panel twice yields the same geometry")
	var square: PackedVector2Array = GdssCpuRenderer._apply_skew(GdssCpuRenderer._get_rounded_rect(rect, Vector4.ZERO, 4), rect, 0.3, 0.2)
	t.check(square.get(0).is_equal_approx(Vector2(5.5, 4.0)), "skew leans each point around the panel center")
	t.check(GdssCpuRenderer._get_rounded_rect(rect, Vector4.ZERO, 4).get(0).is_equal_approx(rect.position), "skewing never alters the cached shape")
