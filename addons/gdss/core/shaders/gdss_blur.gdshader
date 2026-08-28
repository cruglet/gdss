shader_type canvas_item;
render_mode unshaded;

// The liquid-glass refraction (sample-scaling lens + edge glow) is ported from
// OverShifted/LiquidGlass (MIT): https://github.com/OverShifted/LiquidGlass

uniform vec2 u_size = vec2(100.0, 40.0);
// Per-side quad padding (left, right, top, bottom) that holds the shadow.
uniform vec4 u_pad = vec4(0.0);
uniform vec4 u_corner_radius = vec4(0.0);
uniform vec4 u_border_widths = vec4(0.0);
uniform vec4 u_shadow = vec4(0.0);
uniform float u_aa = 1.0;

uniform int u_fill_mode = 0;
uniform vec4 u_fill_a : source_color = vec4(1.0);
uniform vec4 u_fill_b : source_color = vec4(0.0);
uniform vec2 u_grad_p0 = vec2(0.0, 0.5);
uniform vec2 u_grad_p1 = vec2(1.0, 0.5);
uniform vec2 u_grad_offsets = vec2(0.0, 1.0);

uniform int u_border_mode = 0;
uniform vec4 u_border_a : source_color = vec4(0.0);
uniform vec4 u_border_b : source_color = vec4(0.0);
uniform vec2 u_border_p0 = vec2(0.0, 0.5);
uniform vec2 u_border_p1 = vec2(1.0, 0.5);
uniform vec4 u_border_left : source_color = vec4(0.0);
uniform vec4 u_border_right : source_color = vec4(0.0);
uniform vec4 u_border_top : source_color = vec4(0.0);
uniform vec4 u_border_bottom : source_color = vec4(0.0);

uniform vec4 u_shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.4);
uniform sampler2D u_tex : source_color, hint_default_white;

uniform sampler2D u_screen : hint_screen_texture, filter_linear;
uniform vec4 u_fill_glass = vec4(4.0, 0.0, 0.0, 1.0);
uniform vec4 u_border_glass = vec4(4.0, 0.0, 0.0, 1.0);
uniform vec4 u_fill_glass2 = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 u_border_glass2 = vec4(0.0, 0.0, 0.0, 1.0);

// Lens falloff f(x) = 1 - b * (c * e)^(-d*x - a), raised to u_lens_power. Tuned
// to OverShifted/LiquidGlass defaults: small near the rim, ~1 in the centre.
uniform float u_lens_a = 0.7;
uniform float u_lens_b = 2.3;
uniform float u_lens_c = 5.2;
uniform float u_lens_d = 6.9;
uniform float u_lens_power = 3.0;

const float EPS = 0.0001;
const vec3 LUMA = vec3(0.299, 0.587, 0.114);
const int BLUR_TAPS = 24;
const float GOLDEN_ANGLE = 2.39996323;

// The blur is a raw golden-angle disk convolution at base screen resolution -
// no screen-texture mipmaps, whose partial-copy generation is position- and
// zoom-dependent in the editor. Radius and refraction offsets track the canvas
// scale so a zoomed 2D view keeps the blur proportional to the content.
varying float v_canvas_scale;


void vertex() {
	v_canvas_scale = length(vec2(CANVAS_MATRIX[0].x, CANVAS_MATRIX[0].y));
}


// How far past each edge the point sits, measured from the corner circle's centre, with
// that corner's radius in z. Its two components also name the side a point belongs to:
// the larger one wins, which splits every corner down its 45-degree diagonal.
vec3 box_q(vec2 p, vec2 b, vec4 r) {
	r.xy = (p.x > 0.0) ? r.xy : r.zw;
	r.x = (p.y > 0.0) ? r.x : r.y;
	return vec3(abs(p) - b + r.x, r.x);
}


float sd_box(vec3 q) {
	return min(max(q.x, q.y), 0.0) + length(max(q.xy, vec2(0.0))) - q.z;
}


vec4 sample_gradient(vec4 ca, vec4 cb, vec2 offsets, float t) {
	float span = max(offsets.y - offsets.x, EPS);
	float k = clamp((t - offsets.x) / span, 0.0, 1.0);
	return mix(ca, cb, k);
}


float lens_f(float x) {
	return 1.0 - u_lens_b * pow(u_lens_c * E, -u_lens_d * x - u_lens_a);
}


float glow_sweep(vec2 uv) {
	return sin(atan(uv.y * 2.0 - 1.0, uv.x * 2.0 - 1.0) - 0.5);
}


