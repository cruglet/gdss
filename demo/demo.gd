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
var _menu_panel: PanelContainer


func _ready() -> void:
	get_window().content_scale_factor = DisplayServer.screen_get_scale()
	# Embed subwindows so the GDSS-styled PopupMenu renders inside the app window.
	get_window().gui_embed_subwindows = true
	GDSS.set_scheme("dark")
	_on_strength_slider_value_changed(strength_slider.value)
	_on_refraction_slider_value_changed(refraction_slider.value)
	_build_menu()


# A Control-based glass dropdown (PanelContainer + GlassMenu class). Being a Control it
# refracts the app behind it via liquid_blur and pops in/out with the on_show/on_hide
# transition - unlike a Window PopupMenu, whose embedded subwindow can't sample the backdrop.
func _build_menu() -> void:
	_menu_panel = PanelContainer.new()
	_menu_panel.set_meta(GDSS.CLASSES_META, PackedStringArray(["GlassMenu"]))
	_menu_panel.visible = false
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 8)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	for item: String in ["Profile", "Settings", "Sign out"]:
		var row: Button = Button.new()
		row.text = item
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.set_meta(GDSS.CLASSES_META, PackedStringArray(["MenuItem"]))
		row.pressed.connect(func() -> void: GDSS.hide(_menu_panel))
		col.add_child(row)
	margin.add_child(col)
	_menu_panel.add_child(margin)
	add_child(_menu_panel) # added last -> draws above the rest of the UI


func _on_menu_pressed() -> void:
	if _menu_panel.visible:
		GDSS.hide(_menu_panel)
		return
	_menu_panel.reset_size()
	_menu_panel.global_position = menu_btn.global_position + Vector2(0, menu_btn.size.y + 6)
	GDSS.show(_menu_panel)


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
