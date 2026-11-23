shader_type canvas_item;
render_mode unshaded;
uniform float strength = 0.9;

void fragment() {
	vec2 from_center = (UV - vec2(0.5)) * 2.0;
	float rim = smoothstep(0.71, 1.31, length(from_center * vec2(0.86, 1.0)));
	float seed = dot(floor(FRAGCOORD.xy * 0.7), vec2(31.23, 57.89)) + mod(floor(TIME * 8.0), 17.0);
	float grain = fract(sin(seed) * 4395.65);
	// Black density grain keeps the unlit water black.
	COLOR = vec4(0.005, 0.007, 0.006, strength * (rim * 0.43 + grain * 0.033));
}
