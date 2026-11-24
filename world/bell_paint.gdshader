shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

uniform sampler2D enamel : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D pitting : repeat_enable, filter_linear_mipmap;
uniform vec3 hull_center;
uniform vec4 paint : source_color = vec4(0.87, 0.61, 0.30, 1.0);
varying vec3 hull_position;

void vertex() {
	hull_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - hull_center;
}

void fragment() {
	// Wrap wear continuously around the bell, across the cylinder and both caps.
	float turn = atan(hull_position.z, hull_position.x) / TAU;
	float y = hull_position.y;
	vec3 grain = texture(enamel, vec2(4.0*turn, y*0.44)).rgb;
	float pits = texture(pitting, vec2(5.0*turn, y*0.74)).r;
	float flecks = texture(pitting, vec2(18.0*turn, y*2.10)).r;
	float streak = texture(pitting, vec2(13.0*turn, y*0.17)).r;
	// The two strap seats shield strips of paint and collect rust along their edges.
	float strap = min(abs(y-0.94), abs(y+1.15));
	float seam = 1.0 - smoothstep(0.04, 0.19, strap);
	float below = y < 0.94 ? (0.94-y) : 4.0;
	if (y < -1.15) { below = -1.15-y; }
	float run = smoothstep(0.46,0.80,streak) * (1.0-smoothstep(0.0, 0.25+0.86*streak, below));
	float wear = pits*0.53 + flecks*0.47 + seam*0.25 + run*0.24;
	float primer = smoothstep(0.61,0.74,wear);
	float chip = smoothstep(0.73,0.82,wear);
	vec3 topcoat = paint.rgb * grain * (0.82 + 0.20*flecks) * (1.0 - 0.46*run);
	vec3 oxide = mix(vec3(0.15,0.079,0.043),vec3(0.39,0.24,0.11),flecks);
	ALBEDO = mix(mix(topcoat, vec3(0.44,0.30,0.16)*grain, primer*0.74), oxide, chip);
	ROUGHNESS = mix(0.66, 0.93, primer);
	METALLIC = mix(0.06, 0.18, chip);
}
