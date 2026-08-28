@tool
class_name GdssMethod_Rgba
extends GdssMethod

func _init() -> void:
	method_name = "rgba"
	supported_prop_types = [GDSS.Type.COLOR]
	returns_texture = false
	parameters = [
		Param.new("r", ParamType.FLOAT),
		Param.new("g", ParamType.FLOAT),
		Param.new("b", ParamType.FLOAT),
		Param.new("a", ParamType.FLOAT, true, 1.0),
	]


func call_method(args: Array[Variant], node_id: int = -1, state_key: String = "") -> Variant:
	if args.size() < 3:
		return Color.WHITE
	return Color(
		float(args[0]),
		float(args[1]),
		float(args[2]),
		float(args[3]) if args.size() > 3 else 1.0
	)
