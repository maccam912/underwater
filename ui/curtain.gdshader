shader_type canvas_item;
render_mode unshaded;
void fragment(){
	float fade=1.0-smoothstep(0.14,0.80,UV.x);
	COLOR=vec4(.012,.034,.039,fade*.93);
}
