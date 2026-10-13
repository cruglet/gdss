@tool
class_name GdssGpuRenderer
extends GdssRenderer

const _SHADOW_CORNER_SPILL: float = 0.4
static var _shader: Shader = null
static var _blur_shader: Shader = null

var canvas_item: RID = RID()
var parent_item: RID = RID()

var _material: ShaderMaterial = null
var _is_blur: bool = false
var _last_params: Dictionary = {}
var _quad: Rect2 = Rect2()
var _xform: Transform2D = Transform2D.IDENTITY
var _emitted: bool = false
var _warned_clip: bool = false
var _fill_tint: Color = Color.WHITE
var _fill_scroll: Vector2 = Vector2.ZERO
var _fill_scale: Vector2 = Vector2.ZERO
var _fill_texture: Texture2D = null
var _fill_aspect: bool = false
var _fill_repeat: bool = false
var _fill_nearest: bool = false
var _fill_natural: bool = false
var _fade_texture: Texture2D = null
var _fade_target: Texture2D = null
var _fade_value: float = 1.0
var _fade_tween: Tween
var _node: Node = null
var _redraw: Callable


func _init(redraw: Callable) -> void:
	_redraw = redraw


static func _get_shared_shader() -> Shader:
	if _shader == null:
		_shader = load("res://addons/gdss/render/shaders/gdss_panel.gdshader") as Shader
	return _shader


static func _get_blur_shader() -> Shader:
	if _blur_shader == null:
		_blur_shader = load("res://addons/gdss/render/shaders/gdss_blur.gdshader") as Shader
	return _blur_shader


func _ensure_canvas_item(to_canvas_item: RID, want_blur: bool = false) -> void:
	if not canvas_item.is_valid():
		canvas_item = RenderingServer.canvas_item_create()
		_material = ShaderMaterial.new()
		_is_blur = want_blur
		_material.shader = _get_blur_shader() if want_blur else _get_shared_shader()
		RenderingServer.canvas_item_set_material(canvas_item, _material.get_rid())
		RenderingServer.canvas_item_set_draw_behind_parent(canvas_item, true)
		RenderingServer.canvas_item_set_copy_to_backbuffer(canvas_item, want_blur, Rect2())
		parent_item = RID()
	elif _is_blur != want_blur:
		_is_blur = want_blur
		_material.shader = _get_blur_shader() if want_blur else _get_shared_shader()
		RenderingServer.canvas_item_set_copy_to_backbuffer(canvas_item, want_blur, Rect2())
		_last_params.clear()
	if parent_item != to_canvas_item:
		RenderingServer.canvas_item_set_parent(canvas_item, to_canvas_item)
		parent_item = to_canvas_item


func _in_clip_group() -> bool:
	var node: Node = _node
	while node:
		if node is CanvasGroup:
			return true
		if node is CanvasItem and node.clip_children != CanvasItem.CLIP_CHILDREN_DISABLED:
			return true
		node = node.get_parent()
	return false


func release() -> void:
	if canvas_item.is_valid():
		RenderingServer.free_rid(canvas_item)
		canvas_item = RID()
		parent_item = RID()
	_material = null
	_last_params.clear()
	_emitted = false


func _set_param(key: StringName, value: Variant) -> void:
	if _last_params.get(key) == value and _last_params.has(key):
		return
	_last_params.set(key, value)
	_material.set_shader_parameter(key, value)