// Backdrop glass: blurs and tints what is behind the panel. With g = (blur,
// refraction, highlight, saturation) carrying only blur it is a plain frost.
// Refraction scales the sampled position toward the shape's centre by lens_f()
// of the edge depth, so the backdrop bends and magnifies through the rim like
// real liquid glass; highlight adds the swept edge glow.
vec4 glass(vec2 screen_uv, vec2 uv, vec2 p, vec2 b, float d, vec4 tint, vec4 g, vec2 px) {
	float reach = max(min(b.x, b.y), EPS);
	float dist = clamp(-d / reach, 0.0, 1.0);
	float s = pow(clamp(lens_f(dist), 0.0, 1.0), u_lens_power);
	vec2 warp_px = p * (s - 1.0) * g.y * px * v_canvas_scale;
	vec2 base = screen_uv + warp_px;
	vec2 disp = warp_px * 0.04;
	float radius = clamp(exp2(g.x) * 0.5 * v_canvas_scale, 0.0, 48.0);
	vec2 frag = screen_uv / px;
	float jitter = fract(52.9829189 * fract(0.06711056 * frag.x + 0.00583715 * frag.y));
	vec3 backdrop = vec3(0.0);
	for (int i = 0; i < BLUR_TAPS; i++) {
		float fi = float(i);
		float r = radius * sqrt((fi + 0.5) / float(BLUR_TAPS));
		float a = (fi + jitter) * GOLDEN_ANGLE;
		vec2 off = vec2(cos(a), sin(a)) * r * px;
		backdrop.r += texture(u_screen, base + off - disp).r;
		backdrop.g += texture(u_screen, base + off).g;
		backdrop.b += texture(u_screen, base + off + disp).b;
	}
	backdrop /= float(BLUR_TAPS);

	float luma = dot(backdrop, LUMA);
	backdrop = mix(vec3(luma), backdrop, g.w);

	vec3 c = mix(backdrop, tint.rgb, tint.a);
	float glow = glow_sweep(uv) * g.z * smoothstep(0.06, 0.0, dist);
	c *= (1.0 + glow);
	return vec4(c, 1.0);
}


