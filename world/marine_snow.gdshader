shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, diffuse_lambert, specular_disabled, shadows_disabled;

uniform float half_extent = 10.0;
uniform float fleck_size = 0.016;
uniform float thread = 0.0;
varying float torn;
varying float fleck_tint;

void vertex() {
	// Seeds are anchored in world coordinates. Wrap the surrounding cell only at its far edges.
	vec3 seed = MODEL_MATRIX[3].xyz;
	float phase = INSTANCE_CUSTOM.r * 6.28318;
	float drift = TIME * (0.64 + INSTANCE_CUSTOM.g * 0.65);
	vec3 center = seed + vec3(drift*0.10+sin(drift*0.155+phase)*0.29,
		-drift*0.055+sin(drift*0.205+phase)*0.13, drift*0.022+cos(drift*0.14+phase)*0.15);
	vec3 relative = mod(center - CAMERA_POSITION_WORLD + half_extent, half_extent*2.0) - half_extent;
	float radius = length(relative);
	float visibility = smoothstep(0.42,1.42,radius)*(1.0-smoothstep(half_extent*0.76,half_extent,radius));
	float spin = phase + drift*(0.10 + INSTANCE_CUSTOM.a*0.6);
	float cs = cos(spin);
	float sn = sin(spin);
	float tumble = 0.43 + 0.57*abs(cos(phase + drift*0.74));
	vec2 scale = vec2(tumble*mix(1.0,0.37,thread), mix(1.0,4.0,thread));
	vec2 local = VERTEX.xy * scale * fleck_size * (0.55 + INSTANCE_CUSTOM.b * 1.29)*visibility;
	vec2 screen = mat2(vec2(cs,sn),vec2(-sn,cs))*local;
	vec3 world_pos = CAMERA_POSITION_WORLD + relative + INV_VIEW_MATRIX[0].xyz*screen.x + INV_VIEW_MATRIX[1].xyz*screen.y;
	VERTEX = (VIEW_MATRIX*vec4(world_pos,1.0)).xyz;
	NORMAL = vec3(0.0,0.0,1.0);
	torn = INSTANCE_CUSTOM.b;
	fleck_tint = INSTANCE_CUSTOM.g * mix(0.65, 1.0, smoothstep(0.75, 2.75, radius));
}

void fragment() {
	vec2 p = UV*2.0-1.0;
	p.x += (p.y*p.y-0.4)*(torn-0.5)*0.85;
	if (abs(p.x)*0.95 + abs(p.y)*(0.73+torn*0.22) > 1.04) { discard; }
	ALBEDO = mix(vec3(0.31,0.31,0.24),vec3(0.65,0.65,0.56),fleck_tint);
	ROUGHNESS = 1.0;
}
