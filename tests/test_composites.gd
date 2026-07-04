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


func run(t: TC) -> void:
	t.apply_fixture(FIXTURE)
	var parsed: Dictionary = t.parse_fixture(FIXTURE)
	t.check_eq(t.entry_val(parsed, "Panel", "hover", "padding"), Vector4i(7, 20, 30, 40), "base-state per-side key patches onto the base all composite")
	var panel: Panel = Panel.new()
	t.add_styled(panel)
	GDSS.add_class(panel, "Card")
	var ph: GdssPropHandler = GdssNodeHandler.get_primary_handler(panel)
	t.check_eq(ph._get_val("corner_radius"), Vector4i(30, 8, 8, 8), "class per-side key patches onto the base composite")
	t.check_eq(ph._get_val("padding"), Vector4i(10, 20, 99, 40), "class patch keeps every unset side of the base")
	panel.free()
	var pill: Button = Button.new()
	pill.theme_type_variation = "Compact"
	t.add_styled(pill)
	var pill_handler: GdssPropHandler = GdssNodeHandler.get_primary_handler(pill)
	t.check_eq(pill_handler._get_val("padding"), Vector4i(20, 6, 6, 6), "variation per-side key patches onto the base composite")
	pill.free()
	var lifter: Button = Button.new()
	t.add_styled(lifter)
	GDSS.add_class(lifter, "Lift")
	var lift_handler: GdssPropHandler = GdssNodeHandler.get_primary_handler(lifter)
	t.check_eq(lift_handler._get_val("transform_scale"), Vector2(2.0, 1.5), "vector2 class component patches onto the base vector")
	lifter.free()
