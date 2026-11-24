shader_type spatial;
render_mode cull_disabled;

uniform sampler2D wear : repeat_enable, filter_linear_mipmap;
uniform float clean[25];
uniform float seed = 0.0;

void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	vec2 grid = clamp(uv * 5.0 - .5, vec2(0.), vec2(3.999));
	ivec2 ij = ivec2(floor(grid));
	int i = ij.x + 5 * ij.y;
	vec2 blend = smoothstep(vec2(0.),vec2(1.),fract(grid));
	float cleaned = mix(mix(clean[i],clean[i+1],blend.x),mix(clean[i+5],clean[i+6],blend.x),blend.y);
	vec3 grit = texture(wear, uv * .59 + vec2(seed * .19, seed * .07)).rgb;
	float fleck = texture(wear, uv * 2.7 + seed * .17).r;
	float edge = length((uv-.5) * vec2(1.,1.04));
	if (edge > .41 + .23 * (grit.r-.2) + .018 * sin(uv.y * 41. + seed)) { discard; }
	float exposed = smoothstep(.25,.77,cleaned + (fleck-.4)*.52);
	float scratch = sin(uv.y*336.0 + sin(uv.x*29.+seed)*2.)*.035;
	vec3 oxide = mix(vec3(.075,.066,.047),vec3(.31,.177,.081),clamp(grit.r*.8+fleck*.35,0.,1.));
	oxide += vec3(.16,.165,.09) * smoothstep(.38,.56,grit.g);
	vec3 steel = vec3(.37,.405,.39) * (.7 + .60 * grit.g + scratch);
	ALBEDO = mix(oxide,steel,exposed);
	ROUGHNESS = mix(.96,.48,exposed) + fleck*.03;
	METALLIC = mix(.09,.55,exposed);
}
