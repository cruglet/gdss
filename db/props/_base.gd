@tool
class_name GdssProp
extends Resource

var name: String = "":
	set(n):
		name = n.strip_edges().replace(" ", "_")
var type: GDSS.Type = GDSS.Type.INT:
	set(t):
		type = t
		if t == GDSS.Type.COMPOSITE:
			default_value = ""
		if t == GDSS.Type.COMPOSITE4 and name:
			default_value = Vector4i.ZERO
			composite_of = ("%s_left;%s_right;%s_top;%s_bottom" % [name, name, name, name]).split(";")
		notify_property_list_changed()
var default_value: Variant
var composite_of: PackedStringArray = []:
	get():
		if type == GDSS.Type.COMPOSITE4 or type == GDSS.Type.COMPOSITE:
			return composite_of
		else:
			return []


func _get_property_list() -> Array[Dictionary]:
	var props: Array[Dictionary]
	props.append({
		"name": "name",
		"type": TYPE_STRING,
	})
	props.append({
		"name": "type",
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": ",".join(GDSS.Type.keys())
	})
	
	
	match type:
		GDSS.Type.INT: props.append({"name": "default_value", "type": TYPE_INT})
		GDSS.Type.FLOAT: props.append({"name": "default_value", "type": TYPE_FLOAT})
		GDSS.Type.COLOR: props.append({"name": "default_value", "type": TYPE_COLOR})
		GDSS.Type.COMPOSITE4: props.append({"name": "default_value", "type": TYPE_VECTOR4I})
		GDSS.Type.COMPOSITE: props.append({"name": "default_value", "type": TYPE_STRING})
		GDSS.Type.CURSOR: props.append({"name": "default_value", "type": TYPE_INT, "hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(GDSS.CursorType.keys())})
		GDSS.Type.TRANS: props.append({"name": "default_value", "type": TYPE_INT, "hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(GDSS.TransitionType.keys())})
	
	if type == GDSS.Type.COMPOSITE4 or type == GDSS.Type.COMPOSITE:
		props.append({"name": "composite_of", "type": TYPE_PACKED_STRING_ARRAY})
	
	return props


func get_name() -> String:
	return name


func get_type() -> GDSS.Type:
	return type


func get_default_value() -> Variant:
	return 0


func is_composite() -> bool:
	return composite_of.size() > 0
