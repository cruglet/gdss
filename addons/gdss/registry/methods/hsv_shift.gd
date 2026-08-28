@tool
class_name GdssMethod_HsvShift
extends GdssMethod


func _init() -> void:
	method_name = "hsv_shift"
	supported_prop_types = [GDSS.Type.COLOR]
	returns_texture = false
	parameters = [
		Param.new("color", ParamType.COLOR),
		Param.new("h", ParamType.FLOAT, true, 0.0),
		Param.new("s", ParamType.FLOAT, true, 0.0),
		Param.new("v", ParamType.FLOAT, true, 0.0),
	]


func call_method(args: Array[Variant], node_id: int = -1, state_key: String = "") -> Variant:
	if args.is_empty():
		return Color.WHITE
	var color: Color = args[0] if args[0] is Color else Color.WHITE
	var h: float = float(args[1]) if args.size() > 1 else 0.0
	var s: float = float(args[2]) if args.size() > 2 else 0.0
	var v: float = float(args[3]) if args.size() > 3 else 0.0
	return Color.from_hsv(fposmod(color.h + h, 1.0), clampf(color.s + s, 0.0, 1.0), clampf(color.v + v, 0.0, 1.0), color.a)
