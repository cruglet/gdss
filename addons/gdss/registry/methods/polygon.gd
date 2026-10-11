@tool
class_name GdssMethod_Polygon
extends GdssMethod

const MIN_ARGS: int = 6


func _init() -> void:
	method_name = "polygon"
	supported_prop_types = [GDSS.Type.CLIP_PATH]
	variadic = true
	parameters = [
		Param.new("x1", ParamType.FLOAT),
		Param.new("y1", ParamType.FLOAT),
		Param.new("x2", ParamType.FLOAT),
		Param.new("y2", ParamType.FLOAT),
		Param.new("x3", ParamType.FLOAT),
		Param.new("y3", ParamType.FLOAT),
	]


func call_method(args: Array[Variant], _node_id: int = -1, _state_key: String = "") -> Variant:
	if args.size() < MIN_ARGS:
		return null
	var path: GdssClipPath = GdssClipPath.new()
	var points: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in _to_points(args):
		points.append(point)
	path.points = points
	return path


func get_tweenable_args() -> Array[int]:
	return [0, 1, 2, 3, 4, 5]


func interpolate_args(from_args: Array[Variant], to_args: Array[Variant], t: float) -> Array[Variant]:
	var from_points: Array = _to_points(from_args)
	var to_points: Array = _to_points(to_args)
	if from_points.size() < 3 or to_points.size() < 3:
		return to_args
	var target: int = mini(maxi(from_points.size(), to_points.size()), GdssClipPath.MAX_POINTS)
	if from_points.size() != target:
		from_points = _resample(from_points, target)
	if to_points.size() != target:
		to_points = _resample(to_points, target)
	var out: Array[Variant] = []
	for i: int in target:
		var point: Vector2 = (from_points.get(i) as Vector2).lerp(to_points.get(i), t)
		out.append(point.x)
		out.append(point.y)
	return out


func _to_points(args: Array) -> Array:
	var out: Array = []
	for i: int in mini(args.size() / 2, GdssClipPath.MAX_POINTS):
		out.append(Vector2(_num(args, i * 2), _num(args, i * 2 + 1)))
	return out


func _resample(points: Array, target: int) -> Array:
	var lengths: Array = []
	var total: float = 0.0
	for i: int in points.size():
		var seg: float = (points.get(i) as Vector2).distance_to(points.get((i + 1) % points.size()))
		lengths.append(seg)
		total += seg
	if total <= 0.0:
		return points
	var out: Array = []
	for k: int in target:
		var want: float = total * float(k) / float(target)
		var walked: float = 0.0
		for i: int in points.size():
			var seg: float = lengths.get(i)
			if walked + seg >= want or i == points.size() - 1:
				var ratio: float = clampf((want - walked) / maxf(seg, 0.00001), 0.0, 1.0)
				out.append((points.get(i) as Vector2).lerp(points.get((i + 1) % points.size()), ratio))
				break
			walked += seg
	return out


func _num(args: Array, index: int) -> float:
	if index >= args.size() or args.get(index) == null:
		return 0.0
	var raw: Variant = args.get(index)
	if raw is String:
		var text: String = raw
		return float(text.trim_suffix("%")) / 100.0 if text.ends_with("%") else float(text)
	return float(raw)
