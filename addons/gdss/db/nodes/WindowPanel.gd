@tool
class_name GdssNode_WindowPanel
extends GdssNode


func get_active_state(canvas_item: CanvasItem) -> String:
	return "panel"


func get_only_states() -> PackedStringArray:
	return ["panel"]


func get_events() -> PackedStringArray:
	return []


func get_default_events() -> PackedStringArray:
	return ["visibility_changed"]
