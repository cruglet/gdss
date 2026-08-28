@tool
class_name GdssMethod_Contrast
extends GdssMethod


func _init() -> void:
	method_name = "contrast"
	supported_prop_types = [GDSS.Type.COLOR]
	returns_texture = false
	parameters = [
		Param.new("color", ParamType.COLOR),
	]


func call_method(args: Array[Variant], node_id: int = -1, state_key: String = "") -> Variant:
	if args.is_empty():
		return Color.WHITE
	var color: Color = args[0] if args[0] is Color else Color.WHITE
	return Color.BLACK if color.get_luminance() > 0.5 else Color.WHITE
