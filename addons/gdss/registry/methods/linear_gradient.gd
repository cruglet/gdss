@tool
class_name GdssMethod_LinearGradient
extends GdssMethod

static var _live: Dictionary = {}


func _init() -> void:
	method_name = "linear_gradient"
	supported_prop_types = [GDSS.Type.COLOR]
	returns_texture = true
	parameters = [
		Param.new("color1", ParamType.COLOR),
		Param.new("color2", ParamType.COLOR),
		Param.new("angle_degrees", ParamType.FLOAT, true, 0.0),
		Param.new("start", ParamType.FLOAT, true, 0.0),
		Param.new("end", ParamType.FLOAT, true, 1.0),
	]


func call_method(args: Array[Variant], node_id: int = -1, state_key: String = "") -> Variant:
	if args.size() < 2:
		return null
	var color1: Color = args[0] if args[0] is Color else Color.WHITE
	var color2: Color = args[1] if args[1] is Color else Color.BLACK
	var angle_rad: float = deg_to_rad(_arg(args, 2, 0.0))
	var direction: Vector2 = Vector2(cos(angle_rad), sin(angle_rad)) * 0.5
	var start_offset: float = clampf(_arg(args, 3, 0.0), 0.0, 1.0)
	var end_offset: float = clampf(_arg(args, 4, 1.0), 0.0, 1.0)
	var grad: GdssGradient = _obtain(node_id, state_key)
	grad.mode = 1
	grad.color_a = color1
	grad.color_b = color2
	grad.p0 = Vector2(0.5, 0.5) - direction
	grad.p1 = Vector2(0.5, 0.5) + direction
	grad.offsets = Vector2(minf(start_offset, end_offset), maxf(start_offset, end_offset))
	return grad


func _obtain(node_id: int, state_key: String) -> GdssGradient:
	if node_id == -1 or state_key.is_empty():
		return GdssGradient.new()
	var key: String = str(node_id) + ":" + state_key
	if not _live.has(key):
		_live[key] = GdssGradient.new()
	return _live[key]


func _arg(args: Array, index: int, fallback: float) -> float:
	if index < args.size() and args[index] != null:
		return float(args[index])
	return fallback


func get_tweenable_args() -> Array[int]:
	return [0, 1, 2, 3, 4]


func interpolate_args(from_args: Array[Variant], to_args: Array[Variant], t: float) -> Array[Variant]:
	var color1: Color = (from_args[0] if from_args[0] is Color else Color.WHITE).lerp(
		to_args[0] if to_args[0] is Color else Color.WHITE, t)
	var color2: Color = (from_args[1] if from_args[1] is Color else Color.BLACK).lerp(
		to_args[1] if to_args[1] is Color else Color.BLACK, t)
	return [
		color1,
		color2,
		lerpf(_arg(from_args, 2, 0.0), _arg(to_args, 2, 0.0), t),
		lerpf(_arg(from_args, 3, 0.0), _arg(to_args, 3, 0.0), t),
		lerpf(_arg(from_args, 4, 1.0), _arg(to_args, 4, 1.0), t),
	]


func clear_live_textures() -> void:
	var keys_to_erase: Array = []
	for key: String in _live:
		if ":tween:" in key:
			keys_to_erase.append(key)
	for key: String in keys_to_erase:
		_live.erase(key)


func purge_node(node_id: int) -> void:
	var prefix: String = str(node_id) + ":"
	var keys_to_erase: Array = []
	for key: String in _live:
		if (key as String).begins_with(prefix):
			keys_to_erase.append(key)
	for key: String in keys_to_erase:
		_live.erase(key)
