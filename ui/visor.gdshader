shader_type canvas_item;
render_mode unshaded;
uniform float strength = 0.9;
float noise(vec2 p) { return fract(sin(dot(p,vec2(12.9898,78.233))) * 43758.5453); }
void fragment(){
	vec2 edge = (UV-vec2(0.5))*2.0;
	float vignette = smoothstep(0.45,1.34,length(edge*vec2(0.84,1.0)));
	float speck = noise(floor(FRAGCOORD.xy*0.72) + mod(floor(TIME*9.0),71.0));
	float grain = (speck-0.5)*0.033;
	float opacity = vignette*0.37+abs(grain);
	COLOR=vec4(vec3(max(0.0,grain)/max(0.0001,opacity)),strength*opacity);
}
