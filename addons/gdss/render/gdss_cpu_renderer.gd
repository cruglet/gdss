@tool
class_name GdssCpuRenderer
extends GdssRenderer

static var _corner_start_angles: Array[float] = [PI, PI * 1.5, 0.0, PI * 0.5]
static var _rr_cache: Dictionary = {}
static var _tri_cache: Dictionary = {}


static func draw(to_canvas_item: RID, rect: Rect2, vals: Dictionary) -> void:
	var corner_radius: Vector4 = Vector4(vals.get("corner_radius", Vector4i.ZERO))
	var anti_aliasing: bool = vals.get("anti_aliasing", true)
	var aa_size: float = 1.0 if anti_aliasing else 0.0
	var detail: int = max(1, int(vals.get("corner_detail", 8)))
	var skew_x: float = vals.get("skew_x", 0.0)
	var skew_y: float = vals.get("skew_y", 0.0)
	var shadow: Vector4 = Vector4(vals.get("shadow", Vector4i.ZERO))
	var shadow_src: Variant = vals.get("shadow_color", DEFAULT_SHADOW_COLOR)
	if max_side(shadow) > 0.5:
		var shadow_outer: Rect2 = rect.grow_individual(shadow.x, shadow.z, shadow.y, shadow.w)
		var fitted: Vector4 = _fit_corners(corner_radius, rect)
		if shadow_src is GdssGradient:
			_draw_linear_gradient_ring(to_canvas_item, shadow_src as GdssGradient, rect, shadow_outer, fitted, detail, skew_x, skew_y, true)
		elif shadow_src is Texture2D:
			_draw_textured_ring(to_canvas_item, rect, shadow_outer, fitted, shadow_src as Texture2D, detail, skew_x, skew_y, true)
		elif shadow_src is Color:
			_draw_ring_raw(to_canvas_item, rect, shadow_outer, fitted, _fit_corners(corner_radius, shadow_outer), shadow_src as Color, true, detail, skew_x, skew_y)
	var bg: Variant = vals.get("bg_color", Color.TRANSPARENT)
	if bg is GdssGradient:
		var bgrad: GdssGradient = bg as GdssGradient
		if bgrad.mode == 2:
			_draw_radial_gradient_rect(to_canvas_item, bgrad, rect, corner_radius, detail, skew_x, skew_y)
		else:
			_draw_linear_gradient_rect(to_canvas_item, bgrad, rect, corner_radius, detail, skew_x, skew_y)
	elif bg is GdssBlur:
		var blur_tint: Color = (bg as GdssBlur).tint
		if blur_tint.a > 0.0:
			_draw_rect(to_canvas_item, rect, blur_tint, corner_radius, aa_size, detail, skew_x, skew_y)
	elif bg is Texture2D:
		_draw_texture_in_rect(to_canvas_item, bg as Texture2D, rect, corner_radius, detail, skew_x, skew_y)
	elif bg is Color and (bg as Color).a > 0.0:
		_draw_rect(to_canvas_item, rect, bg as Color, corner_radius, aa_size, detail, skew_x, skew_y)
	var border: Vector4 = Vector4(vals.get("border", Vector4i.ZERO))
	var border_raw: Variant = vals.get("border_color", Color.TRANSPARENT)
	var border_src: Variant = border_base(border_raw)
	var border_sides: Array = border_side_colors(border_raw)
	var has_border: bool = border.x > 0 or border.y > 0 or border.z > 0 or border.w > 0
	if has_border:
		var inner_rect: Rect2 = rect.grow_individual(-border.x, -border.z, -border.y, -border.w)
		if inner_rect.has_area():
			if not border_sides.is_empty():
				_draw_ring_sides(to_canvas_item, inner_rect, rect, corner_radius, border_sides, detail, skew_x, skew_y)
			elif border_src is GdssGradient:
				_draw_linear_gradient_ring(to_canvas_item, border_src as GdssGradient, inner_rect, rect, corner_radius, detail, skew_x, skew_y)
			elif border_src is GdssBlur:
				var border_tint: Color = (border_src as GdssBlur).tint
				if border_tint.a > 0.0:
					_draw_ring(to_canvas_item, inner_rect, rect, corner_radius, border_tint, aa_size, detail, skew_x, skew_y)
			elif border_src is Color and (border_src as Color).a > 0.0:
				_draw_ring(to_canvas_item, inner_rect, rect, corner_radius, border_src as Color, aa_size, detail, skew_x, skew_y)


