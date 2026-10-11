@tool
class_name GdssMethod_Texture
extends GdssMethod

static var _cache: Dictionary = {}


func _init() -> void:
	method_name = "texture"
	supported_prop_types = [GDSS.Type.COLOR, GDSS.Type.ICON]
	returns_texture = true
	parameters = [
		Param.new("path", ParamType.STRING, true, ""),
		Param.new("interpolation", ParamType.ENUM, true, "DEFAULT", GdssTexture.interpolation_names()),
		Param.new("preserve_aspect", ParamType.BOOL, true, false),
		Param.new("repeat", ParamType.BOOL, true, false),
	]


func call_method(args: Array[Variant], _node_id: int = -1, _state_key: String = "") -> Variant:
	if args.is_empty() or str(args.get(0)).is_empty():
		return null
	var path: String = str(args.get(0))
	var tex: Texture2D = _cache.get(path)
	if tex == null:
		if not ResourceLoader.exists(path):
			return null
		tex = load(path) as Texture2D
		if tex == null:
			return null
		_cache.set(path, tex)
	if args.size() <= 1:
		return tex
	var wrapped: GdssTexture = GdssTexture.new()
	wrapped.texture = tex
	wrapped.interpolation = GdssTexture.parse_interpolation(args.get(1))
	wrapped.preserve_aspect = _flag(args, 2)
	wrapped.repeat = _flag(args, 3)
	return wrapped


func _flag(args: Array, index: int) -> bool:
	if index >= args.size() or args.get(index) == null:
		return false
	var raw: Variant = args.get(index)
	if raw is bool:
		return raw
	return str(raw).strip_edges().to_lower() in ["true", "1"]


func clear_live_textures() -> void:
	_cache.clear()
