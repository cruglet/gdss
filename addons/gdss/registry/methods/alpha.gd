@tool
class_name GdssMethod_Alpha
extends GdssMethod


func _init() -> void:
	method_name = "alpha"
	supported_prop_types = [GDSS.Type.COLOR]
	returns_texture = false
	parameters = [
		Param.new("color", ParamType.COLOR),
		Param.new("alpha", ParamType.FLOAT),
	]


func call_method(args: Array[Variant], node_id: int = -1, state_key: String = "") -> Variant:
	if args.size() < 2:
		return Color.WHITE
	var color: Color = args[0] if args[0] is Color else Color.WHITE
	return Color(color.r, color.g, color.b, float(args[1]))
