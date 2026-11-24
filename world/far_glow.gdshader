shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled;

// A small lamp seen a long way off through dark water: a hard core, a soft
// scattering halo and a faint vertical smear from suspended particles.
uniform vec4 tint : source_color = vec4(0.72, 0.86, 0.80, 1.0);
uniform float level = 0.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float core = exp(-r * r * 70.0);
	float halo = pow(max(1.0 - r, 0.0), 3.6) * 0.42;
	float smear = exp(-p.x * p.x * 300.0) * pow(max(1.0 - abs(p.y), 0.0), 2.0) * 0.1;
	ALBEDO = tint.rgb * (core * 2.2 + halo + smear) * level;
	ALPHA = 1.0;
}
