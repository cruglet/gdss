@tool
class_name GdssNode_ItemList
extends GdssNode


func get_active_state(canvas_item: CanvasItem) -> String:
	return ""


func get_events() -> PackedStringArray:
	return ["focus_entered", "focus_exited","mouse_entered","mouse_exited",
	"empty_clicked", "item_activated", "item_clicked", "item_selected", "multi_selected"
	]
