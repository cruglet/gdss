extends Control

# 0.5.x showcase. A small fake GDSS-themed app sits in the background so the two
# draggable glass buttons have real UI to frost (blur) and refract (liquid_blur)
# as you move them. The top bar swaps the light/dark @scheme and animates the
# @global accent; the sliders retune both glass buttons through @instance vars.

@export var frosted: Button
@export var liquid: Button
@export var switch_button: Button
@export var strength_slider: HSlider
@export var refraction_slider: HSlider
@export var strength_value: Label
@export var refraction_value: Label

var _dark: bool = true


func _ready() -> void:
	GDSS.set_scheme("dark")
	_on_strength_slider_value_changed(strength_slider.value)
	_on_refraction_slider_value_changed(refraction_slider.value)


func _on_switch_pressed() -> void:
	_dark = not _dark
	switch_button.text = "Switch to light" if _dark else "Switch to dark"
	GDSS.set_scheme("dark" if _dark else "light", 0.25)


func _on_randomize_pressed() -> void:
	var from: Color = GDSS.get_global_var("accent", Color.WHITE)
	var to: Color = Color(randf(), randf(), randf())
	var tween: Tween = create_tween().set_ease(Tween.EASE_OUT)
	tween.tween_method(func(color: Color) -> void:
		GDSS.set_global_var("accent", color)
		GDSS.set_global_var("accent_dark", color.darkened(0.4))
	, from, to, 0.35)


func _on_strength_slider_value_changed(value: float) -> void:
	GDSS.set_instance_var(frosted, "glass_strength", value)
	GDSS.set_instance_var(liquid, "glass_strength", value)
	strength_value.text = "%.1f" % value


func _on_refraction_slider_value_changed(value: float) -> void:
	GDSS.set_instance_var(liquid, "glass_refraction", value)
	refraction_value.text = "%.1f" % value
