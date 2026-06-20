@tool
class_name GdssMethod_Blur
extends GdssMethod


func _init() -> void:
	method_name = "blur"
	supported_prop_types = [GDSS.Type.COLOR]
	returns_texture = false
	parameters = [
		Param.new("strength", ParamType.FLOAT, true, 4.0),
		Param.new("color", ParamType.COLOR, true, Color.WHITE),
		Param.new("color_opacity", ParamType.FLOAT, true, 0.0),
	]


func call_method(args: Array[Variant], node_id: int = -1, state_key: String = "") -> Variant:
	var blur: GdssBlur = GdssBlur.new()
	blur.strength = maxf(float(args[0]), 0.0) if args.size() > 0 and args[0] != null else 4.0
	var base: Color = args[1] if args.size() > 1 and args[1] is Color else Color.BLACK
	var opacity: float = clampf(float(args[2]), 0.0, 1.0) if args.size() > 2 and args[2] != null else 0.2
	blur.tint = Color(base.r, base.g, base.b, opacity)
	blur.refraction = 0.0
	blur.highlight = 0.0
	blur.saturation = 1.0
	return blur
