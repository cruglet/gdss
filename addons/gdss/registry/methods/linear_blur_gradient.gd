@tool
class_name GdssMethod_LinearBlurGradient
extends GdssMethod


func _init() -> void:
	method_name = "linear_blur_gradient"
	supported_prop_types = [GDSS.Type.COLOR]
	returns_texture = false
	parameters = [
		Param.new("strength_start", ParamType.FLOAT, true, 4.0),
		Param.new("strength_end", ParamType.FLOAT, true, 0.0),
		Param.new("color", ParamType.COLOR, true, Color.WHITE),
		Param.new("color_opacity", ParamType.FLOAT, true, 0.06),
		Param.new("angle_degrees", ParamType.FLOAT, true, 0.0),
		Param.new("start", ParamType.FLOAT, true, 0.0),
		Param.new("end", ParamType.FLOAT, true, 1.0),
	]


func call_method(args: Array[Variant], node_id: int = -1, state_key: String = "") -> Variant:
	var blur: GdssBlur = GdssBlur.new()
	blur.strength = maxf(_arg(args, 0, 4.0), 0.0)
	blur.strength_end = maxf(_arg(args, 1, 0.0), 0.0)
	var base: Color = args[2] if args.size() > 2 and args[2] is Color else Color.WHITE
	var opacity: float = clampf(_arg(args, 3, 0.06), 0.0, 1.0)
	blur.tint = Color(base.r, base.g, base.b, opacity)
	blur.refraction = 0.0
	blur.highlight = 0.0
	blur.saturation = 1.0
	var angle_rad: float = deg_to_rad(_arg(args, 4, 0.0))
	var direction: Vector2 = Vector2(cos(angle_rad), sin(angle_rad)) * 0.5
	var start_offset: float = clampf(_arg(args, 5, 0.0), 0.0, 1.0)
	var end_offset: float = clampf(_arg(args, 6, 1.0), 0.0, 1.0)
	blur.grad_p0 = Vector2(0.5, 0.5) - direction
	blur.grad_p1 = Vector2(0.5, 0.5) + direction
	blur.grad_offsets = Vector2(minf(start_offset, end_offset), maxf(start_offset, end_offset))
	return blur


func _arg(args: Array, index: int, fallback: float) -> float:
	if index < args.size() and args[index] != null:
		return float(args[index])
	return fallback


func get_tweenable_args() -> Array[int]:
	return [0, 1, 2, 3, 4, 5, 6]


func interpolate_args(from_args: Array[Variant], to_args: Array[Variant], t: float) -> Array[Variant]:
	var from_color: Color = from_args[2] if from_args.size() > 2 and from_args[2] is Color else Color.WHITE
	var to_color: Color = to_args[2] if to_args.size() > 2 and to_args[2] is Color else Color.WHITE
	return [
		lerpf(_arg(from_args, 0, 4.0), _arg(to_args, 0, 4.0), t),
		lerpf(_arg(from_args, 1, 0.0), _arg(to_args, 1, 0.0), t),
		from_color.lerp(to_color, t),
		lerpf(_arg(from_args, 3, 0.06), _arg(to_args, 3, 0.06), t),
		lerpf(_arg(from_args, 4, 0.0), _arg(to_args, 4, 0.0), t),
		lerpf(_arg(from_args, 5, 0.0), _arg(to_args, 5, 0.0), t),
		lerpf(_arg(from_args, 6, 1.0), _arg(to_args, 6, 1.0), t),
	]
