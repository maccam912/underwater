shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;

void vertex() {
	// Positive X is the snout. The head stays level while the tail beats laterally.
	float tail = clamp((0.29 - VERTEX.x) / 0.85, 0.0, 1.0);
	float wave = TIME * (6.7 + 1.6 * INSTANCE_CUSTOM.g) + INSTANCE_CUSTOM.r * 6.28318 + VERTEX.x * 5.9;
	VERTEX.z += tail * tail * 0.115 * sin(wave);
	NORMAL.x -= NORMAL.z * 0.22 * tail * sin(wave);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.49;
	SPECULAR = 0.52;
}