static func _draw_texture_in_rect(to_canvas_item: RID, tex: Texture2D, rect: Rect2, corner_radii: Vector4, detail: int, skew_x: float, skew_y: float) -> void:
	var points: PackedVector2Array = _apply_skew(_get_rounded_rect(rect, _fit_corners(corner_radii, rect), detail), rect, skew_x, skew_y)
	var n: int = points.size()
	var tex_size: Vector2 = tex.get_size()
	var scale: float = maxf(rect.size.x / tex_size.x, rect.size.y / tex_size.y)
	var scaled: Vector2 = tex_size * scale
	var uv_scale: Vector2 = rect.size / scaled
	var uv_offset: Vector2 = (Vector2.ONE - uv_scale) * 0.5
	var uvs: PackedVector2Array
	uvs.resize(n)
	for i: int in n:
		var local: Vector2 = (points.get(i) - rect.position) / rect.size
		uvs.set(i, uv_offset + local * uv_scale)
	RenderingServer.canvas_item_add_polygon(to_canvas_item, points, [Color.WHITE], uvs, tex.get_rid())


static func _draw_textured_ring(to_canvas_item: RID, inner_rect: Rect2, outer_rect: Rect2, corner_radii: Vector4, tex: Texture2D, detail: int, skew_x: float, skew_y: float, fade: bool = false) -> void:
	var outer_fitted: Vector4 = _fit_corners(corner_radii, outer_rect)
	var inner_fitted: Vector4 = _fit_corners(corner_radii, inner_rect)
	var inner_points: PackedVector2Array = _apply_skew(_get_rounded_rect(inner_rect, inner_fitted, detail), inner_rect, skew_x, skew_y)
	var outer_points: PackedVector2Array = _apply_skew(_get_rounded_rect(outer_rect, outer_fitted, detail), outer_rect, skew_x, skew_y)
	var n: int = max(inner_points.size(), outer_points.size())
	for i: int in n:
		var i0: int = i % inner_points.size()
		var i1: int = (i + 1) % inner_points.size()
		var o0: int = i % outer_points.size()
		var o1: int = (i + 1) % outer_points.size()
		var p0: Vector2 = inner_points.get(i0)
		var p1: Vector2 = outer_points.get(o0)
		var p2: Vector2 = outer_points.get(o1)
		var p3: Vector2 = inner_points.get(i1)
		if p0.is_equal_approx(p1) or p0.is_equal_approx(p3) or p1.is_equal_approx(p2) or p2.is_equal_approx(p3) or p0.is_equal_approx(p2) or p1.is_equal_approx(p3):
			continue
		var quad: PackedVector2Array = PackedVector2Array([p0, p1, p2, p3])
		var uvs: PackedVector2Array
		uvs.resize(4)
		var colors: PackedColorArray
		colors.resize(4)
		for j: int in 4:
			uvs.set(j, (quad.get(j) - outer_rect.position) / outer_rect.size)
			var is_outer: bool = j == 1 or j == 2
			colors.set(j, Color(1, 1, 1, 0.0 if (fade and is_outer) else 1.0))
		RenderingServer.canvas_item_add_polygon(to_canvas_item, quad, colors, uvs, tex.get_rid())


static func _sample_grad(c1: Color, c2: Color, offsets: Vector2, t: float) -> Color:
	var span: float = maxf(offsets.y - offsets.x, 0.0001)
	return c1.lerp(c2, clampf((t - offsets.x) / span, 0.0, 1.0))


static func _draw_linear_gradient_rect(to_canvas_item: RID, grad: GdssGradient, rect: Rect2, corner_radii: Vector4, detail: int, skew_x: float, skew_y: float) -> void:
	var c1: Color = grad.color_a
	var c2: Color = grad.color_b
	var angle: float = grad.p0.angle_to_point(grad.p1)
	var points: PackedVector2Array = _apply_skew(_get_rounded_rect(rect, _fit_corners(corner_radii, rect), detail), rect, skew_x, skew_y)
	var dir: Vector2 = Vector2(cos(angle), sin(angle))
	var colors: PackedColorArray
	colors.resize(points.size())
	for i: int in points.size():
		var p: Vector2 = points.get(i)
		var t: float = ((p - rect.position) / rect.size).dot(dir) * 0.5 + 0.5
		colors.set(i, _sample_grad(c1, c2, grad.offsets, t))
	RenderingServer.canvas_item_add_polygon(to_canvas_item, points, colors)


