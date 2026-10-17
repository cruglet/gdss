@tool
class_name GdssNodeType_Button
extends GdssNodeType


func get_active_state(canvas_item: CanvasItem) -> String:
	var button: Button = canvas_item as Button
	if button.disabled: return "disabled"
	var pressed: bool = button.button_pressed
	var hovered: bool = button.is_hovered()
	if pressed and button.toggle_mode:
		if hovered and _defines_state(canvas_item, "hover_pressed"): return "hover_pressed"
		if button.has_focus(true) and _defines_state(canvas_item, "focus_pressed"): return "focus_pressed"
	if pressed: return "pressed"
	if hovered: return "hover"
	if button.has_focus(true): return "focus"
	return "normal"


func get_extra_states() -> PackedStringArray:
	return ["hover_pressed", "focus_pressed"]


func get_events() -> PackedStringArray:
	return ["mouse_entered", "mouse_exited", "button_down", "button_up",
	"toggled", "focus_entered", "focus_exited"]


func _defines_state(canvas_item: CanvasItem, state: String) -> bool:
	var stylebox: GdssStylebox = GdssNodeBinder.get_primary_stylebox(canvas_item)
	return stylebox != null and stylebox._resolve_entry().has(state)
