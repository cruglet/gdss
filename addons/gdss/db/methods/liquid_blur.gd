@tool
class_name GdssMethod_LiquidBlur
extends GdssMethod

# The liquid-glass refraction this drives is ported from OverShifted/LiquidGlass
# (MIT): https://github.com/OverShifted/LiquidGlass


func _init() -> void:
	method_name = "liquid_blur"
	supported_prop_types = [GDSS.Type.COLOR]
	returns_texture = false
	parameters = [
		Param.new("strength", ParamType.FLOAT, true, 3.0),
		Param.new("color", ParamType.COLOR, true, Color.WHITE),
		Param.new("color_opacity", ParamType.FLOAT, true, 0.06),
		Param.new("refraction", ParamType.FLOAT, true, 1.0),
		Param.new("highlight", ParamType.FLOAT, true, 0.3),
	]


func call_method(args: Array[Variant], node_id: int = -1, state_key: String = "") -> Variant:
	var glass: GdssBlur = GdssBlur.new()
	glass.strength = maxf(float(args[0]), 0.0) if args.size() > 0 and args[0] != null else 3.0
	var base: Color = args[1] if args.size() > 1 and args[1] is Color else Color.WHITE
	var opacity: float = clampf(float(args[2]), 0.0, 1.0) if args.size() > 2 and args[2] != null else 0.06
	glass.tint = Color(base.r, base.g, base.b, opacity)
	glass.refraction = maxf(float(args[3]), 0.0) if args.size() > 3 and args[3] != null else 1.0
	glass.highlight = maxf(float(args[4]), 0.0) if args.size() > 4 and args[4] != null else 0.3
	glass.saturation = 1.2
	return glass
