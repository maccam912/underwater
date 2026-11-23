shader_type sky;
render_mode use_debanding;

uniform vec4 deep_tint : source_color = vec4(0.026, 0.073, 0.087, 1.0);
uniform vec4 upper_tint : source_color = vec4(0.106, 0.222, 0.226, 1.0);

void sky() {
	float up = smoothstep(-0.85, 0.90, EYEDIR.y + 0.12 * EYEDIR.z);
	COLOR = mix(deep_tint.rgb, upper_tint.rgb, up);
}
