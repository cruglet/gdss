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

const FIXTURE_SIDE_COLORS: String = """
Button {
	border: 2 2 2 2
	border_color: "#000000"
	border_color_top: "#ff0000"
	transition_time: 0.2
	:disabled {
		border_color_top: "#00ff00"
	}
}
"""

const FIXTURE_UNCHANGED: String = """
Button {
	bg_color: "#202020"
	font_color: "#ffffff"
	corner_radius: 4 4 4 4
	transition_time: 0.2
	:disabled {
		bg_color: "#ff0000"
	}
}
"""


func _enter_disabled(t: TC, button: Button) -> GdssStylebox:
	var stylebox: GdssStylebox = GdssNodeBinder.get_primary_stylebox(button)
	button.disabled = true
	GDSS.refresh(button)
	return stylebox


func run(t: TC) -> void:
	t.apply_fixture(FIXTURE)
	var button: Button = await t.make_drawn_button()
	var stylebox: GdssStylebox = _enter_disabled(t, button)
	t.check_eq(stylebox.current_state, "disabled", "refresh drives the real active state")
	t.check(stylebox._transition != null, "state change starts a tween")
	t.check(stylebox._transition.values.has("bg_color"), "tweened value tracked mid-flight")
	var unbound_state: WeakRef = weakref(stylebox._transition)
	GdssNodeBinder.unbind(button)
	t.check(stylebox._transition == null, "unbind kills the in-flight tween")
	t.check(unbound_state.get_ref() == null, "unbind frees the transition state")
	await t.await_seconds(0.35)
	t.check(not button.has_theme_stylebox_override("normal"), "no override resurrects after unbind")
	button.free()
	var natural: Button = await t.make_drawn_button()
	var natural_stylebox: GdssStylebox = _enter_disabled(t, natural)
	t.check(natural_stylebox._transition != null, "second tween starts")
	var natural_state: WeakRef = weakref(natural_stylebox._transition)
	await t.await_seconds(0.45)
	t.check(natural_stylebox._transition == null, "completed tween clears itself")
	t.check(natural_state.get_ref() == null, "a completed transition frees its state")
	t.check_eq(natural_stylebox._get_val("bg_color"), Color("#ff0000"), "completed tween settles on the target value")
	var reapplied: Button = await t.make_drawn_button()
	var reapplied_stylebox: GdssStylebox = _enter_disabled(t, reapplied)
	t.check(reapplied_stylebox._transition != null, "third tween starts")
	var reapplied_state: WeakRef = weakref(reapplied_stylebox._transition)
	reapplied_stylebox.reapply()
	t.check(reapplied_stylebox._transition == null, "reapply kills the in-flight tween")
	t.check(reapplied_state.get_ref() == null, "reapply frees the transition state")
	t.apply_fixture(FIXTURE_SIDE_COLORS)
	var sided: Button = await t.make_drawn_button()
	var sided_stylebox: GdssStylebox = _enter_disabled(t, sided)
	var mid: Variant = sided_stylebox._transition.values.get("border_color")
	t.check(mid is Array and (mid as Array).size() == 4, "per-side border color tweens as four sides")
	await t.await_seconds(0.45)
	t.check_eq(sided_stylebox._get_val("border_color"), [Color.BLACK, Color.BLACK, Color("#00ff00"), Color.BLACK], "per-side color tween settles on the target side")
	sided.free()
	t.apply_fixture(FIXTURE)
	var doomed: Button = await t.make_drawn_button()
	var doomed_stylebox: GdssStylebox = _enter_disabled(t, doomed)
	t.check(doomed_stylebox._transition != null, "fourth tween starts")
	var doomed_id: int = doomed.get_instance_id()
	doomed.free()
	await t.await_frames(2)
	t.check(not GdssNodeBinder._registry.has(doomed_id), "freeing mid-tween purges cleanly")
	await _check_only_changed_props_tween(t)


func _check_only_changed_props_tween(t: TC) -> void:
	t.apply_fixture(FIXTURE_UNCHANGED)
	var button: Button = await t.make_drawn_button()
	var stylebox: GdssStylebox = _enter_disabled(t, button)
	t.check(stylebox._transition.values.has("bg_color"), "a prop the state changes tweens")
	t.check(not stylebox._transition.values.has("font_color"), "a prop shared by both states does not tween")
	t.check(not stylebox._transition.values.has("corner_radius"), "a composite shared by both states does not tween")
	await t.await_seconds(0.35)
	t.check_eq(stylebox._get_val("bg_color"), Color("#ff0000"), "the changed prop still settles on its target")
	button.free()
