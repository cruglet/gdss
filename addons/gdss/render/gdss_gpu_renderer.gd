@tool
class_name GdssGpuRenderer
extends GdssRenderer

const _SHADOW_CORNER_SPILL: float = 0.4
const _NONE: Dictionary = {}
static var _shader: Shader = null
static var _blur_shader: Shader = null
static var _shared_materials: Dictionary[int, SharedMaterial] = {}

var canvas_item: RID = RID()
var parent_item: RID = RID()

var _is_blur: bool = false
var _params: Dictionary = _NONE
var _private: ShaderMaterial = null
var _private_params: Dictionary = _NONE
var _shared: SharedMaterial = null
var _bound: ShaderMaterial = null
var _quad: Rect2 = Rect2()
var _xform: Transform2D = Transform2D.IDENTITY
var _emitted: bool = false
var _warned_clip: bool = false
var _fade: GdssTextureFade = null
var _drawn_revision: int = -1
var _drawn_rect: Rect2 = Rect2()
var _drawn_generation: int = -1
var _redraw: Callable


class SharedMaterial extends RefCounted:
	var material: ShaderMaterial = ShaderMaterial.new()
	var key: int
	var is_blur: bool
	var params: Dictionary
	var users: int = 0
	
	func _init(p_key: int, p_shader: Shader, p_is_blur: bool, p_params: Dictionary) -> void:
		key = p_key
		is_blur = p_is_blur
		params = p_params
		params.make_read_only()
		material.shader = p_shader
		for key: StringName in p_params:
			material.set_shader_parameter(key, p_params.get(key))


func _init(redraw: Callable) -> void:
	_redraw = redraw


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	if canvas_item.is_valid():
		RenderingServer.free_rid(canvas_item)
	if _shared != null:
		_shared.users -= 1
		if _shared.users <= 0:
			_shared_materials.erase(_shared.key)


static func shared_material_count() -> int:
	return _shared_materials.size()


func params() -> Dictionary:
	return _params


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
		_is_blur = want_blur
		RenderingServer.canvas_item_set_draw_behind_parent(canvas_item, true)
		RenderingServer.canvas_item_set_copy_to_backbuffer(canvas_item, want_blur, Rect2())
		parent_item = RID()
		_bound = null
	elif _is_blur != want_blur:
		_is_blur = want_blur
		RenderingServer.canvas_item_set_copy_to_backbuffer(canvas_item, want_blur, Rect2())
		_private = null
	if parent_item != to_canvas_item:
		RenderingServer.canvas_item_set_parent(canvas_item, to_canvas_item)
		parent_item = to_canvas_item


func _in_clip_group(node: Node) -> bool:
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
	_release_shared()
	_private = null
	_bound = null
	_params = _NONE
	_emitted = false


func _set_param(key: StringName, value: Variant) -> void:
	_params.set(key, value)


func _commit_params(animating: bool) -> void:
	if animating or not _use_shared():
		_use_private()


func _use_shared() -> bool:
	var key: int = hash([_is_blur, _params])
	if _shared != null and _shared.key == key:
		_params = _shared.params
		_bind(_shared.material)
		return true
	var shared: SharedMaterial = _shared_materials.get(key)
	if shared != null and (shared.is_blur != _is_blur or shared.params != _params):
		return false
	if shared == null:
		shared = SharedMaterial.new(key, _shader_for(_is_blur), _is_blur, _params)
		_shared_materials.set(key, shared)
	shared.users += 1
	_release_shared()
	_shared = shared
	_params = shared.params
	_private = null
	_bind(shared.material)
	return true


func _use_private() -> void:
	_release_shared()
	if _private == null:
		_private = ShaderMaterial.new()
		_private.shader = _shader_for(_is_blur)
		_private_params = {}
	for key: StringName in _params:
		var value: Variant = _params.get(key)
		if not _private_params.has(key) or _private_params.get(key) != value:
			_private_params.set(key, value)
			_private.set_shader_parameter(key, value)
	_bind(_private)


