@tool
class_name GdssNodeType_Panel
extends GdssNodeType


func get_events() -> PackedStringArray:
	return []


func get_active_state(canvas_item: CanvasItem) -> String:
	return "panel"
