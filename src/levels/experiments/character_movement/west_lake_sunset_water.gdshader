shader_type spatial;
render_mode unshaded, cull_disabled;
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
	vec2 p = world_position.xz;
	float waves = sin(p.x*2.8 + sin(p.y*.25+TIME*.18)*.65 - TIME*.48);
	float line = smoothstep(.975,.998,waves) * smoothstep(.2,.65,sin(p.y*.53+p.x*.15)*.5+.5);
	float wash = sin(p.x*.085+sin(p.y*.052))*.035;
	vec3 lake = vec3(.31,.43,.43)+wash;
	// A broken golden sunset path, painterly instead of specular PBR.
	float reflection = exp(-pow((p.y-8.0-sin(p.x*.12)*2.0)/12.0,2.0));
	reflection *= smoothstep(-40.0,40.0,p.x)*(.40+.6*smoothstep(.55,.96,waves));
	ALBEDO = mix(lake,vec3(.79,.60,.42),reflection*.36)+line*.035;
}
