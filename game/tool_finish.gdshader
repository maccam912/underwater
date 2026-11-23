shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
uniform vec4 pigment : source_color = vec4(.4,.4,.4,1.);
uniform sampler2D wear : repeat_enable, filter_linear_mipmap;
uniform float metal = .0;
varying vec3 wp;
varying vec3 wn;
void vertex() {
	wp=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;
	wn=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment() {
	vec3 weights=pow(abs(normalize(wn)),vec3(4.));
	weights/=max(dot(weights,vec3(1.)),.001);
	vec3 p=wp*2.7;
	vec3 sample_color=texture(wear,p.yz).rgb*weights.x+
		texture(wear,p.zx).rgb*weights.y+texture(wear,p.xy).rgb*weights.z;
	float mottling=dot(sample_color,vec3(.31,.48,.21));
	float pitting=smoothstep(.19,.44,mottling);
	float rust=clamp((sample_color.r-sample_color.g)*2.4,0.,.75);
	ALBEDO=mix(pigment.rgb*(.56+.62*pitting),vec3(.22,.139,.083),rust*metal);
	ROUGHNESS=.94-.3*pitting*metal;
	METALLIC=metal*.52;
	SPECULAR=.31;
}
