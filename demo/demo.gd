extends Control

# A small showcase scene for GDSS. The nodes live in demo.tscn; this script only
# drives the light/dark scheme swap and the randomize-accent button. The palettes
# themselves live in theme.tgdss as @scheme blocks.

@export var toggle_button: Button

var _dark: bool = true


func _ready() -> void:
	GDSS.set_scheme("dark")


func _on_switch_pressed() -> void:
	_dark = not _dark
	toggle_button.text = "Switch to light" if _dark else "Switch to dark"
	GDSS.set_scheme("dark" if _dark else "light", 0.25)


func _on_randomize_pressed() -> void:
	var from: Color = GDSS.get_global_var("accent", Color.WHITE)
	var to: Color = Color(randf(), randf(), randf())
	var tween: Tween = create_tween().set_ease(Tween.EASE_OUT)
	tween.tween_method(func(color: Color) -> void:
		GDSS.set_global_var("accent", color)
		GDSS.set_global_var("accent_dark", color.darkened(0.5))
	, from, to, 0.35)
