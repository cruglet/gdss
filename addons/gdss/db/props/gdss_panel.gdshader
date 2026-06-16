shader_type canvas_item;
render_mode unshaded;

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

const float EPS = 0.0001;


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
	} else {
		fill_col = u_fill_a;
	}

	vec4 border_col;
	if (u_border_mode == 1) {
		vec2 dir = u_border_p1 - u_border_p0;
		float denom = max(dot(dir, dir), EPS);
		float t = clamp(dot(UV - u_border_p0, dir) / denom, 0.0, 1.0);
		border_col = mix(u_border_a, u_border_b, t);
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
