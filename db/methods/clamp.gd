@tool
class_name GdssMethod_Clamp
extends GdssMethod

func _init() -> void:
	method_name = "clamp"
	supported_prop_types = [GDSS.Type.FLOAT, GDSS.Type.INT]
	returns_texture = false
	parameters = [
		Param.new("value", ParamType.FLOAT),
		Param.new("min", ParamType.FLOAT),
		Param.new("max", ParamType.FLOAT),
	]


func call_method(args: Array[Variant], node_id: int = -1, state_key: String = "") -> Variant:
	if args.size() < 3:
		return 0.0
	return clampf(float(args[0]), float(args[1]), float(args[2]))
