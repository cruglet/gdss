@tool
class_name GdssNode_PopupMenu
extends GdssNode


func get_active_state(canvas_item: CanvasItem) -> String:
	return "panel"


# Only the panel background is GDSS-drawn; hover/separator stay theme-driven.
func get_only_states() -> PackedStringArray:
	return ["panel"]


func get_events() -> PackedStringArray:
	return ["about_to_popup", "popup_hide"]


func get_default_events() -> PackedStringArray:
	return ["visibility_changed"]
