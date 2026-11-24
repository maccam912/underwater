shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

uniform sampler2D enamel : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D wear : repeat_enable, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);

varying vec3 part_position;
varying vec3 part_size;
varying vec3 part_normal;
varying vec2 tile_offset;

void vertex() {
	part_size = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	part_position = VERTEX * part_size;
	part_normal = NORMAL / max(part_size, vec3(0.0001));
	tile_offset = fract(float(INSTANCE_ID) * vec2(0.37, 0.63)) + vec2(0.31, 0.17);
}

void fragment() {
	vec3 n = abs(normalize(part_normal));
	// Project the texture in metres onto each casting. Its marks travel with the tool.
	vec2 face = part_position.xy;
	vec2 half_size = part_size.xy * 0.5;
	if (n.x > max(n.y, n.z)) {
		face = part_position.zy;
		half_size = part_size.zy * 0.5;
	} else if (n.y > n.z) {
		face = part_position.xz;
		half_size = part_size.xz * 0.5;
	}
	vec3 paint = texture(enamel, face * 1.45 + tile_offset).rgb * tint.rgb;
	float fleck = texture(wear, face * 3.7 + tile_offset).r;
	float stain = texture(wear, face * vec2(1.4, 0.52) + tile_offset.yx).r;
	vec2 margin = half_size - abs(face);
	float edge_distance = min(margin.x, margin.y);
	float edge_wear = 1.0 - smoothstep(0.001, 0.018, edge_distance);
	float deposits = 1.0 - smoothstep(0.315, 0.415, stain);
	float missing_paint = smoothstep(0.495, 0.55, fleck + edge_wear * (0.065 + deposits * 0.13));
	vec3 oxide = mix(vec3(0.043, 0.030, 0.019), vec3(0.19, 0.113, 0.057), stain);
	vec3 rim = mix(oxide, vec3(0.235, 0.229, 0.185), edge_wear * smoothstep(0.35, 0.58, fleck));
	paint *= mix(vec3(1.0), vec3(0.61, 0.65, 0.57), deposits);
	ALBEDO = mix(paint, rim, missing_paint);
	ROUGHNESS = mix(0.56, 0.92 - edge_wear * 0.27, missing_paint);
	METALLIC = missing_paint * (0.13 + edge_wear * 0.42);
}
