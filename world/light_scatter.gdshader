shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(0.55, 0.76, 0.65, 1.0);
uniform float density = 0.19;

void fragment() {
	// The sprite is a thin veil of suspended particles around the work light.
	vec2 radial = UV * 2.0 - 1.0;
	float radius = length(radial);
	float glow = pow(max(1.0 - radius, 0.0), 3.7) * density;
	// Fall off to black in the source color so the additive veil has no
	// visible square edge on the Compatibility renderer.
	ALBEDO = tint.rgb * glow;
	ALPHA = 1.0;
}
