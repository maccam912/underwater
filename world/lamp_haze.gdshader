shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

varying vec3 position_world;
void vertex() {
	position_world = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
}
void fragment() {
	vec2 r = (UV-0.5)*2.0;
	float distance_to_axis = length(r);
	float density = pow(max(0.0,1.0-distance_to_axis*distance_to_axis),3.8);
	float drift = sin(position_world.y*1.5 + position_world.x*0.63 - TIME*0.13)
		* cos(position_world.z*0.81 - position_world.x*0.47 + TIME*0.06);
	ALBEDO = vec3(0.31,0.40,0.38);
	ALPHA = density * (0.023 + drift*0.005);
}