static func _draw_radial_gradient_rect(to_canvas_item: RID, grad: GdssGradient, rect: Rect2, corner_radii: Vector4, detail: int, skew_x: float, skew_y: float) -> void:
	var perimeter: PackedVector2Array = _apply_skew(_get_rounded_rect(rect, _fit_corners(corner_radii, rect), detail), rect, skew_x, skew_y)
	var n: int = perimeter.size()
	if n < 3:
		return
	var radius: float = maxf((grad.p1 - grad.p0).length(), 0.0001)
	var center: Vector2 = rect.position + grad.p0 * rect.size
	var verts: PackedVector2Array
	var cols: PackedColorArray
	var indices: PackedInt32Array
	verts.resize(n + 1)
	cols.resize(n + 1)
	verts.set(0, center)
	cols.set(0, _sample_grad(grad.color_a, grad.color_b, grad.offsets, 0.0))
	for i: int in n:
		verts.set(i + 1, perimeter.get(i))
		var uv: Vector2 = (perimeter.get(i) - rect.position) / rect.size
		cols.set(i + 1, _sample_grad(grad.color_a, grad.color_b, grad.offsets, (uv - grad.p0).length() / radius))
	for i: int in n:
		indices.append_array([0, i + 1, (i + 1) % n + 1])
	RenderingServer.canvas_item_add_triangle_array(to_canvas_item, indices, verts, cols)


static func _draw_linear_gradient_ring(to_canvas_item: RID, grad: GdssGradient, inner_rect: Rect2, outer_rect: Rect2, corner_radii: Vector4, detail: int, skew_x: float, skew_y: float, fade: bool = false) -> void:
	var c1: Color = grad.color_a
	var c2: Color = grad.color_b
	var angle: float = grad.p0.angle_to_point(grad.p1)
	var outer_fitted: Vector4 = _fit_corners(corner_radii, outer_rect)
	var inner_fitted: Vector4 = _fit_corners(corner_radii, inner_rect)
	var inner_points: PackedVector2Array = _apply_skew(_get_rounded_rect(inner_rect, inner_fitted, detail), inner_rect, skew_x, skew_y)
	var outer_points: PackedVector2Array = _apply_skew(_get_rounded_rect(outer_rect, outer_fitted, detail), outer_rect, skew_x, skew_y)
	var dir: Vector2 = Vector2(cos(angle), sin(angle))
	var n: int = max(inner_points.size(), outer_points.size())
	for i: int in n:
		var i0: int = i % inner_points.size()
		var i1: int = (i + 1) % inner_points.size()
		var o0: int = i % outer_points.size()
		var o1: int = (i + 1) % outer_points.size()
		var p0: Vector2 = inner_points.get(i0)
		var p1: Vector2 = outer_points.get(o0)
		var p2: Vector2 = outer_points.get(o1)
		var p3: Vector2 = inner_points.get(i1)
		var quad: PackedVector2Array = PackedVector2Array([p0, p1, p2, p3])
		var quad_colors: PackedColorArray
		quad_colors.resize(4)
		for j: int in 4:
			var p: Vector2 = quad.get(j)
			var t: float = ((p - outer_rect.position) / outer_rect.size).dot(dir) * 0.5 + 0.5
			var col: Color = _sample_grad(c1, c2, grad.offsets, t)
			var is_outer: bool = j == 1 or j == 2
			if fade and is_outer:
				col.a = 0.0
			quad_colors.set(j, col)
		RenderingServer.canvas_item_add_polygon(to_canvas_item, quad, quad_colors)


static func _draw_rect(to_canvas_item: RID, rect: Rect2, color: Color, corner_radii: Vector4, aa: float, detail: int, skew_x: float, skew_y: float) -> void:
	if corner_radii == Vector4.ZERO and aa == 0.0:
		var points: PackedVector2Array = _apply_skew(_get_rounded_rect(rect, corner_radii, detail), rect, skew_x, skew_y)
		RenderingServer.canvas_item_add_polygon(to_canvas_item, points, [color])
		return
	
	var fitted: Vector4 = _fit_corners(corner_radii, rect)
	
	if aa > 0.0:
		var inner_rect: Rect2 = rect.grow(-aa)
		var inner_fitted: Vector4 = _fit_corners(corner_radii, inner_rect)
		_draw_ring_raw(to_canvas_item, inner_rect, rect, inner_fitted, fitted, color, true, detail, skew_x, skew_y)
		rect = inner_rect
		fitted = inner_fitted
	
	var points: PackedVector2Array = _apply_skew(_get_rounded_rect(rect, fitted, detail), rect, skew_x, skew_y)
	RenderingServer.canvas_item_add_polygon(to_canvas_item, points, [color])


