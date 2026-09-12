extends RefCounted


const TC: GDScript = preload("res://tests/gdss_test_context.gd")

const FIXTURE: String = """
Button {
	bg_color: "#202020"
	transition_time: 0.2
	transform_enabled: true
	transform_scale: 1.2 1.2
	:disabled {
		bg_color: "#ff0000"
	}
}
"""


const FIXTURE_CONFIG: String = """
@config {
	sfx_bus: "UI"
	animations_enabled: false
	animation_speed_scale: 0.5
	blur_quality: LOW
	transforms_enabled: false
}
Button {
	bg_color: "#202020"
}
"""

const FIXTURE_CONFIG_BAD: String = """
@config {
	nope: 1
	animations_enabled: maybe
	animation_speed_scale: fast
	blur_quality: ULTRA
	sfx_enabled:
	sfx_enabled: true
}
"""


func run(t: TC) -> void:
	_check_config(t)
	t.apply_fixture(FIXTURE)
	_check_durations(t)
	_check_instant_transitions(t)
	_check_blur_quality(t)
	_check_transforms(t)
	_check_gpu_panels(t)
	_restore_defaults()


func _check_config(t: TC) -> void:
	t.apply_fixture(FIXTURE_CONFIG)
	t.check_eq(GDSS.animations_enabled, false, "@config sets a bool default")
	t.check_eq(GDSS.animation_speed_scale, 0.5, "@config sets a float default")
	t.check_eq(GDSS.blur_quality, GDSS.BlurQuality.LOW, "@config sets an enum default")
	t.check_eq(GDSS.transforms_enabled, false, "@config sets every listed key")
	t.check_eq(GDSS.sfx_bus, &"UI", "@config sets a string default, quotes stripped")
	GDSS.animations_enabled = true
	GDSS.reset_config()
	t.check_eq(GDSS.animations_enabled, false, "reset_config goes back to the sheet's value")
	t.apply_fixture(FIXTURE)
	t.check_eq(GDSS.animations_enabled, true, "a sheet with no @config restores the built-in defaults")
	t.check_eq(GDSS.sfx_bus, &"Master", "dropping a key restores its default too")
	t.check_eq(GDSS.blur_quality, GDSS.BlurQuality.HIGH, "the enum default comes back as well")
	var errors: Array[Array] = t.validate_fixture(FIXTURE_CONFIG_BAD)
	t.check(t.has_error_containing(errors, "Unknown @config key 'nope'"), "unknown key flagged")
	t.check(t.has_error_containing(errors, "'animations_enabled' expects true or false"), "non-bool flagged")
	t.check(t.has_error_containing(errors, "'animation_speed_scale' expects a number"), "non-number flagged")
	t.check(t.has_error_containing(errors, "'blur_quality' expects one of: HIGH, LOW, OFF"), "bad enum value flagged")
	t.check(t.has_error_containing(errors, "'sfx_enabled' has no value"), "valueless key flagged")
	t.check(t.has_error_containing(errors, "is set more than once"), "duplicate key flagged")
	t.check(t.validate_fixture(FIXTURE_CONFIG).is_empty(), "a valid @config block has zero errors")


func _check_durations(t: TC) -> void:
	t.check_eq(GDSS.scaled_duration(0.4), 0.4, "default settings leave durations alone")
	GDSS.animation_speed_scale = 0.5
	t.check_eq(GDSS.scaled_duration(0.4), 0.2, "speed scale shortens durations")
	GDSS.animation_speed_scale = -3.0
	t.check_eq(GDSS.animation_speed_scale, 0.0, "negative speed scale clamps to zero")
	t.check_eq(GDSS.scaled_duration(0.4), 0.0, "a zero speed scale is instant")
	GDSS.animation_speed_scale = 1.0
	GDSS.animations_enabled = false
	t.check_eq(GDSS.scaled_duration(0.4), 0.0, "disabled animations are instant")
	GDSS.animations_enabled = true
	t.check_eq(GDSS.scaled_duration(0.4), 0.4, "re-enabling restores the duration")


