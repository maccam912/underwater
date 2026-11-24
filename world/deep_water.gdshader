shader_type sky;

// The only ambient light at this depth leaks down from above. Looking away
// from the jacket, pitch alone changes the color of the empty water.
void sky() {
	float horizon = smoothstep(-0.77, 0.16, EYEDIR.y);
	float overhead = smoothstep(-0.05, 0.96, EYEDIR.y);
	vec3 abyss = vec3(0.004, 0.008, 0.012);
	vec3 water = mix(abyss, vec3(0.012, 0.028, 0.034), horizon);
	COLOR = mix(water, vec3(0.024, 0.057, 0.068), overhead);
}
