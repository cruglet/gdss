@tool
class_name GdssNode_LineEdit
extends GdssNode


func get_active_state(canvas_item: CanvasItem) -> String:
	var line_edit: LineEdit = canvas_item as LineEdit
	if line_edit.has_focus(): return "focus"
	if not line_edit.editable: return "read_only"
	return "normal"


func get_events() -> PackedStringArray:
	return ["focus_entered", "focus_exited","mouse_entered","mouse_exited"]
