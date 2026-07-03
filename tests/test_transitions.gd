extends RefCounted


const TC: GDScript = preload("res://tests/gdss_test_context.gd")

const FIXTURE: String = """
Button {
	bg_color: "#202020"
	transition_time: 0.2
	transition_func: QUAD
	transition_type: EASE_OUT
	:disabled {
		bg_color: "#ff0000"
	}
}
"""


func _enter_disabled(t: TC, button: Button) -> GdssPropHandler:
	var handler: GdssPropHandler = GdssNodeHandler.get_primary_handler(button)
	button.disabled = true
	GDSS.refresh(button)
	return handler


func run(t: TC) -> void:
	t.apply_fixture(FIXTURE)
	var button: Button = t.make_styled_button()
	var handler: GdssPropHandler = _enter_disabled(t, button)
	t.check_eq(handler.current_state, "disabled", "refresh drives the real active state")
	t.check(handler._tween != null, "state change starts a tween")
	t.check(handler._tweened_values.has("bg_color"), "tweened value tracked mid-flight")
	GdssNodeHandler.unbind(button)
	t.check(handler._tween == null, "unbind kills the in-flight tween")
	t.check(handler._tweened_values.is_empty(), "unbind clears tweened values")
	await t.await_seconds(0.35)
	t.check(not button.has_theme_stylebox_override("normal"), "no override resurrects after unbind")
	button.free()
	var natural: Button = t.make_styled_button()
	var natural_handler: GdssPropHandler = _enter_disabled(t, natural)
	t.check(natural_handler._tween != null, "second tween starts")
	await t.await_seconds(0.45)
	t.check(natural_handler._tween == null, "completed tween clears itself")
	t.check_eq(natural_handler._get_val("bg_color"), Color("#ff0000"), "completed tween settles on the target value")
	var reapplied: Button = t.make_styled_button()
	var reapplied_handler: GdssPropHandler = _enter_disabled(t, reapplied)
	t.check(reapplied_handler._tween != null, "third tween starts")
	reapplied_handler.reapply()
	t.check(reapplied_handler._tween == null, "reapply kills the in-flight tween")
	t.check(reapplied_handler._tweened_values.is_empty(), "reapply clears tweened values")
	var doomed: Button = t.make_styled_button()
	var doomed_handler: GdssPropHandler = _enter_disabled(t, doomed)
	t.check(doomed_handler._tween != null, "fourth tween starts")
	var doomed_id: int = doomed.get_instance_id()
	doomed.free()
	await t.await_frames(2)
	t.check(not GdssNodeHandler._registry.has(doomed_id), "freeing mid-tween purges cleanly")