static func _draw_ring(to_canvas_item: RID, inner_rect: Rect2, outer_rect: Rect2, corner_radii: Vector4, color: Color, aa: float, detail: int, skew_x: float, skew_y: float) -> void:
	var outer_fitted: Vector4 = _fit_corners(corner_radii, outer_rect)
	var inner_fitted: Vector4 = _fit_corners(corner_radii, inner_rect)
	_draw_ring_raw(to_canvas_item, inner_rect, outer_rect, inner_fitted, outer_fitted, color, false, detail, skew_x, skew_y)


static func _draw_ring_raw(to_canvas_item: RID, inner_rect: Rect2, outer_rect: Rect2, inner_radii: Vector4, outer_radii: Vector4, color: Color, fade: bool, detail: int, skew_x: float, skew_y: float) -> void:
	var inner_points: PackedVector2Array = _apply_skew(_get_rounded_rect(inner_rect, inner_radii, detail), inner_rect, skew_x, skew_y)
	var outer_points: PackedVector2Array = _apply_skew(_get_rounded_rect(outer_rect, outer_radii, detail), outer_rect, skew_x, skew_y)
	var all_points: PackedVector2Array = inner_points + outer_points
	var indices: PackedInt32Array = _triangulate_ring(inner_points.size(), outer_points.size())
	
	var colors: PackedColorArray
	if fade:
		colors.resize(all_points.size())
		for i: int in inner_points.size():
			colors.set(i, color)
		for i: int in outer_points.size():
			colors.set(inner_points.size() + i, Color(color.r, color.g, color.b, 0.0))
	else:
		colors = [color]
	
	RenderingServer.canvas_item_add_triangle_array(to_canvas_item, indices, all_points, colors)


static func _draw_ring_sides(to_canvas_item: RID, inner_rect: Rect2, outer_rect: Rect2, corner_radii: Vector4, colors: Array, detail: int, skew_x: float, skew_y: float) -> void:
	var outer_fitted: Vector4 = _fit_corners(corner_radii, outer_rect)
	var inner_fitted: Vector4 = _match_corner_counts(_fit_corners(corner_radii, inner_rect), outer_fitted)
	var inner_points: PackedVector2Array = _apply_skew(_get_rounded_rect(inner_rect, inner_fitted, detail), inner_rect, skew_x, skew_y)
	var outer_points: PackedVector2Array = _apply_skew(_get_rounded_rect(outer_rect, outer_fitted, detail), outer_rect, skew_x, skew_y)
	var count: int = outer_points.size()
	if inner_points.size() != count:
		return
	var splits: PackedInt32Array = _corner_splits(outer_fitted, detail)
	var spans: Array[Vector2i] = [
		Vector2i(splits.get(3), splits.get(0)),
		Vector2i(splits.get(1), splits.get(2)),
		Vector2i(splits.get(0), splits.get(1)),
		Vector2i(splits.get(2), splits.get(3)),
	]
	for side: int in 4:
		var color: Color = colors.get(side)
		if color.a <= 0.0:
			continue
		_draw_ring_span(to_canvas_item, inner_points, outer_points, spans.get(side), count, color)


static func _draw_ring_span(to_canvas_item: RID, inner_points: PackedVector2Array, outer_points: PackedVector2Array, span: Vector2i, count: int, color: Color) -> void:
	var quads: int = posmod(span.y - span.x, count)
	var verts: PackedVector2Array
	var indices: PackedInt32Array
	for i: int in quads:
		var near: int = (span.x + i) % count
		var far: int = (span.x + i + 1) % count
		var base: int = verts.size()
		verts.append_array(PackedVector2Array([inner_points.get(near), outer_points.get(near), outer_points.get(far), inner_points.get(far)]))
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	if indices.is_empty():
		return
	RenderingServer.canvas_item_add_triangle_array(to_canvas_item, indices, verts, PackedColorArray([color]))


static func _corner_splits(radii: Vector4, detail: int) -> PackedInt32Array:
	var splits: PackedInt32Array
	var index: int = 0
	for corner: int in 4:
		var points: int = 1 if radii[corner] == 0.0 else detail + 1
		splits.append(index + points / 2)
		index += points
	return splits


