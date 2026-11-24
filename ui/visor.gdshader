shader_type canvas_item;
render_mode unshaded;

uniform sampler2D picture : hint_screen_texture, filter_linear, repeat_disable;
uniform float strength : hint_range(0.0, 1.0) = 0.85;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 pixel = SCREEN_PIXEL_SIZE;
	vec3 clean = texture(picture, uv).rgb;
	vec2 glass = uv * 2.0 - 1.0;
	float edge = dot(glass, glass);
	// Keep the phosphor image in register with the diver's physical touch targets.
	// At the edge of the glass the red and blue guns drift by only one pixel.
	vec2 bleed = vec2((0.55 + 0.65 * edge) * pixel.x, 0.0);
	float red = texture(picture, uv - bleed).r;
	float blue = texture(picture, uv + bleed).b;
	vec3 signal = mix(clean, vec3(red, clean.g, blue), 0.65);
	// Align each scan to whole output pixels. Avoid a moving moiré on small screens.
	float pitch = max(2.0, floor(1.0 / (pixel.y * 240.0) + 0.5));
	float row = mod(floor(FRAGCOORD.y), pitch) / pitch;
	float line = exp(-14.0 * (row - 0.78) * (row - 0.78));
	vec3 mask = 0.975 + 0.025 * cos(2.094395 * (floor(FRAGCOORD.x) + vec3(0.0, 1.0, 2.0)));
	float rim = smoothstep(0.60, 1.32, length(glass * vec2(0.86, 1.0)));
	float grain = fract(sin(dot(floor(FRAGCOORD.xy * 0.64), vec2(21.56, 53.13))
			+ mod(floor(TIME * 8.0), 31.0)) * 4319.65);
	vec3 crt = signal * mask * (1.042 - 0.15 * line) * (1.0 - 0.29 * rim);
	crt += (grain - 0.5) * (0.004 + signal * 0.045);
	COLOR = vec4(mix(clean, crt, strength), 1.0);
}