void fragment() {
	vec2 half_size = u_size * 0.5 - vec2(u_pad.x + u_pad.y, u_pad.z + u_pad.w) * 0.5;
	// Uneven padding pushes the panel off the quad's centre; p stays panel-relative.
	vec2 p = (UV - 0.5) * u_size - vec2(u_pad.x - u_pad.y, u_pad.z - u_pad.w) * 0.5;

	vec2 full = half_size * 2.0;
	vec4 cr = u_corner_radius;
	float fit = min(1.0, min(
		min(full.x / max(cr.x + cr.y, EPS), full.y / max(cr.y + cr.z, EPS)),
		min(full.x / max(cr.z + cr.w, EPS), full.y / max(cr.w + cr.x, EPS))));
	cr *= fit;
	vec4 ordered_radius = vec4(cr.z, cr.y, cr.w, cr.x);

	vec3 q_outer = box_q(p, half_size, ordered_radius);
	float d_outer = sd_box(q_outer);
	float aa = max(u_aa * fwidth(d_outer), EPS);

	vec2 inner_center = vec2((u_border_widths.x - u_border_widths.y) * 0.5,
							 (u_border_widths.z - u_border_widths.w) * 0.5);
	vec2 inner_half = max(half_size - vec2((u_border_widths.x + u_border_widths.y) * 0.5,
										   (u_border_widths.z + u_border_widths.w) * 0.5), vec2(EPS));
	vec2 inner_full = inner_half * 2.0;
	vec4 icr = u_corner_radius;
	float ifit = min(1.0, min(
		min(inner_full.x / max(icr.x + icr.y, EPS), inner_full.y / max(icr.y + icr.z, EPS)),
		min(inner_full.x / max(icr.z + icr.w, EPS), inner_full.y / max(icr.w + icr.x, EPS))));
	icr *= ifit;
	vec4 inner_radius = vec4(icr.z, icr.y, icr.w, icr.x);
	float d_inner = sd_box(box_q(p - inner_center, inner_half, inner_radius));

	vec4 fill_col;
	if (u_fill_mode == 1) {
		vec2 dir = u_grad_p1 - u_grad_p0;
		float denom = max(dot(dir, dir), EPS);
		float t = clamp(dot(UV - u_grad_p0, dir) / denom, 0.0, 1.0);
		fill_col = sample_gradient(u_fill_a, u_fill_b, u_grad_offsets, t);
	} else if (u_fill_mode == 2) {
		float t = clamp(length(UV - u_grad_p0)
			/ max(length(u_grad_p1 - u_grad_p0), EPS), 0.0, 1.0);
		fill_col = sample_gradient(u_fill_a, u_fill_b, u_grad_offsets, t);
	} else if (u_fill_mode == 3) {
		fill_col = texture(u_tex, UV);
	} else if (u_fill_mode == 4) {
		fill_col = glass(SCREEN_UV, UV, p, half_size, d_outer, u_fill_a, u_fill_glass, SCREEN_PIXEL_SIZE);
	} else if (u_fill_mode == 5) {
		vec2 dir = u_grad_p1 - u_grad_p0;
		float denom = max(dot(dir, dir), EPS);
		float t = clamp(dot(UV - u_grad_p0, dir) / denom, 0.0, 1.0);
		float span = max(u_grad_offsets.y - u_grad_offsets.x, EPS);
		float k = clamp((t - u_grad_offsets.x) / span, 0.0, 1.0);
		vec4 g = vec4(mix(u_fill_glass.x, u_fill_glass2.x, k), u_fill_glass.yzw);
		fill_col = glass(SCREEN_UV, UV, p, half_size, d_outer, u_fill_a, g, SCREEN_PIXEL_SIZE);
	} else {
		fill_col = u_fill_a;
	}

	vec4 border_col;
	if (u_border_mode == 1) {
		vec2 dir = u_border_p1 - u_border_p0;
		float denom = max(dot(dir, dir), EPS);
		float t = clamp(dot(UV - u_border_p0, dir) / denom, 0.0, 1.0);
		border_col = mix(u_border_a, u_border_b, t);
	} else if (u_border_mode == 2) {
		border_col = glass(SCREEN_UV, UV, p, half_size, d_outer, u_border_a, u_border_glass, SCREEN_PIXEL_SIZE);
	} else if (u_border_mode == 3) {
		vec2 dir = u_border_p1 - u_border_p0;
		float denom = max(dot(dir, dir), EPS);
		float t = clamp(dot(UV - u_border_p0, dir) / denom, 0.0, 1.0);
		vec4 g = vec4(mix(u_border_glass.x, u_border_glass2.x, t), u_border_glass.yzw);
		border_col = glass(SCREEN_UV, UV, p, half_size, d_outer, u_border_a, g, SCREEN_PIXEL_SIZE);
	} else if (u_border_mode == 4) {
		border_col = (q_outer.x > q_outer.y)
			? (p.x < 0.0 ? u_border_left : u_border_right)
			: (p.y < 0.0 ? u_border_top : u_border_bottom);
	} else {
		border_col = u_border_a;
	}

	float fill_mask = 1.0 - smoothstep(-aa, aa, d_inner);
	float panel_mask = 1.0 - smoothstep(-aa, aa, d_outer);
	float border_mask = clamp(panel_mask - fill_mask, 0.0, 1.0);

	// Straight-alpha source-over throughout: the border sits on the fill, and both sit on
	// the shadow. Blending the layers by coverage alone would tint a see-through panel
	// with whatever is underneath it.
	float fill_a = fill_col.a * fill_mask;
	float border_a = border_col.a * border_mask;
	float panel_a = border_a + fill_a * (1.0 - border_a);
	vec3 panel_rgb = panel_a > EPS
		? (border_col.rgb * border_a + fill_col.rgb * fill_a * (1.0 - border_a)) / panel_a
		: fill_col.rgb;
	vec4 col = vec4(panel_rgb, panel_a);

	if (max(max(u_shadow.x, u_shadow.y), max(u_shadow.z, u_shadow.w)) > 0.5) {
		// The reach in the fragment's outward direction blends the two side extents that
		// meet at that corner, weighted by the squared direction so an even shadow keeps
		// its radius and a side left at 0 fades out instead of cutting off.
		vec2 outward = max(q_outer.xy, vec2(0.0));
		vec2 dir = outward / max(length(outward), EPS);
		vec2 ext = vec2(p.x < 0.0 ? u_shadow.x : u_shadow.y, p.y < 0.0 ? u_shadow.z : u_shadow.w);
		float reach = dot(dir * dir, ext);
		float shadow_alpha = 1.0 - smoothstep(0.0, 1.0, d_outer / max(reach, EPS));
		shadow_alpha *= u_shadow_color.a * (1.0 - panel_mask);
		float out_a = col.a + shadow_alpha * (1.0 - col.a);
		col = vec4(out_a > EPS
			? (col.rgb * col.a + u_shadow_color.rgb * shadow_alpha * (1.0 - col.a)) / out_a
			: col.rgb, out_a);
	}

	COLOR = col;
}
