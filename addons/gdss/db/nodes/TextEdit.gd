@tool
class_name GdssNode_TextEdit
extends GdssNode


func get_active_state(canvas_item: CanvasItem) -> String:
	var text_edit: TextEdit = canvas_item as TextEdit
	if text_edit.has_focus(): return "focus"
	if not text_edit.editable: return "read_only"
	return "normal"


func get_events() -> PackedStringArray:
	return ["focus_entered", "focus_exited","mouse_entered","mouse_exited"]
