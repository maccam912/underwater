shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
uniform sampler2D steel : repeat_enable, filter_linear_mipmap;
uniform sampler2D tarnish : repeat_enable, filter_linear_mipmap;
varying vec2 cut;
void vertex() {
	cut = (MODEL_MATRIX*vec4(VERTEX,1.0)).xy - vec2(-4.0,0.0);
}
void fragment() {
	// Scalloped feathering left by the grinder under the couplant.
	float film = texture(tarnish,cut * 0.85 + vec2(0.35,0.12)).r;
	float grit = texture(steel,cut * 3.6).g;
	float swirl = length(cut * vec2(0.91,1.38) + vec2(0.092,-0.018)) * 72.0;
	float resolving = 1.0-smoothstep(0.11,0.52,fwidth(swirl));
	float scratches = smoothstep(0.12,0.94,sin(swirl*6.283) + (grit-0.5)*1.4) * resolving;
	float edge = smoothstep(0.15,0.219,length(cut));
	float spot = smoothstep(0.18,0.82,film + (grit-0.4)*0.46);
	vec3 alloy = mix(vec3(0.19,0.202,0.192),vec3(0.295,0.31,0.285),spot);
	ALBEDO = mix(alloy,vec3(0.18,0.165,0.146),edge*(0.25+0.56*film)) * (0.82+grit*0.46) + scratches*(0.015+0.017*grit);
	METALLIC = 0.28;
	ROUGHNESS = 0.67 + 0.17*film;
	SPECULAR = 0.15;
}