func _check_instant_transitions(t: TC) -> void:
	GDSS.animations_enabled = false
	var instant: Button = t.make_styled_button()
	var instant_box: GdssStylebox = GdssNodeBinder.get_primary_stylebox(instant)
	instant.disabled = true
	GDSS.refresh(instant)
	t.check(instant_box._tween == null, "no tween starts while animations are off")
	t.check(instant_box._tweened_values.is_empty(), "no tweened values are tracked")
	t.check_eq(instant_box._get_val("bg_color"), Color("#ff0000"), "the state value applies instantly")
	GdssNodeBinder.unbind(instant)
	instant.free()
	GDSS.animations_enabled = true
	var animated: Button = t.make_styled_button()
	var animated_box: GdssStylebox = GdssNodeBinder.get_primary_stylebox(animated)
	animated.disabled = true
	GDSS.refresh(animated)
	t.check(animated_box._tween != null, "a tween starts once animations are back on")
	GdssNodeBinder.unbind(animated)
	animated.free()
	GDSS.animation_speed_scale = 0.0
	var scaled: Button = t.make_styled_button()
	var scaled_box: GdssStylebox = GdssNodeBinder.get_primary_stylebox(scaled)
	scaled.disabled = true
	GDSS.refresh(scaled)
	t.check(scaled_box._tween == null, "a zero speed scale skips the tween too")
	GdssNodeBinder.unbind(scaled)
	scaled.free()
	GDSS.animation_speed_scale = 1.0


func _check_blur_quality(t: TC) -> void:
	var glass: GdssBlur = GdssBlur.new()
	glass.strength = 3.0
	glass.tint = Color(1.0, 1.0, 1.0, 0.06)
	glass.refraction = 1.0
	glass.highlight = 0.4
	glass.saturation = 1.2
	GDSS.blur_quality = GDSS.BlurQuality.HIGH
	t.check(GdssStylebox._at_blur_quality(glass) == glass, "high quality keeps the authored backdrop")
	GDSS.blur_quality = GDSS.BlurQuality.LOW
	var low: Variant = GdssStylebox._at_blur_quality(glass)
	t.check(low is GdssBlur and low != glass, "low quality swaps in a degraded backdrop")
	t.check_eq((low as GdssBlur).refraction, 0.0, "low quality drops the refraction")
	t.check_eq((low as GdssBlur).highlight, 0.0, "low quality drops the edge highlight")
	t.check_eq((low as GdssBlur).saturation, 1.0, "low quality drops the saturation shift")
	t.check_eq((low as GdssBlur).strength, 3.0, "low quality keeps the blur strength")
	t.check_eq((low as GdssBlur).tint, glass.tint, "low quality keeps the tint")
	t.check(GdssStylebox._at_blur_quality(glass) == low, "the degraded backdrop is cached per blur")
	var plain: GdssBlur = GdssBlur.new()
	plain.tint = Color(0.0, 0.0, 0.0, 0.2)
	t.check(GdssStylebox._at_blur_quality(plain) == plain, "a plain blur is already its own low-quality form")
	GDSS.blur_quality = GDSS.BlurQuality.OFF
	var off: Variant = GdssStylebox._at_blur_quality(glass)
	t.check(off is Color and (off as Color) == glass.tint, "off falls back to the tint colour")
	t.check_eq(GdssStylebox._at_blur_quality(Color.RED), Color.RED, "values that are not backdrops pass through")
	GDSS.blur_quality = GDSS.BlurQuality.HIGH


func _check_transforms(t: TC) -> void:
	var button: Button = t.make_styled_button()
	var stylebox: GdssStylebox = GdssNodeBinder.get_primary_stylebox(button)
	stylebox._applied_node_props.clear()
	stylebox.reapply()
	t.check(stylebox._applied_node_props.has("transform_scale"), "transform properties apply by default")
	GDSS.transforms_enabled = false
	stylebox._applied_node_props.clear()
	stylebox.reapply()
	t.check(not stylebox._applied_node_props.has("transform_scale"), "disabling transforms falls back to the defaults")
	GDSS.transforms_enabled = true
	stylebox._applied_node_props.clear()
	stylebox.reapply()
	t.check(stylebox._applied_node_props.has("transform_scale"), "re-enabling transforms restores them")
	GdssNodeBinder.unbind(button)
	button.free()


func _check_gpu_panels(t: TC) -> void:
	var initial: bool = GDSS.gpu_panels
	GDSS.gpu_panels = not initial
	t.check_eq(GDSS.gpu_panels, not initial, "gpu panels toggle at runtime")
	t.check_eq(GDSS.gpu_panels_enabled(), not initial, "gpu_panels_enabled() agrees with the property")
	GDSS.gpu_panels = initial
	t.check_eq(GDSS.gpu_panels, initial, "gpu panels restore")


func _restore_defaults() -> void:
	GDSS.animations_enabled = true
	GDSS.animation_speed_scale = 1.0
	GDSS.blur_quality = GDSS.BlurQuality.HIGH
	GDSS.transforms_enabled = true
