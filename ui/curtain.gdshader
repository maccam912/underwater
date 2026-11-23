shader_type canvas_item;
render_mode unshaded;

// The table lamp falls off towards the outside edge of the book.
void fragment() {
	vec4 prop = texture(TEXTURE, UV);
	float light = 0.94 - 0.15 * distance(UV, vec2(0.34, 0.25));
	COLOR = vec4(prop.rgb * light, prop.a);
}
