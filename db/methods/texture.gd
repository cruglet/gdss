@tool
class_name GdssMethod_Texture
extends GdssMethod

func _init() -> void:
	method_name = "texture"
	supported_prop_types = [GDSS.Type.COLOR]
	returns_texture = true
	parameters = [
		Param.new("path", ParamType.STRING, true, ""),
	]


func call_method(args: Array[Variant], node_id: int = -1, state_key: String = "") -> Variant:
	if args.is_empty() or str(args[0]).is_empty():
		return null
	var path: String = str(args[0])
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