static func _match_corner_counts(inner: Vector4, outer: Vector4) -> Vector4:
	return Vector4(
		maxf(inner.x, 0.001) if outer.x > 0.0 else 0.0,
		maxf(inner.y, 0.001) if outer.y > 0.0 else 0.0,
		maxf(inner.z, 0.001) if outer.z > 0.0 else 0.0,
		maxf(inner.w, 0.001) if outer.w > 0.0 else 0.0,
	)


static func _triangulate_ring(inner_size: int, outer_size: int) -> PackedInt32Array:
	var key: int = inner_size * 100003 + outer_size
	if _tri_cache.has(key):
		return _tri_cache.get(key)
	var indices: PackedInt32Array
	var total: int = max(inner_size, outer_size)
	for i: int in total:
		var i0: int = i % inner_size
		var i1: int = (i + 1) % inner_size
		var o0: int = i % outer_size + inner_size
		var o1: int = (i + 1) % outer_size + inner_size
		indices.append_array([i0, o0, o1, i0, o1, i1])
	_tri_cache.set(key, indices)
	return indices


static func _get_rounded_rect(rect: Rect2, corner_radii: Vector4, detail: int = 8) -> PackedVector2Array:
	var key: int = int(rect.position.x * 100.0)
	key = key * 92821 + int(rect.position.y * 100.0)
	key = key * 92821 + int(rect.size.x * 100.0)
	key = key * 92821 + int(rect.size.y * 100.0)
	key = key * 92821 + int(corner_radii.x * 100.0)
	key = key * 92821 + int(corner_radii.y * 100.0)
	key = key * 92821 + int(corner_radii.z * 100.0)
	key = key * 92821 + int(corner_radii.w * 100.0)
	key = key * 92821 + detail
	if _rr_cache.has(key):
		return _rr_cache.get(key)
	var corner_centers: Array[Vector2] = [
		rect.position + Vector2(corner_radii[0], corner_radii[0]),
		Vector2(rect.end.x, rect.position.y) + Vector2(-corner_radii[1], corner_radii[1]),
		rect.end + Vector2(-corner_radii[2], -corner_radii[2]),
		Vector2(rect.position.x, rect.end.y) + Vector2(corner_radii[3], -corner_radii[3]),
	]
	
	var points: PackedVector2Array
	for corner_idx: int in 4:
		var radius: float = corner_radii[corner_idx]
		if radius == 0.0:
			match corner_idx:
				0: points.append(rect.position)
				1: points.append(Vector2(rect.end.x, rect.position.y))
				2: points.append(rect.end)
				3: points.append(Vector2(rect.position.x, rect.end.y))
		else:
			for i: int in range(detail + 1):
				var theta: float = _corner_start_angles.get(corner_idx) + (PI * 0.5) * i / detail
				points.append(corner_centers.get(corner_idx) + Vector2(cos(theta), sin(theta)) * radius)
	if _rr_cache.size() > 2048:
		_rr_cache.clear()
	_rr_cache.set(key, points)
	return points


static func _apply_skew(points: PackedVector2Array, rect: Rect2, skew_x: float, skew_y: float) -> PackedVector2Array:
	if skew_x == 0.0 and skew_y == 0.0:
		return points
	var result: PackedVector2Array = points
	for i: int in result.size():
		var p: Vector2 = result.get(i)
		var t: Vector2 = (p - rect.position) / rect.size
		result.set(i, Vector2(
			p.x + skew_x * (t.y - 0.5) * rect.size.y,
			p.y + skew_y * (t.x - 0.5) * rect.size.x
		))
	return result


static func _fit_corners(corners: Vector4, rect: Rect2) -> Vector4:
	var scale: float = min(
		1.0,
		rect.size.x / maxf(corners[0] + corners[1], 0.001),
		rect.size.y / maxf(corners[1] + corners[2], 0.001),
		rect.size.x / maxf(corners[2] + corners[3], 0.001),
		rect.size.y / maxf(corners[3] + corners[0], 0.001),
	)
	return Vector4(
		maxf(0.0, corners[0] * scale - 0.001),
		maxf(0.0, corners[1] * scale - 0.001),
		maxf(0.0, corners[2] * scale - 0.001),
		maxf(0.0, corners[3] * scale - 0.001),
	)
