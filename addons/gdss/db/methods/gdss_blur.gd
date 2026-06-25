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
