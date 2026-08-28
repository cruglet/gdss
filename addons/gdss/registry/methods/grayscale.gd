@tool
class_name GdssMethod_Grayscale
extends GdssMethod


func _init() -> void:
	method_name = "grayscale"
	supported_prop_types = [GDSS.Type.COLOR]
	returns_texture = false
	parameters = [
		Param.new("color", ParamType.COLOR),
	]


func call_method(args: Array[Variant], node_id: int = -1, state_key: String = "") -> Variant:
	if args.is_empty():
		return Color.WHITE
	var color: Color = args[0] if args[0] is Color else Color.WHITE
	var luminance: float = color.get_luminance()
	return Color(luminance, luminance, luminance, color.a)