func draw(to_canvas_item: RID, rect: Rect2, vals: Dictionary, node: Node, fade_duration: float) -> void:
	_node = node
	var bg: Variant = at_blur_quality(vals.get("bg_color", Color.TRANSPARENT))
	var border_raw: Variant = vals.get("border_color", Color.TRANSPARENT)
	var border_src: Variant = at_blur_quality(border_base(border_raw))
	var border_sides: Array = border_side_colors(border_raw)
	var want_blur: bool = bg is GdssBlur or border_src is GdssBlur
	if want_blur and _in_clip_group():
		want_blur = false
		if not _warned_clip:
			_warned_clip = true
			push_warning("[GDSS] Blur disabled on %s: a clip_children or CanvasGroup ancestor renders its children into the backbuffer, so the engine binds a solid white screen texture and the blur would draw pure white. Mask without a clip group to keep the blur." % _node)
	_ensure_canvas_item(to_canvas_item, want_blur)
	var shadow: Vector4 = Vector4(vals.get("shadow", Vector4i.ZERO))
	var shadow_offset: Vector2 = vals.get("shadow_offset", Vector2.ZERO)
	var pad: Vector4 = Vector4.ZERO
	if max_side(shadow) > 0.5:
		var spill_x: float = maxf(shadow.z, shadow.w) * _SHADOW_CORNER_SPILL
		var spill_y: float = maxf(shadow.x, shadow.y) * _SHADOW_CORNER_SPILL
		pad = Vector4(
			maxf(shadow.x, spill_x) + maxf(-shadow_offset.x, 0.0) + 2.0,
			maxf(shadow.y, spill_x) + maxf(shadow_offset.x, 0.0) + 2.0,
			maxf(shadow.z, spill_y) + maxf(-shadow_offset.y, 0.0) + 2.0,
			maxf(shadow.w, spill_y) + maxf(shadow_offset.y, 0.0) + 2.0,
		)
	var quad: Rect2 = rect.grow_individual(pad.x, pad.z, pad.y, pad.w)
	var pad_min: Vector2 = Vector2(pad.x / quad.size.x, pad.z / quad.size.y)
	var pad_max: Vector2 = Vector2(pad.y / quad.size.x, pad.w / quad.size.y)
	var anti_aliasing: bool = vals.get("anti_aliasing", true)
	_set_param(&"u_size", quad.size)
	_set_param(&"u_pad", pad)
	_set_param(&"u_corner_radius", Vector4(vals.get("corner_radius", Vector4i.ZERO)))
	_set_param(&"u_border_widths", Vector4(vals.get("border", Vector4i.ZERO)))
	_set_param(&"u_shadow", shadow)
	_set_param(&"u_aa", 1.0 if anti_aliasing else 0.0)
	var clip_src: Variant = vals.get("clip_path")
	if clip_src is GdssClipPath:
		var clip_path: GdssClipPath = clip_src
		_set_param(&"u_clip_count", clip_path.count())
		_set_param(&"u_clip", clip_path.padded())
	else:
		_set_param(&"u_clip_count", 0)
	_set_param(&"u_shadow_blur", float(vals.get("shadow_blur", -1.0)))
	_set_param(&"u_shadow_offset", shadow_offset)
	var shadow_src: Variant = vals.get("shadow_color", DEFAULT_SHADOW_COLOR)
	_set_param(&"u_shadow_color", shadow_src if shadow_src is Color else DEFAULT_SHADOW_COLOR)
	var tint_src: Variant = vals.get("bg_tint", Color.WHITE)
	_fill_tint = tint_src if tint_src is Color else Color.WHITE
	var scroll_src: Variant = vals.get("bg_scroll", Vector2.ZERO)
	_fill_scroll = scroll_src if scroll_src is Vector2 else Vector2.ZERO
	var scale_src: Variant = vals.get("bg_texture_scale", Vector2.ZERO)
	_fill_scale = scale_src if scale_src is Vector2 else Vector2.ZERO
	_resolve_fill_texture(vals.get("bg_texture"), bg, fade_duration)
	_push_fill(bg, pad_min, pad_max)
	_push_border(border_src, border_sides, pad_min, pad_max)
	var xform: Transform2D = _skew_transform(rect, vals.get("skew_x", 0.0), vals.get("skew_y", 0.0))
	if not _emitted or quad != _quad or xform != _xform:
		_quad = quad
		_xform = xform
		_emitted = true
		RenderingServer.canvas_item_clear(canvas_item)
		RenderingServer.canvas_item_set_transform(canvas_item, xform)
		RenderingServer.canvas_item_add_rect(canvas_item, quad, Color.WHITE)


static func at_blur_quality(value: Variant) -> Variant:
	if not value is GdssBlur:
		return value
	match GDSS.blur_quality:
		GDSS.BlurQuality.OFF:
			return (value as GdssBlur).tint
		GDSS.BlurQuality.LOW:
			return (value as GdssBlur).to_plain()
	return value


func _resolve_fill_texture(src: Variant, fallback: Variant, duration: float) -> void:
	if not (src is GdssTexture or src is Texture2D):
		src = fallback
	_fill_texture = null
	_fill_aspect = false
	_fill_repeat = false
	_fill_nearest = false
	_fill_natural = false
	if src is GdssTexture:
		var wrapped: GdssTexture = src
		_fill_texture = wrapped.texture
		_fill_aspect = wrapped.preserve_aspect
		_fill_repeat = wrapped.repeat
		_fill_natural = wrapped.repeat
		_fill_nearest = wrapped.is_nearest()
	elif src is Texture2D:
		_fill_texture = src
	if _fill_scroll != Vector2.ZERO or _fill_scale != Vector2.ZERO:
		_fill_repeat = true
	_fill_texture = _fade_to(_fill_texture, duration)


func _fade_to(target: Texture2D, duration: float) -> Texture2D:
	if target == _fade_target:
		return _fade_texture
	_fade_target = target
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	if duration <= 0.0 or not is_instance_valid(_node) or not _node.is_inside_tree():
		_fade_texture = target
		_fade_value = 1.0
		return _fade_texture
	if target != null and target != _fade_texture:
		_fade_texture = target
		_fade_value = 0.0
	_fade_tween = (Engine.get_main_loop() as SceneTree).create_tween()
	_fade_tween.tween_method(func(v: float) -> void:
		_fade_value = v
		_redraw.call()
	, _fade_value, 1.0 if target != null else 0.0, duration)
	if target == null:
		_fade_tween.finished.connect(func() -> void:
			if _fade_target == null:
				_fade_texture = null
				_fade_value = 1.0
				_redraw.call()
		)
	return _fade_texture


