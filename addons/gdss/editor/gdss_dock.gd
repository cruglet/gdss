class_name GdssDock
extends EditorDock


func _init() -> void:
	title = "GDSS"
	default_slot = EditorDock.DOCK_SLOT_BOTTOM
	available_layouts = EditorDock.DOCK_LAYOUT_ALL


func set_editor(editor: GdssEditor) -> void:
	add_child(editor)