func _release_shared() -> void:
	if _shared == null:
		return
	_shared.users -= 1
	if _shared.users <= 0:
		_shared_materials.erase(_shared.key)
	_shared = null


func _bind(material: ShaderMaterial) -> void:
	if _bound == material:
		return
	_bound = material
	RenderingServer.canvas_item_set_material(canvas_item, material.get_rid())


static func _shader_for(blur: bool) -> Shader:
	return _get_blur_shader() if blur else _get_shared_shader()


func is_current(to_canvas_item: RID, rect: Rect2, revision: int) -> bool:
	return _emitted and parent_item == to_canvas_item and revision == _drawn_revision and rect == _drawn_rect \
		and _drawn_generation == GDSS._redraw_generation and (_fade == null or _fade.tween == null)


func draw(to_canvas_item: RID, rect: Rect2, vals: Dictionary, node: Node, fade_duration: float, revision: int, animating: bool = false) -> void:
	_params = {}
	_drawn_revision = revision
	_drawn_rect = rect
	_drawn_generation = GDSS._redraw_generation
	var bg: Variant = at_blur_quality(vals.get("bg_color", Color.TRANSPARENT))
	var border_raw: Variant = vals.get("border_color", Color.TRANSPARENT)
	var border_src: Variant = at_blur_quality(border_base(border_raw))
	var border_sides: Array = border_side_colors(border_raw)
	var want_blur: bool = bg is GdssBlur or border_src is GdssBlur
	if want_blur and _in_clip_group(node):
		want_blur = false
		if not _warned_clip:
			_warned_clip = true
			push_warning("[GDSS] Blur disabled on %s: a clip_children or CanvasGroup ancestor renders its children into the backbuffer, so the engine binds a solid white screen texture and the blur would draw pure white. Mask without a clip group to keep the blur." % node)
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
	var anti_aliasing: bool = vals.get("anti_aliasing", true)
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
	if not _push_texture_fill(vals, bg, fade_duration, node):
		_push_fill(bg)
	_push_border(border_src, border_sides)
	_commit_params(animating or (_fade != null and _fade.tween != null))
	var xform: Transform2D = skew_transform(rect, vals.get("skew_x", 0.0), vals.get("skew_y", 0.0))
	if not _emitted or quad != _quad or xform != _xform:
		_quad = quad
		_xform = xform
		_emitted = true
		var half: Vector2 = quad.size * 0.5
		RenderingServer.canvas_item_clear(canvas_item)
		RenderingServer.canvas_item_set_transform(canvas_item, xform)
		RenderingServer.canvas_item_add_primitive(canvas_item,
			PackedVector2Array([quad.position, Vector2(quad.end.x, quad.position.y), quad.end, Vector2(quad.position.x, quad.end.y)]),
			PackedColorArray([Color.WHITE]),
			PackedVector2Array([-half, Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)]),
			RID())


static func at_blur_quality(value: Variant) -> Variant:
	if not value is GdssBlur:
		return value
	match GDSS.blur_quality:
		GDSS.BlurQuality.OFF:
			return (value as GdssBlur).tint
		GDSS.BlurQuality.LOW:
			return (value as GdssBlur).to_plain()
	return value


