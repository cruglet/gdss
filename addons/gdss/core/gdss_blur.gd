@tool
class_name GdssBlur
extends RefCounted

var strength: float = 4.0
var strength_end: float = 4.0
var tint: Color = Color(0.0, 0.0, 0.0, 0.0)
var refraction: float = 0.0
var highlight: float = 0.0
var saturation: float = 1.0
var grad_p0: Vector2 = Vector2(0.0, 0.5)
var grad_p1: Vector2 = Vector2(1.0, 0.5)
var grad_offsets: Vector2 = Vector2(0.0, 1.0)

var _plain: GdssBlur


## The same backdrop without refraction, edge highlight or saturation shift, so a
## liquid_blur() degrades to what blur() would have produced. Cached per instance.
func to_plain() -> GdssBlur:
	if refraction == 0.0 and highlight == 0.0 and saturation == 1.0:
		return self
	if _plain == null:
		_plain = GdssBlur.new()
		_plain.strength = strength
		_plain.strength_end = strength_end
		_plain.tint = tint
		_plain.grad_p0 = grad_p0
		_plain.grad_p1 = grad_p1
		_plain.grad_offsets = grad_offsets
	return _plain
