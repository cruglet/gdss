extends Control

# A small showcase scene for GDSS. The nodes live in demo.tscn; this script only
# drives the light/dark palette swap and the randomize-accent button.

const DARK: Dictionary = {
	"bg": Color("0d0d14"),
	"surface": Color("16161f"),
	"surface_2": Color("1f1f3a"),
	"text": Color("ffffff"),
	"text_dim": Color("9097ad"),
	"border": Color("ffffff22"),
}
const LIGHT: Dictionary = {
	"bg": Color("eceef5"),
	"surface": Color("ffffff"),
	"surface_2": Color("dfe3ee"),
	"text": Color("1b1e28"),
	"text_dim": Color("6a7088"),
	"border": Color("00000018"),
}

@export var toggle_button: Button

var _dark: bool = true


func _ready() -> void:
	_apply_palette(DARK, false)


func _on_switch_pressed() -> void:
	_dark = not _dark
	toggle_button.text = "Switch to light" if _dark else "Switch to dark"
	_apply_palette(DARK if _dark else LIGHT, true)


func _on_randomize_pressed() -> void:
	var from: Color = GDSS.get_global_var("accent", Color.WHITE)
	var to: Color = Color(randf(), randf(), randf())
	var tween: Tween = create_tween().set_ease(Tween.EASE_OUT)
	tween.tween_method(func(color: Color) -> void:
		GDSS.set_global_var("accent", color)
		GDSS.set_global_var("accent_dark", color.darkened(0.5))
	, from, to, 0.35)


func _apply_palette(palette: Dictionary, animate: bool) -> void:
	if not animate:
		for key: String in palette:
			GDSS.set_global_var(key, palette[key])
		return
	var tween: Tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT)
	for key: String in palette:
		var from: Color = GDSS.get_global_var(key, palette[key])
		var to: Color = palette[key]
		tween.tween_method(func(c: Color) -> void:
			GDSS.set_global_var(key, c)
		, from, to, 0.25)
