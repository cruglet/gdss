extends RefCounted


const TC: GDScript = preload("res://tests/gdss_test_context.gd")

const FIXTURE: String = """
Button {
	bg_color: "#202020"
	transition_time: 0.3
	:disabled {
		bg_color: "#505050"
	}
}
LineEdit {
	bg_color: "#202020"
}
"""


func _state(node: Control) -> String:
	return GdssNodeBinder.get_primary_stylebox(node).current_state


func run(t: TC) -> void:
	t.apply_fixture(FIXTURE)
	var button: Button = t.make_styled_button()
	await t.await_frames(1)
	t.check(button.is_connected(&"draw", GDSS._get_node_types().get("Button")._sync_state_on_draw), "a runtime button syncs its state on draw")
	t.check(button.get_signal_connection_list(&"mouse_entered").is_empty(), "a runtime button has no per-state signal hooks")
	button.disabled = true
	await t.await_frames(1)
	t.check_eq(_state(button), "disabled", "disabling syncs the state on the next draw")
	button.disabled = false
	button.toggle_mode = true
	button.button_pressed = true
	await t.await_frames(1)
	t.check_eq(_state(button), "pressed", "a code toggle syncs the state")
	var flat: Button = t.make_styled_button()
	flat.flat = true
	await t.await_frames(1)
	flat.disabled = true
	await t.await_frames(1)
	t.check_eq(_state(flat), "disabled", "a button made flat after binding still syncs its state")
	var fresh: Button = t.make_styled_button()
	var fresh_box: GdssStylebox = GdssNodeBinder.get_primary_stylebox(fresh)
	fresh.disabled = true
	GDSS.refresh(fresh)
	t.check_eq(fresh_box.current_state, "disabled", "a never-drawn button takes its state")
	t.check(fresh_box._tween == null, "a never-drawn button does not animate into its state")
	var line_edit: LineEdit = LineEdit.new()
	t.holder.add_child(line_edit)
	await t.await_frames(1)
	line_edit.editable = false
	await t.await_frames(1)
	t.check_eq(_state(line_edit), "read_only", "a line edit syncs read only on draw")
	line_edit.grab_focus()
	await t.await_frames(2)
	t.check_eq(_state(line_edit), "focus", "a line edit syncs focus on draw")
