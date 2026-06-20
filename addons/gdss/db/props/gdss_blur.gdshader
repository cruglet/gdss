shader_type canvas_item;
render_mode unshaded;

// The liquid-glass refraction (sample-scaling lens + edge glow) is ported from
// OverShifted/LiquidGlass (MIT): https://github.com/OverShifted/LiquidGlass

uniform vec2 u_size = vec2(100.0, 40.0);
uniform vec2 u_pad = vec2(0.0);
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

uniform vec4 u_shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.4);
uniform sampler2D u_tex : source_color, hint_default_white;

uniform sampler2D u_screen : hint_screen_texture, filter_linear_mipmap;
uniform vec4 u_fill_glass = vec4(4.0, 0.0, 0.0, 1.0);
uniform vec4 u_border_glass = vec4(4.0, 0.0, 0.0, 1.0);

// Lens falloff f(x) = 1 - b * (c * e)^(-d*x - a), raised to u_lens_power. Tuned
// to OverShifted/LiquidGlass defaults: small near the rim, ~1 in the centre.
uniform float u_lens_a = 0.7;
uniform float u_lens_b = 2.3;
uniform float u_lens_c = 5.2;
uniform float u_lens_d = 6.9;
uniform float u_lens_power = 3.0;

const float EPS = 0.0001;
const vec3 LUMA = vec3(0.299, 0.587, 0.114);


float sd_round_box(vec2 p, vec2 b, vec4 r) {
	r.xy = (p.x > 0.0) ? r.xy : r.zw;
	r.x = (p.y > 0.0) ? r.x : r.y;
	vec2 q = abs(p) - b + r.x;
	return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r.x;
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
	vec2 warp = p * (s - 1.0) * g.y;
	vec2 base = screen_uv + warp * px;
	vec2 disp = warp * px * 0.04;
	vec3 backdrop;
	backdrop.r = textureLod(u_screen, base - disp, g.x).r;
	backdrop.g = textureLod(u_screen, base, g.x).g;
	backdrop.b = textureLod(u_screen, base + disp, g.x).b;

	float luma = dot(backdrop, LUMA);
	backdrop = mix(vec3(luma), backdrop, g.w);

	vec3 c = mix(backdrop, tint.rgb, tint.a);
	float glow = glow_sweep(uv) * g.z * smoothstep(0.06, 0.0, dist);
	c *= (1.0 + glow);
	return vec4(c, 1.0);
}


void fragment() {
	vec2 half_size = u_size * 0.5 - u_pad;
	vec2 p = (UV - 0.5) * u_size;

	vec2 full = half_size * 2.0;
	vec4 cr = u_corner_radius;
	float fit = min(1.0, min(
		min(full.x / max(cr.x + cr.y, EPS), full.y / max(cr.y + cr.z, EPS)),
		min(full.x / max(cr.z + cr.w, EPS), full.y / max(cr.w + cr.x, EPS))));
	cr *= fit;
	vec4 ordered_radius = vec4(cr.z, cr.y, cr.w, cr.x);

	float d_outer = sd_round_box(p, half_size, ordered_radius);
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
	float d_inner = sd_round_box(p - inner_center, inner_half, inner_radius);

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
	} else {
		border_col = u_border_a;
	}

	float fill_mask = 1.0 - smoothstep(-aa, aa, d_inner);
	float panel_mask = 1.0 - smoothstep(-aa, aa, d_outer);
	float border_mask = clamp(panel_mask - fill_mask, 0.0, 1.0);

	vec4 col = fill_col * fill_mask;
	col = mix(col, border_col, border_mask * border_col.a);
	col.a = max(fill_col.a * fill_mask, border_col.a * border_mask);

	float shadow_size = (u_shadow.x + u_shadow.y + u_shadow.z + u_shadow.w) * 0.25;
	if (shadow_size > 0.5) {
		float shadow_alpha = (1.0 - smoothstep(0.0, shadow_size, d_outer)) * u_shadow_color.a;
		shadow_alpha *= (1.0 - panel_mask);
		col = mix(vec4(u_shadow_color.rgb, shadow_alpha), col, col.a);
		col.a = max(col.a, shadow_alpha);
	}

	COLOR = col;
}
