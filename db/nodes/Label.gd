@tool
class_name GdssNode_Label
extends GdssNode


func get_active_state(canvas_item: CanvasItem) -> String:
	var label: Label = canvas_item as Label
	if label.has_focus(): return "focus"
	return "normal"


func get_events() -> PackedStringArray:
	return ["focus_entered", "focus_exited","mouse_entered","mouse_exited"]
