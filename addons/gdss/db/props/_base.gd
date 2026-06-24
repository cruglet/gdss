@tool
class_name GdssProp
extends Resource

enum Category {
	STYLE,
	COLOR,
	CONST,
	FONT_SIZE,
	NODE_PROPERTY,
	ICON,
	FONT,
}

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
var category: Category = Category.STYLE
var composite_of: PackedStringArray = []:
	get():
		if type == GDSS.Type.COMPOSITE4 or type == GDSS.Type.COMPOSITE:
			return composite_of
		else:
			return []
var category_subproperties: PackedStringArray


static func create(
	p_name: String,
	p_type: GDSS.Type,
	p_default_value: Variant,
	p_category: Category,
	) -> GdssProp:
	
	var prop: GdssProp = GdssProp.new()
	prop.name = p_name
	prop.type = p_type
	prop.default_value = p_default_value
	prop.category = p_category
	
	return prop


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
		GDSS.Type.BOOLEAN: props.append({"name": "default_value", "type": TYPE_BOOL})
		GDSS.Type.COLOR: props.append({"name": "default_value", "type": TYPE_COLOR})
		GDSS.Type.COMPOSITE4: props.append({"name": "default_value", "type": TYPE_VECTOR4I})
		GDSS.Type.VECTOR2: props.append({"name": "default_value", "type": TYPE_VECTOR2})
		GDSS.Type.COMPOSITE: props.append({"name": "default_value", "type": TYPE_STRING})
		GDSS.Type.CURSOR: props.append({"name": "default_value", "type": TYPE_INT, "hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(GDSS.CursorType.keys())})
		GDSS.Type.TRANSITION_TYPE: props.append({"name": "default_value", "type": TYPE_INT, "hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(GDSS.TransitionType.keys())})
		GDSS.Type.TRANSITION_FUNC: props.append({"name": "default_value", "type": TYPE_INT, "hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(GDSS.TransitionFunc.keys())})
		GDSS.Type.ICON: props.append({"name": "default_value", "type": TYPE_OBJECT, "hint": PROPERTY_HINT_RESOURCE_TYPE, "hint_string": "Texture2D"})
	
	if type == GDSS.Type.COMPOSITE4 or type == GDSS.Type.COMPOSITE:
		props.append({"name": "composite_of", "type": TYPE_PACKED_STRING_ARRAY})
	
	props.append({
		"name": "category",
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": ",".join(Category.keys())
	})
	
	props.append({
		"name": "category_subproperties",
		"type": TYPE_PACKED_STRING_ARRAY,
		"hint": PROPERTY_HINT_ARRAY_TYPE,
	})
	
	return props


func get_name() -> String:
	return name


func get_type() -> GDSS.Type:
	return type


func get_default_value() -> Variant:
	if default_value != null:
		return default_value
	match type:
		GDSS.Type.INT, GDSS.Type.CURSOR, GDSS.Type.TRANSITION_TYPE, GDSS.Type.TRANSITION_FUNC:
			return 0
		GDSS.Type.FLOAT:
			return 0.0
		GDSS.Type.BOOLEAN:
			return false
		GDSS.Type.COLOR:
			return Color.TRANSPARENT
		GDSS.Type.COMPOSITE4:
			return Vector4i.ZERO
		GDSS.Type.VECTOR2:
			return Vector2.ZERO
		GDSS.Type.COMPOSITE:
			return ""
	return 0


func is_composite() -> bool:
	return composite_of.size() > 0


func get_info() -> Dictionary:
	var type_name: String = ""
	
	match type:
		GDSS.Type.INT: type_name = "INT"
		GDSS.Type.FLOAT: type_name = "FLOAT"
		GDSS.Type.BOOLEAN: type_name = "BOOLEAN"
		GDSS.Type.COLOR: type_name = "COLOR"
		GDSS.Type.COMPOSITE: type_name = "COMPOSITE"
		GDSS.Type.COMPOSITE4: type_name = "COMPOSITE4"
		GDSS.Type.VECTOR2: type_name = "VECTOR2"
		GDSS.Type.CURSOR: type_name = "CURSOR"
		GDSS.Type.TRANSITION_TYPE: type_name = "TRANSITION_TYPE"
		GDSS.Type.TRANSITION_FUNC: type_name = "TRANSITION_FUNC"
		GDSS.Type.ICON: type_name = "ICON"
		_:
			type_name = "UNKNOWN"
	
	var info: Dictionary = {
		"name": name,
		"type": "%d (%s)" % [type, type_name],
		"default_value": default_value,
		"composite_of": composite_of,
		"is_composite": is_composite()
	}
	
	return info