func _push_texture_fill(vals: Dictionary, bg: Variant, duration: float, node: Node) -> bool:
	var src: Variant = vals.get("bg_texture")
	if not (src is GdssTexture or src is Texture2D):
		src = bg
	var target: Texture2D = null
	var aspect: bool = false
	var natural: bool = false
	var nearest: bool = false
	if src is GdssTexture:
		var wrapped: GdssTexture = src
		target = wrapped.texture
		aspect = wrapped.preserve_aspect
		natural = wrapped.repeat
		nearest = wrapped.is_nearest()
	elif src is Texture2D:
		target = src
	var texture: Texture2D = _fade_to(target, duration, node)
	if texture == null:
		return false
	var tint: Variant = vals.get("bg_tint", Color.WHITE)
	var scroll: Variant = vals.get("bg_scroll", Vector2.ZERO)
	var scale: Variant = vals.get("bg_texture_scale", Vector2.ZERO)
	if not scroll is Vector2:
		scroll = Vector2.ZERO
	if not scale is Vector2:
		scale = Vector2.ZERO
	var repeat: bool = natural or scroll != Vector2.ZERO or scale != Vector2.ZERO
	_set_param(&"u_fill_mode", 3)
	_set_param(&"u_tex", null if nearest else texture)
	_set_param(&"u_tex_nearest", texture if nearest else null)
	_set_param(&"u_fill_nearest", 1.0 if nearest else 0.0)
	_set_param(&"u_fill_repeat", 1.0 if repeat else 0.0)
	_set_param(&"u_fill_natural", 1.0 if natural else 0.0)
	_set_param(&"u_fill_fade", _fade.value)
	_set_param(&"u_fill_tint", tint if tint is Color else Color.WHITE)
	_set_param(&"u_fill_scroll", scroll)
	_set_param(&"u_fill_scale", scale)
	_set_param(&"u_fill_aspect", 1.0 if aspect else 0.0)
	_set_param(&"u_fill_a", bg if bg is Color else Color.TRANSPARENT)
	return true


func _fade_to(target: Texture2D, duration: float, node: Node) -> Texture2D:
	if _fade == null:
		if target == null:
			return null
		_fade = GdssTextureFade.new()
	var texture: Texture2D = _fade.texture if target == _fade.target else _fade.fade_to(target, duration, node, _redraw)
	if texture == null and _fade.tween == null:
		_fade = null
	return texture


func _push_fill(bg: Variant) -> void:
	if bg is GdssGradient:
		var grad: GdssGradient = bg as GdssGradient
		_set_param(&"u_fill_a", grad.color_a)
		_set_param(&"u_fill_b", grad.color_b)
		_set_param(&"u_grad_offsets", grad.offsets)
		_set_param(&"u_grad_p0", grad.p0)
		_set_param(&"u_grad_p1", grad.p1)
		_set_param(&"u_fill_mode", grad.mode)
	elif bg is GdssBlur:
		var blur: GdssBlur = bg as GdssBlur
		_set_param(&"u_fill_a", blur.tint)
		_set_param(&"u_fill_glass", Vector4(blur.strength, blur.refraction, blur.highlight, blur.saturation))
		if blur.strength_end != blur.strength:
			_set_param(&"u_fill_mode", 5)
			_set_param(&"u_fill_glass2", Vector4(blur.strength_end, blur.refraction, blur.highlight, blur.saturation))
			_set_param(&"u_grad_offsets", blur.grad_offsets)
			_set_param(&"u_grad_p0", blur.grad_p0)
			_set_param(&"u_grad_p1", blur.grad_p1)
		else:
			_set_param(&"u_fill_mode", 4)
	elif bg is Color:
		_set_param(&"u_fill_mode", 0)
		_set_param(&"u_fill_a", bg as Color)
	else:
		_set_param(&"u_fill_mode", 0)
		_set_param(&"u_fill_a", Color.TRANSPARENT)


func _push_border(border_src: Variant, border_sides: Array) -> void:
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
		_set_param(&"u_border_p0", grad.p0)
		_set_param(&"u_border_p1", grad.p1)
	elif border_src is GdssBlur:
		var blur: GdssBlur = border_src as GdssBlur
		_set_param(&"u_border_a", blur.tint)
		_set_param(&"u_border_glass", Vector4(blur.strength, blur.refraction, blur.highlight, blur.saturation))
		if blur.strength_end != blur.strength:
			_set_param(&"u_border_mode", 3)
			_set_param(&"u_border_glass2", Vector4(blur.strength_end, blur.refraction, blur.highlight, blur.saturation))
			_set_param(&"u_border_p0", blur.grad_p0)
			_set_param(&"u_border_p1", blur.grad_p1)
		else:
			_set_param(&"u_border_mode", 2)
	elif border_src is Color:
		_set_param(&"u_border_mode", 0)
		_set_param(&"u_border_a", border_src as Color)
	else:
		_set_param(&"u_border_mode", 0)
		_set_param(&"u_border_a", Color.TRANSPARENT)
