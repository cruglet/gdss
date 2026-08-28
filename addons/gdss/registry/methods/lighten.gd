@tool
class_name GdssMethod_Lighten
extends GdssMethod


func _init() -> void:
	method_name = "lighten"
	supported_prop_types = [GDSS.Type.COLOR]
	returns_texture = false
	parameters = [
		Param.new("color", ParamType.COLOR),
		Param.new("amount", ParamType.FLOAT, true, 0.1),
	]


func call_method(args: Array[Variant], node_id: int = -1, state_key: String = "") -> Variant:
	if args.is_empty():
		return Color.WHITE
	var color: Color = args[0] if args[0] is Color else Color.WHITE
	var amount: float = float(args[1]) if args.size() > 1 else 0.1
	return color.lightened(amount)
