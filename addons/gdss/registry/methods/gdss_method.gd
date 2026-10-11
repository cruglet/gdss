class_name GdssMethod
extends Resource

enum ParamType {
	INT,
	FLOAT,
	COLOR,
	STRING,
	BOOL,
	ENUM,
}


class Param:
	var name: String
	var type: ParamType
	var optional: bool
	var default_value: Variant
	var enum_keys: PackedStringArray
	
	func _init(p_name: String, p_type: ParamType, p_optional: bool = false, p_default: Variant = null, p_enum_keys: PackedStringArray = PackedStringArray()) -> void:
		name = p_name
		type = p_type
		optional = p_optional
		default_value = p_default
		enum_keys = p_enum_keys

@export var method_name: String = ""
@export var supported_prop_types: Array[GDSS.Type] = []
@export var returns_texture: bool = false
@export var variadic: bool = false

var parameters: Array[Param] = []


func get_code_hint(active_param: int = -1) -> String:
	var parts: PackedStringArray = []
	for i: int in parameters.size():
		var param: Param = parameters.get(i)
		var type_str: String = ParamType.find_key(param.type).to_lower()
		if param.type == ParamType.ENUM and not param.enum_keys.is_empty():
			type_str = "|".join(param.enum_keys)
		if active_param == i:
			var part: String = param.name + ": " + type_str
			if param.optional and str(param.default_value) != "":
				part += " = " + str(param.default_value)
			parts.append("[" + part + "]")
		else:
			parts.append(param.name)
	if variadic:
		parts.append("...")
	return method_name + "(" + ", ".join(parts) + ")"


func call_method(args: Array[Variant], node_id: int = -1, state_key: String = "") -> Variant:
	return null


func _resolve_arg(raw: String) -> Variant:
	if raw.begins_with("\"") or raw.begins_with("'"):
		var stripped: String = raw.trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'")
		if stripped.begins_with("#") and Color.html_is_valid(stripped):
			return Color.html(stripped)
		return stripped
	if raw.begins_with("#") and Color.html_is_valid(raw):
		return Color.html(raw)
	if raw.is_valid_int():
		return int(raw)
	if raw.is_valid_float():
		return float(raw)
	return raw


func get_tweenable_args() -> Array[int]:
	return []


func get_live_texture(node_id: int, state_key: String) -> Texture2D:
	return null


func interpolate_args(from_args: Array[Variant], to_args: Array[Variant], t: float) -> Array[Variant]:
	return to_args


func clear_live_textures() -> void:
	pass


func purge_node(node_id: int) -> void:
	pass
