extends RefCounted


const TC: GDScript = preload("res://tests/gdss_test_context.gd")

const FIXTURE: String = """
Panel {
	corner_radius: 8 8 8 8
	padding: 10 20 30 40
	Card {
		corner_radius_top_left: 30
		padding_top: 99
	}
	:hover {
		padding_left: 7
	}
}
Button {
	padding: 6 6 6 6
	transform_scale: 1.5 1.5
	%Compact {
		padding_left: 20
	}
	Lift {
		transform_scale_x: 2
	}
}
"""


const FIXTURE_SHORTHAND: String = """
@global var ring: 5
var pad: 3
@global var unit: 4
Panel {
	border: 1
	corner_radius: $ring
	padding: calc($unit * 2)
	shadow: $pad
	Tight {
		border: 2
		border_top: 9
	}
}
"""


func run(t: TC) -> void:
	_check_shorthand(t)
	t.apply_fixture(FIXTURE)
	var parsed: Dictionary = t.parse_fixture(FIXTURE)
	t.check_eq(t.entry_val(parsed, "Panel", "hover", "padding"), Vector4i(7, 20, 30, 40), "base-state per-side key patches onto the base all composite")
	var panel: Panel = Panel.new()
	t.add_styled(panel)
	GDSS.add_class(panel, "Card")
	var ph: GdssStylebox = GdssNodeBinder.get_primary_stylebox(panel)
	t.check_eq(ph._get_val("corner_radius"), Vector4i(30, 8, 8, 8), "class per-side key patches onto the base composite")
	t.check_eq(ph._get_val("padding"), Vector4i(10, 20, 99, 40), "class patch keeps every unset side of the base")
	panel.free()
	var pill: Button = Button.new()
	pill.theme_type_variation = "Compact"
	t.add_styled(pill)
	var pill_stylebox: GdssStylebox = GdssNodeBinder.get_primary_stylebox(pill)
	t.check_eq(pill_stylebox._get_val("padding"), Vector4i(20, 6, 6, 6), "variation per-side key patches onto the base composite")
	pill.free()
	var lifter: Button = Button.new()
	t.add_styled(lifter)
	GDSS.add_class(lifter, "Lift")
	var lift_stylebox: GdssStylebox = GdssNodeBinder.get_primary_stylebox(lifter)
	t.check_eq(lift_stylebox._get_val("transform_scale"), Vector2(2.0, 1.5), "vector2 class component patches onto the base vector")
	lifter.free()


func _check_shorthand(t: TC) -> void:
	var parsed: Dictionary = t.parse_fixture(FIXTURE_SHORTHAND)
	t.check_eq(t.entry_val(parsed, "Panel", "all", "border"), Vector4i(1, 1, 1, 1), "a single literal splats to four sides at parse time")
	t.apply_fixture(FIXTURE_SHORTHAND)
	var panel: Panel = t.add_styled(Panel.new()) as Panel
	var stylebox: GdssStylebox = GdssNodeBinder.get_primary_stylebox(panel)
	t.check_eq(stylebox._get_val("border"), Vector4i(1, 1, 1, 1), "the splat survives to the styled node")
	t.check_eq(stylebox._get_val("corner_radius"), Vector4i(5, 5, 5, 5), "a global variable splats when it resolves")
	t.check_eq(stylebox._get_val("shadow"), Vector4i(3, 3, 3, 3), "a local variable splats too")
	t.check_eq(stylebox._get_val("padding"), Vector4i(8, 8, 8, 8), "calc() splats across the four sides")
	t.check_eq(stylebox.get_content_margin(SIDE_TOP), 8.0, "the splatted padding reaches the content margins")
	GDSS.set_global_var("ring", 11)
	t.check_eq(stylebox._get_val("corner_radius"), Vector4i(11, 11, 11, 11), "changing the global re-splats")
	GDSS.reset_global_vars()
	var tight: Panel = t.add_styled(Panel.new()) as Panel
	GDSS.add_class(tight, "Tight")
	var tight_box: GdssStylebox = GdssNodeBinder.get_primary_stylebox(tight)
	t.check_eq(tight_box._get_val("border"), Vector4i(2, 2, 9, 2), "a per-side key still patches onto a splatted shorthand (sides are left, right, top, bottom)")
	var clean: Array[Array] = t.validate_fixture(FIXTURE_SHORTHAND)
	t.check(clean.is_empty(), "shorthands validate clean (got: %s)" % ", ".join(t.error_messages(clean)))
	var errors: Array[Array] = t.validate_fixture("Panel {\n\tborder: 1 2\n\tcorner_radius: 1 2 3\n}")
	t.check(t.has_error_containing(errors, "'border' expects 1 or 4 integer values, got 2"), "two values are still rejected")
	t.check(t.has_error_containing(errors, "'corner_radius' expects 1 or 4 integer values, got 3"), "three values are still rejected")
	GdssNodeBinder.unbind(panel)
	GdssNodeBinder.unbind(tight)
	panel.free()
	tight.free()
