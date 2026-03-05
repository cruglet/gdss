@tool
class_name GdssMethod_Mix
extends GdssMethod

func _init() -> void:
	method_name = "mix"
	supported_prop_types = [GDSS.Type.COLOR, GDSS.Type.FLOAT]
	returns_texture = false
	parameters = [
		Param.new("a", ParamType.COLOR),
		Param.new("b", ParamType.COLOR),
		Param.new("t", ParamType.FLOAT),
	]


func call_method(args: Array[Variant], node_id: int = -1, state_key: String = "") -> Variant:
	if args.size() < 3:
		return Color.WHITE
	var a: Color = args[0] if args[0] is Color else Color.WHITE
	var b: Color = args[1] if args[1] is Color else Color.WHITE
	return a.lerp(b, float(args[2]))
