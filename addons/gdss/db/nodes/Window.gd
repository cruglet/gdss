@tool
class_name GdssNode_Window
extends GdssNode


func get_active_state(canvas_item: CanvasItem) -> String:
	return "embedded_border"


# Only the embedded window border is GDSS-drawn (and only when the window is
# embedded; native OS windows simply don't render it, so this no-ops gracefully).
func get_only_states() -> PackedStringArray:
	return ["embedded_border"]


func get_events() -> PackedStringArray:
	return []


func get_default_events() -> PackedStringArray:
	return ["visibility_changed"]
