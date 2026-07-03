extends RefCounted


const TC: GDScript = preload("res://tests/gdss_test_context.gd")

const FIXTURE_CLEAN: String = """
@global var accent: "#3b82f6"
Button {
	bg_color: $accent
	corner_radius: 8 8 8 8
	transition_time: 0.15
	transition_type: ease_out
	:hover {
		bg_color: lighten($accent, 0.1)
	}
}
"""

const FIXTURE_BROKEN: String = """
Bogus {
	bg_color: RED
}
Button {
	nope: 1
	padding: 1 2 3
	bg_color: $missing
	border: what what what what
"""

const FIXTURE_METHODS: String = """
Button {
	bg_color: unknown_method(1)
	border_color: rgba(1)
	font_size: calc(1 +)
}
"""

const FIXTURE_CLASS_BLOCKS: String = """
Button {
	bg_color: BLACK
	Ghost {
		bogus_prop: 1
		corner_radius_top_left: 8
		:hover {
			another_bogus: 2
		}
	}
	%Flat {
		flat_bogus: 3
	}
}
PanelContainer {
	AnimCard {
		on_show() {
			transform_scale: 0.6 0.6
			transition_time: 0.3
			transition_func: BACK
		}
	}
}
"""


func run(t: TC) -> void:
	var clean: Array[Array] = t.validate_fixture(FIXTURE_CLEAN)
	t.check(clean.is_empty(), "clean fixture has zero errors (got: %s)" % ", ".join(t.error_messages(clean)))
	var broken: Array[Array] = t.validate_fixture(FIXTURE_BROKEN)
	t.check(t.has_error_containing(broken, "Unknown selector 'Bogus'"), "unknown selector flagged")
	t.check(t.has_error_containing(broken, "Unknown property 'nope'"), "unknown property flagged")
	t.check(t.has_error_containing(broken, "expects 4 integer values"), "composite arity flagged")
	t.check(t.has_error_containing(broken, "Undefined variable '$missing'"), "undefined variable flagged")
	t.check(t.has_error_containing(broken, "integer components"), "non-integer composite component flagged")
	t.check(t.has_error_containing(broken, "Unclosed brace"), "unclosed brace flagged")
	var methods: Array[Array] = t.validate_fixture(FIXTURE_METHODS)
	t.check(t.has_error_containing(methods, "Unknown method 'unknown_method()'"), "unknown method flagged")
	t.check(t.has_error_containing(methods, "argument"), "method arg count flagged")
	t.check(t.has_error_containing(methods, "incomplete"), "incomplete calc flagged")
	var class_blocks: Array[Array] = t.validate_fixture(FIXTURE_CLASS_BLOCKS)
	t.check(t.has_error_containing(class_blocks, "Unknown property 'bogus_prop' for selector 'Ghost'"), "class-block property validated against node type")
	t.check(t.has_error_containing(class_blocks, "Unknown property 'another_bogus'"), "state inside class block validated")
	t.check(t.has_error_containing(class_blocks, "Unknown property 'flat_bogus'"), "variation-block property validated")
	t.check(not t.has_error_containing(class_blocks, "corner_radius_top_left"), "per-side key accepted in class block")
	t.check(not t.has_error_containing(class_blocks, "transition_time"), "transition props accepted in event blocks")
	t.check(not t.has_error_containing(class_blocks, "transform_scale"), "node props accepted in event blocks")