func _push_fill(bg: Variant, pad_min: Vector2, pad_max: Vector2) -> void:
	if _fill_texture != null:
		_set_param(&"u_fill_mode", 3)
		_set_param(&"u_tex", null if _fill_nearest else _fill_texture)
		_set_param(&"u_tex_nearest", _fill_texture if _fill_nearest else null)
		_set_param(&"u_fill_nearest", 1.0 if _fill_nearest else 0.0)
		_set_param(&"u_fill_repeat", 1.0 if _fill_repeat else 0.0)
		_set_param(&"u_fill_natural", 1.0 if _fill_natural else 0.0)
		_set_param(&"u_fill_fade", _fade_value)
		_set_param(&"u_fill_tint", _fill_tint)
		_set_param(&"u_fill_scroll", _fill_scroll)
		_set_param(&"u_fill_scale", _fill_scale)
		_set_param(&"u_fill_aspect", 1.0 if _fill_aspect else 0.0)
		_set_param(&"u_fill_a", bg if bg is Color else Color.TRANSPARENT)
		return
	if bg is GdssGradient:
		var grad: GdssGradient = bg as GdssGradient
		_set_param(&"u_fill_a", grad.color_a)
		_set_param(&"u_fill_b", grad.color_b)
		_set_param(&"u_grad_offsets", grad.offsets)
		_set_param(&"u_grad_p0", _remap_uv(grad.p0, pad_min, pad_max))
		_set_param(&"u_grad_p1", _remap_uv(grad.p1, pad_min, pad_max))
		_set_param(&"u_fill_mode", grad.mode)
	elif bg is GdssBlur:
		var blur: GdssBlur = bg as GdssBlur
		_set_param(&"u_fill_a", blur.tint)
		_set_param(&"u_fill_glass", Vector4(blur.strength, blur.refraction, blur.highlight, blur.saturation))
		if blur.strength_end != blur.strength:
			_set_param(&"u_fill_mode", 5)
			_set_param(&"u_fill_glass2", Vector4(blur.strength_end, blur.refraction, blur.highlight, blur.saturation))
			_set_param(&"u_grad_offsets", blur.grad_offsets)
			_set_param(&"u_grad_p0", _remap_uv(blur.grad_p0, pad_min, pad_max))
			_set_param(&"u_grad_p1", _remap_uv(blur.grad_p1, pad_min, pad_max))
		else:
			_set_param(&"u_fill_mode", 4)
	elif bg is Color:
		_set_param(&"u_fill_mode", 0)
		_set_param(&"u_fill_a", bg as Color)
	else:
		_set_param(&"u_fill_mode", 0)
		_set_param(&"u_fill_a", Color.TRANSPARENT)


func _push_border(border_src: Variant, border_sides: Array, pad_min: Vector2, pad_max: Vector2) -> void:
	if not border_sides.is_empty():
		_set_param(&"u_border_mode", 4)
		_set_param(&"u_border_left", border_sides.get(0))
		_set_param(&"u_border_right", border_sides.get(1))
		_set_param(&"u_border_top", border_sides.get(2))
		_set_param(&"u_border_bottom", border_sides.get(3))
		return
	if border_src is GdssGradient:
		var grad: GdssGradient = border_src as GdssGradient
		_set_param(&"u_border_mode", 1)
		_set_param(&"u_border_a", grad.color_a)
		_set_param(&"u_border_b", grad.color_b)
		_set_param(&"u_border_p0", _remap_uv(grad.p0, pad_min, pad_max))
		_set_param(&"u_border_p1", _remap_uv(grad.p1, pad_min, pad_max))
	elif border_src is GdssBlur:
		var blur: GdssBlur = border_src as GdssBlur
		_set_param(&"u_border_a", blur.tint)
		_set_param(&"u_border_glass", Vector4(blur.strength, blur.refraction, blur.highlight, blur.saturation))
		if blur.strength_end != blur.strength:
			_set_param(&"u_border_mode", 3)
			_set_param(&"u_border_glass2", Vector4(blur.strength_end, blur.refraction, blur.highlight, blur.saturation))
			_set_param(&"u_border_p0", _remap_uv(blur.grad_p0, pad_min, pad_max))
			_set_param(&"u_border_p1", _remap_uv(blur.grad_p1, pad_min, pad_max))
		else:
			_set_param(&"u_border_mode", 2)
	elif border_src is Color:
		_set_param(&"u_border_mode", 0)
		_set_param(&"u_border_a", border_src as Color)
	else:
		_set_param(&"u_border_mode", 0)
		_set_param(&"u_border_a", Color.TRANSPARENT)


func _remap_uv(uv: Vector2, pad_min: Vector2, pad_max: Vector2) -> Vector2:
	return pad_min + uv * (Vector2.ONE - pad_min - pad_max)


func _skew_transform(rect: Rect2, skew_x: float, skew_y: float) -> Transform2D:
	if skew_x == 0.0 and skew_y == 0.0:
		return Transform2D.IDENTITY
	var center: Vector2 = rect.position + rect.size * 0.5
	var bx: Vector2 = Vector2(1.0, skew_y)
	var by: Vector2 = Vector2(skew_x, 1.0)
	return Transform2D(bx, by, center - (bx * center.x + by * center.y))
