shader_type canvas_item;
render_mode unshaded;

uniform sampler2D picture : hint_screen_texture, filter_linear, repeat_disable;
uniform float strength : hint_range(0.0, 1.0) = 0.85;
// A signal fault on the helmet feed: torn scan lines, a rolling bar and snow.
uniform float disturb : hint_range(0.0, 1.0) = 0.0;
// The faceplate mists at its edges with each exhale and clears on the draw.
uniform float mist : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 pixel = SCREEN_PIXEL_SIZE;
	float tick = floor(TIME * 24.0);
	if (disturb > 0.001) {
		float band = floor(uv.y * 54.0);
		float torn = step(1.0 - disturb * 0.45, hash(vec2(band, tick)));
		uv.x += torn * (hash(vec2(band + 3.0, tick)) - 0.5) * 0.05 * disturb;
		uv.y += disturb * disturb * 0.004 * sin(TIME * 41.0);
	}
	vec3 clean = texture(picture, uv).rgb;
	vec2 glass = SCREEN_UV * 2.0 - 1.0;
	float edge = dot(glass, glass);
	// Keep the phosphor image in register with the diver's physical touch targets.
	// At the edge of the glass the red and blue guns drift by only one pixel.
	vec2 bleed = vec2((0.55 + 0.65 * edge + 5.0 * disturb) * pixel.x, 0.0);
	float red = texture(picture, uv - bleed).r;
	float blue = texture(picture, uv + bleed).b;
	vec3 signal = mix(clean, vec3(red, clean.g, blue), 0.65);
	// Breath condenses on the cold faceplate, softening and lifting the rim.
	float fogged = mist * smoothstep(0.55, 1.35, length(glass * vec2(0.9, 1.05)));
	if (fogged > 0.002) {
		vec2 spread = pixel * 7.0;
		vec3 soft = (texture(picture, uv + vec2(spread.x, 0.0)).rgb + texture(picture, uv - vec2(spread.x, 0.0)).rgb
			+ texture(picture, uv + vec2(0.0, spread.y)).rgb + texture(picture, uv - vec2(0.0, spread.y)).rgb) * 0.25;
		signal = mix(signal, soft * 0.9 + vec3(0.018, 0.026, 0.026), fogged * 0.55);
	}
	// Align each scan to whole output pixels. Avoid a moving moiré on small screens.
	float pitch = max(2.0, floor(1.0 / (pixel.y * 240.0) + 0.5));
	float row = mod(floor(FRAGCOORD.y), pitch) / pitch;
	float line = exp(-14.0 * (row - 0.78) * (row - 0.78));
	vec3 mask = 0.975 + 0.025 * cos(2.094395 * (floor(FRAGCOORD.x) + vec3(0.0, 1.0, 2.0)));
	float rim = smoothstep(0.60, 1.32, length(glass * vec2(0.86, 1.0)));
	float grain = fract(sin(dot(floor(FRAGCOORD.xy * 0.64), vec2(21.56, 53.13))
			+ mod(floor(TIME * 8.0), 31.0)) * 4319.65);
	vec3 crt = signal * mask * (1.042 - 0.15 * line) * (1.0 - 0.29 * rim);
	crt += (grain - 0.5) * (0.004 + signal * 0.045 + disturb * 0.09);
	if (disturb > 0.001) {
		float roll = fract(SCREEN_UV.y * 0.7 - TIME * 0.9);
		crt += vec3(0.05, 0.06, 0.055) * disturb * smoothstep(0.0, 0.06, roll) * (1.0 - smoothstep(0.06, 0.16, roll));
		crt *= 1.0 - 0.35 * disturb * step(0.94, hash(vec2(floor(SCREEN_UV.y * 120.0), tick)));
	}
	COLOR = vec4(mix(clean, crt, strength), 1.0);
}
