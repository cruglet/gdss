@tool
class_name GdssNodeType_Window
extends GdssNodeType


func get_active_state(canvas_item: CanvasItem) -> String:
	return "embedded_border"


# Only the embedded window border is GDSS-drawn; native OS windows don't render it.
func get_only_states() -> PackedStringArray:
	return ["embedded_border"]


func get_events() -> PackedStringArray:
	return []


func get_default_events() -> PackedStringArray:
	return ["visibility_changed"]
