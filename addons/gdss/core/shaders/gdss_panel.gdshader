shader_type canvas_item;
render_mode unshaded;

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

const float EPS = 0.0001;


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
	} else {
		fill_col = u_fill_a;
	}

	vec4 border_col;
	if (u_border_mode == 1) {
		vec2 dir = u_border_p1 - u_border_p0;
		float denom = max(dot(dir, dir), EPS);
		float t = clamp(dot(UV - u_border_p0, dir) / denom, 0.0, 1.0);
		border_col = mix(u_border_a, u_border_b, t);
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
