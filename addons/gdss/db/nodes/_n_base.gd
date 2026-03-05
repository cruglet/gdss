@tool
class_name GdssNode_Base
extends GdssNode


func get_active_state(canvas_item: CanvasItem) -> String:
	return ""


func get_events() -> PackedStringArray:
	return ["focus_entered", "focus_exited","mouse_entered","mouse_exited"]
