@tool
class_name GdssTextureFade
extends RefCounted

var target: Texture2D = null
var texture: Texture2D = null
var value: float = 1.0
var tween: Tween = null


func fade_to(new_target: Texture2D, duration: float, node: Node, redraw: Callable) -> Texture2D:
	if new_target == target:
		return texture
	target = new_target
	if tween != null and tween.is_valid():
		tween.kill()
	if duration <= 0.0 or not is_instance_valid(node) or not node.is_inside_tree():
		texture = new_target
		value = 1.0
		return texture
	if new_target != null and new_target != texture:
		texture = new_target
		value = 0.0
	tween = node.get_tree().create_tween()
	tween.tween_method(func(v: float) -> void:
		value = v
		redraw.call()
	, value, 1.0 if new_target != null else 0.0, duration)
	tween.finished.connect(func() -> void:
		tween = null
		if target == null:
			texture = null
			value = 1.0
			redraw.call()
	)
	return texture
