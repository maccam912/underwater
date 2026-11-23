shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

uniform sampler2D steel_albedo : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D corrosion : repeat_enable, filter_linear_mipmap;
uniform vec4 coating : source_color = vec4(1.0);
varying vec3 position_world;
varying vec3 world_normal;

void vertex() {
	position_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 p = position_world;
	vec3 axis = pow(abs(normalize(world_normal)), vec3(4.0));
	axis /= max(0.001, dot(axis, vec3(1.0)));
	vec3 steel = texture(steel_albedo, p.zy * 0.61).rgb * axis.x
		+ texture(steel_albedo, p.xz * 0.61).rgb * axis.y
		+ texture(steel_albedo, p.xy * 0.61).rgb * axis.z;
	vec3 substrate = p*vec3(0.075,0.064,0.075);
	float broad = texture(corrosion,substrate.zy).r * axis.x
		+ texture(corrosion,substrate.xz).r * axis.y + texture(corrosion,substrate.xy).r * axis.z;
	float freckles = texture(corrosion,vec2(p.x + 0.43*p.z, p.y + 0.27*p.z)*0.58).r;
	float exposure = broad + (freckles-0.50)*0.52;
	float blister = smoothstep(0.50,0.63,exposure);
	float scale_edge = smoothstep(0.58,0.63,exposure) * (1.0-smoothstep(0.64,0.70,exposure));
	vec3 undercoat = steel * vec3(0.94,0.77,0.65);
	vec3 iron = steel * vec3(1.13,0.77,0.59) * (0.70 + freckles*0.52);
	vec3 surface = mix(steel*coating.rgb, undercoat, blister*0.72);
	ALBEDO = mix(surface,iron,smoothstep(0.64,0.73,exposure)) + scale_edge*vec3(0.014,0.012,0.007);
	METALLIC = 0.04;
	ROUGHNESS = 0.90;
	SPECULAR = 0.18;
}
