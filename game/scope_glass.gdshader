shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float gate = 3.0;
uniform float wall = 9.0;
uniform bool contact = false;
float echo(float x,float centre,float width,float amplitude) {
	return amplitude * pow(max(0.0,1.0-abs(x-centre)/width),1.55);
}
void fragment() {
	vec2 p=UV;
	float x=p.x*24.0;
	float grass=.009*abs(sin(x*9.2)+sin(x*3.4+wall));
	float peaks=grass+echo(x,.9,.5,.72);
	if (contact) {
		peaks+=echo(x,3.8,.65,.065)+echo(x,5.4,.5,.042);
		peaks+=echo(x,wall,.83,.63)+echo(x,wall*2.0,.96,.43);
	}
	float trace=.82-peaks;
	float w=max(fwidth(trace-p.y)*.95,.010);
	float signal=1.0-smoothstep(w,2.0*w,abs(trace-p.y));
	float glow=exp(-abs(trace-p.y)*44.0)*.22;
	vec2 cell=abs(fract(p*vec2(12.0,5.0)+.5)-.5);
	vec2 aa=max(fwidth(p)*vec2(12.,5.)*.70,vec2(.01));
	float grid=1.0-smoothstep(0.0,1.0,min(cell.x/aa.x,cell.y/aa.y));
	float cursor=1.0-smoothstep(.02+fwidth(x)*.4,.03+fwidth(x)*1.2,abs(x-gate));
	float vignette=1.0-.35*pow(length((p-.5)*1.23),2.0);
	vec3 phosphor=vec3(.025,.061,.049)+grid*vec3(.027,.056,.039);
	phosphor+=(signal+glow)*vec3(.31,.68,.34);
	phosphor+=cursor*vec3(.66,.40,.13);
	ALBEDO=phosphor*vignette;
}
