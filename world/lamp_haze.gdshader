shader_type spatial;
render_mode unshaded, blend_add, cull_front, depth_test_disabled, depth_draw_never, fog_disabled, shadows_disabled;

// The box encloses a cone. Integrate only the water between the eye and the first
// opaque surface so a nearby flange cuts off the beam continuously.
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform float reach = 18.0;
uniform float slope = 0.66;
uniform float density = 0.042;
uniform vec4 water_color : source_color = vec4(0.43, 0.61, 0.57, 1.0);

varying vec3 source_view;
varying vec3 axis_view;
void vertex() {
	VERTEX.z -= reach * 0.5;
	source_view = MODELVIEW_MATRIX[3].xyz;
	axis_view = -normalize(MODELVIEW_MATRIX[2].xyz);
}

void fragment() {
	float depth = texture(scene_depth, SCREEN_UV).r;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		depth = depth * 2.0 - 1.0;
	#endif
	vec4 hit = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec3 ray = normalize(VERTEX);
	float end = min(length(VERTEX), -hit.z / (hit.w * max(0.001, -ray.z)));

	// Bound the integral to a sphere containing the volume. This also gives distant
	// work lights enough samples when viewed broadside from across the jacket.
	vec3 center = source_view + axis_view * reach * 0.60;
	float radius_sq = reach * reach * max(0.36, 0.16 + slope * slope);
	float along = dot(ray, center);
	float chord = sqrt(max(0.0, radius_sq - dot(center - ray * along, center - ray * along)));
	float start = max(0.0, along - chord);
	float span = max(0.0, min(end, along + chord) - start);
	if (span <= 0.0) {
		discard;
	}
	float radiance = 0.0;
	for (int i = 0; i < 6; i++) {
		// Extra resolution near the eye captures short water paths at the helmet.
		float a = float(i) / 6.0;
		float b = float(i + 1) / 6.0;
		float ds = span * (b*b - a*a);
		float t = start + span*a*a + 0.5*ds;
		vec3 from_bulb = ray*t - source_view;
		float z = dot(from_bulb, axis_view);
		float width = 0.075 + max(z, 0.0) * slope;
		vec3 lateral = from_bulb - axis_view*z;
		float profile = max(0.0, 1.0 - dot(lateral,lateral) / (width * width));
		float depth_fade = clamp(1.0 - z/reach, 0.0, 1.0);
		float scatter = profile*profile * depth_fade*depth_fade / (1.0 + 0.25*z*z);
		radiance += ds * scatter * smoothstep(0.02, 0.24, z);
	}
	float amount = clamp(density * radiance, 0.0, 0.6);
	ALBEDO = water_color.rgb * amount;
	ALPHA = 1.0;
}
