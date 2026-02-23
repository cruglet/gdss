@tool
class_name GdssInspectorPlugin
extends EditorInspectorPlugin


func _can_handle(object: Object) -> bool:
	if object is Control:
		return true
	return false


#func _parse_group(object: Object, group: String) -> void:
	#if object is Control and group == "Theme":
		#add_


func _parse_property(object: Object, type: Variant.Type, name: String, hint_type: PropertyHint, hint_string: String, usage_flags: int, wide: bool) -> bool:
	if object is Control and name.begins_with("theme"):
		return true
	return false
