@tool
class_name GdssMethod_LinearGradient
extends GdssMethod

static var _live_textures: Dictionary = {}

func _init() -> void:
	method_name = "linear_gradient"
	supported_prop_types = [GDSS.Type.COLOR]
	returns_texture = true
	parameters = [
		Param.new("color1", ParamType.COLOR),
		Param.new("color2", ParamType.COLOR),
		Param.new("angle_degrees", ParamType.FLOAT, true, 0.0),
	]


func call_method(args: Array[Variant], node_id: int = -1, state_key: String = "") -> Variant:
	if args.size() < 2:
		return null
	var c1: Color = args[0] if args[0] is Color else Color.WHITE
	var c2: Color = args[1] if args[1] is Color else Color.BLACK
	var angle_deg: float = float(args[2]) if args.size() > 2 else 0.0
	var grad: Gradient = Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.set_color(0, c1)
	grad.set_color(1, c2)
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = grad
	var angle_rad: float = deg_to_rad(angle_deg)
	tex.fill_from = Vector2(0.5, 0.5) - Vector2(cos(angle_rad), sin(angle_rad)) * 0.5
	tex.fill_to = Vector2(0.5, 0.5) + Vector2(cos(angle_rad), sin(angle_rad)) * 0.5
	if node_id != -1 and not state_key.is_empty():
		_live_textures[str(node_id) + ":" + state_key] = tex
	return tex


func get_tweenable_args() -> Array[int]:
	return [0, 1, 2]


func get_live_texture(node_id: int, state_key: String) -> Texture2D:
	var key: String = str(node_id) + ":" + state_key
	return _live_textures.get(key, null) as Texture2D


func interpolate_args(from_args: Array[Variant], to_args: Array[Variant], t: float) -> Array[Variant]:
	var result: Array[Variant] = []
	var c1: Color = (from_args[0] if from_args[0] is Color else Color.from_string(str(from_args[0]), Color.WHITE)).lerp(
		to_args[0] if to_args[0] is Color else Color.from_string(str(to_args[0]), Color.WHITE), t)
	var c2: Color = (from_args[1] if from_args[1] is Color else Color.from_string(str(from_args[1]), Color.BLACK)).lerp(
		to_args[1] if to_args[1] is Color else Color.from_string(str(to_args[1]), Color.BLACK), t)
	var angle: float = lerpf(
		float(from_args[2]) if from_args.size() > 2 else 0.0,
		float(to_args[2]) if to_args.size() > 2 else 0.0, t)
	result.append(c1)
	result.append(c2)
	result.append(angle)
	return result


func clear_live_textures() -> void:
	var tween_keys: Array = []
	for key: String in _live_textures:
		if ":tween:" not in key:
			tween_keys.append(key)
	for key: String in tween_keys:
		_live_textures.erase(key)
