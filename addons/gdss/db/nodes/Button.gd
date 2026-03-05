@tool
class_name GdssNode_Button
extends GdssNode


func get_active_state(canvas_item: CanvasItem) -> String:
	var button: Button = canvas_item as Button
	if button.disabled: return "disabled"
	if button.is_hovered() and button.button_pressed and button.toggle_mode: return "hover_pressed"
	if button.button_pressed: return "pressed"
	if button.is_hovered(): return "hover"
	if button.has_focus(true): return "focus"
	return "normal"


func get_events() -> PackedStringArray:
	return ["mouse_entered", "mouse_exited", "button_down", "button_up",
	"toggled", "focus_entered", "focus_exited"]
