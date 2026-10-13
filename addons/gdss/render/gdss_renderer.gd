@tool
class_name GdssRenderer
extends RefCounted

const DEFAULT_SHADOW_COLOR: Color = Color(0, 0, 0, 0.4)


static func side_colors(src: Variant, fallback: Color) -> Array:
	var sides: Array = src as Array if src is Array else [src, src, src, src]
	var result: Array = []
	for side: Variant in sides:
		result.append(side if side is Color else fallback)
	return result


static func border_side_colors(src: Variant) -> Array:
	if not src is Array:
		return []
	var sides: Array = src as Array
	var uniform: bool = true
	for side: Variant in sides:
		if not side is Color:
			return []
		if side != sides.front():
			uniform = false
	return [] if uniform else sides


static func border_base(src: Variant) -> Variant:
	if not src is Array:
		return src
	var sides: Array = src as Array
	for side: Variant in sides:
		if not side is Color:
			return side
	return sides.front()


static func max_side(sides: Vector4) -> float:
	return maxf(maxf(sides.x, sides.y), maxf(sides.z, sides.w))
