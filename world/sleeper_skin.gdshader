shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;

uniform float beat = 1.0;

void vertex() {
	// Positive X is the snout. A slow, heavy sweep travels down to the tail.
	float tail = clamp((1.1 - VERTEX.x) / 3.6, 0.0, 1.0);
	float wave = TIME * 0.95 * beat - VERTEX.x * 1.15;
	VERTEX.z += tail * tail * 0.34 * sin(wave);
	NORMAL.x -= NORMAL.z * 0.25 * tail * cos(wave);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.82;
	SPECULAR = 0.28;
}
