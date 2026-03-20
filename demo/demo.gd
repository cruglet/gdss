extends Control


func _on_randomize_accent_pressed() -> void:
	var from: Color = GDSS.get_global_var("accent", Color.WHITE)
	var to: Color = Color(randf(), randf(), randf())
	var tween: Tween = create_tween().set_ease(Tween.EASE_OUT)
	tween.tween_method(func(c: Color) -> void:
		GDSS.set_global_var("accent", c)
		GDSS.set_global_var("accent_dark", c.darkened(0.5))
	, from, to, 0.35)
