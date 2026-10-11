@tool
class_name GdssClipPath
extends RefCounted

const MAX_POINTS: int = 32

var points: PackedVector2Array = PackedVector2Array()


func padded() -> PackedVector2Array:
	var out: PackedVector2Array = points.slice(0, mini(points.size(), MAX_POINTS))
	out.resize(MAX_POINTS)
	return out


func count() -> int:
	return mini(points.size(), MAX_POINTS)
