shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

uniform sampler2D steel_albedo : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D corrosion : repeat_enable, filter_linear_mipmap;
uniform vec4 coating : source_color = vec4(1.0);
uniform bool leg_welds = false;
varying vec3 position_world;
varying vec3 world_normal;
varying float upright;

void vertex() {
	position_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	upright = smoothstep(0.90, 0.97, abs(normalize(MODEL_MATRIX[1].xyz).y));
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
	// The welds on the legs trap rust. Long, interrupted trails spread below the lip.
	float streaks = texture(corrosion, vec2(p.x + 0.67*p.z, p.y) * vec2(0.64, 0.088)).r;
	float below_weld = mod(2.9 - p.y, 9.13);
	float trail = leg_welds ? upright * smoothstep(0.43,0.78,streaks)
		* (1.0 - smoothstep(0.03, 0.32 + 2.45*streaks, below_weld)) : 0.0;
	float exposure = broad + (freckles-0.50)*0.52 + trail*0.32;
	float blister = smoothstep(0.48,0.62,exposure);
	float scale_edge = smoothstep(0.54,0.60,exposure) * (1.0-smoothstep(0.62,0.70,exposure));
	float steel_luma = dot(steel, vec3(0.22, 0.68, 0.10));
	vec3 undercoat = mix(steel, vec3(steel_luma), 0.48) * vec3(0.66,0.56,0.42);
	vec3 iron = mix(steel*vec3(0.92,0.67,0.50),
		steel_luma*mix(vec3(0.49,0.26,0.16), vec3(1.04,0.65,0.36), freckles), 0.70);
	vec3 surface = mix(steel*coating.rgb*0.90, undercoat, blister*0.87);
	ALBEDO = mix(surface,iron,smoothstep(0.59,0.71,exposure)) + scale_edge*vec3(0.020,0.012,0.006);
	// Use the existing worn texture as a shallow relief map. Derivatives keep
	// the relief in metres across different-sized piles and tapered braces.
	float height = 0.022*steel_luma + 0.015*blister + 0.004*scale_edge;
	vec3 px = dFdx(VERTEX);
	vec3 py = dFdy(VERTEX);
	vec3 u = cross(py,NORMAL);
	vec3 v = cross(NORMAL,px);
	float area = dot(px,u);
	vec3 gradient = (u*dFdx(height) + v*dFdy(height)) * sign(area) / max(abs(area),0.000001);
	NORMAL = normalize(NORMAL - gradient);
	METALLIC = mix(0.16,0.025,blister);
	ROUGHNESS = mix(0.59,0.97,blister);
	SPECULAR = mix(0.34,0.15,blister);
}
