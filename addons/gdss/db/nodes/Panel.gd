@tool
class_name GdssNode_Panel
extends GdssNode


func get_events() -> PackedStringArray:
	return []


func get_active_state(canvas_item: CanvasItem) -> String:
	return "panel"
