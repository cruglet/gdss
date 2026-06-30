@tool
class_name GdssMethod_Font
extends GdssMethod

static var _cache: Dictionary = {}

func _init() -> void:
	method_name = "font"
	supported_prop_types = [GDSS.Type.FONT]
	parameters = [
		Param.new("path", ParamType.STRING, true, ""),
	]


func call_method(args: Array[Variant], node_id: int = -1, state_key: String = "") -> Variant:
	if args.is_empty() or str(args[0]).is_empty():
		return null
	var path: String = str(args[0])
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		return null
	var font: Font = load(path) as Font
	if font == null:
		return null
	_cache[path] = font
	return font


func clear_live_textures() -> void:
	_cache.clear()
