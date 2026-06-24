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

@onready var anim_card: PanelContainer = $AnimCard
@onready var menu_btn: Button = $App/AppMargin/AppCol/Showcase/FeatureRow/MenuBtn

var _dark: bool = true
var _menu: PopupMenu


func _ready() -> void:
	get_window().content_scale_factor = DisplayServer.screen_get_scale()
	# Embed subwindows so the GDSS-styled PopupMenu renders inside the app window.
	get_window().gui_embed_subwindows = true
	GDSS.set_scheme("dark")
	_on_strength_slider_value_changed(strength_slider.value)
	_on_refraction_slider_value_changed(refraction_slider.value)
	_build_menu()


# A GDSS-styled PopupMenu (Window-derived) opened from the showcase row.
func _build_menu() -> void:
	_menu = PopupMenu.new()
	_menu.add_item("Profile")
	_menu.add_item("Settings")
	_menu.add_separator()
	_menu.add_item("Sign out")
	menu_btn.add_child(_menu)


func _on_menu_pressed() -> void:
	_menu.reset_size()
	_menu.position = Vector2i(menu_btn.get_screen_position()) + Vector2i(0, int(menu_btn.size.y) + 4)
	_menu.popup()


# Plays the AnimCard's on_show()/on_hide() one-shot transition.
func _on_toggle_card_pressed() -> void:
	if anim_card.visible:
		GDSS.hide(anim_card)
	else:
		GDSS.show(anim_card)


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
