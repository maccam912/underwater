shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

uniform vec4 pigment : source_color = vec4(0.4, 0.4, 0.4, 1.0);
uniform sampler2D wear : repeat_enable, filter_linear_mipmap;
uniform float metal = 0.0;

varying vec3 surface_position;
varying vec3 surface_normal;

void vertex() {
	// Keep the finish attached to moving screws and the diver's wrist.
	vec3 size = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	surface_position = VERTEX * size;
	surface_normal = NORMAL / max(size, vec3(0.0001));
}

void fragment() {
	vec3 weights = pow(abs(normalize(surface_normal)), vec3(4.0));
	weights /= max(dot(weights, vec3(1.0)), 0.001);
	vec3 p = surface_position * 2.7;
	vec3 grain = texture(wear, p.yz).rgb * weights.x
		+ texture(wear, p.zx).rgb * weights.y
		+ texture(wear, p.xy).rgb * weights.z;
	float relief = dot(grain, vec3(0.31, 0.48, 0.21));
	float rubbed = smoothstep(0.23, 0.59, relief);
	float oxide = clamp((grain.r - grain.g) * 2.4, 0.0, 0.75);
	ALBEDO = mix(pigment.rgb * (0.62 + 0.55 * rubbed), vec3(0.19, 0.12, 0.068), oxide * metal);

	// A broad return on rubber, a narrower glint where an oxidised nut has worn bright.
	float exposed = metal * rubbed * (1.0 - oxide);
	ROUGHNESS = mix(0.90, 0.32, exposed);
	METALLIC = metal * (0.36 + 0.34 * rubbed);
	SPECULAR = mix(0.26, 0.55, exposed);

	// The height gradient is in metres, so it responds to the real lamp on
	// curved castings and non-uniformly scaled thread and sleeve geometry.
	vec3 across = dFdx(VERTEX);
	vec3 down = dFdy(VERTEX);
	vec3 tx = cross(down, NORMAL);
	vec3 ty = cross(NORMAL, across);
	float area = dot(across, tx);
	vec3 slope = (tx * dFdx(relief) + ty * dFdy(relief)) * sign(area) / max(abs(area), 1e-9);
	slope *= mix(0.0010, 0.0020, metal);
	NORMAL = normalize(NORMAL - slope / (1.0 + 2.5 * length(slope)));
}
