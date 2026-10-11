@tool
class_name GdssTexture
extends RefCounted

var texture: Texture2D
var interpolation: GDSS.Interpolation = GDSS.Interpolation.DEFAULT
var repeat: bool = false
var preserve_aspect: bool = false


static func interpolation_names() -> PackedStringArray:
	return PackedStringArray(GDSS.Interpolation.keys())


static func parse_interpolation(value: Variant) -> GDSS.Interpolation:
	if value is int:
		return value as GDSS.Interpolation
	var index: int = interpolation_names().find(str(value).strip_edges().to_upper())
	return index if index != -1 else GDSS.Interpolation.DEFAULT


func is_nearest() -> bool:
	return interpolation == GDSS.Interpolation.NEAREST
