shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;
varying vec3 world_normal;
varying vec3 world_position;
void vertex() {
	VERTEX.x += sin(TIME*.032)*2.2;
	world_normal = normalize(MODEL_NORMAL_MATRIX*NORMAL);
	world_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment() {
	float shade=dot(world_normal,normalize(vec3(-.6,.8,-.2)));
	vec3 shadow=vec3(.58,.68,.69);
	vec3 paper=vec3(.94,.85,.72);
	float light=smoothstep(-.4,.6,shade);
	ALBEDO=mix(shadow,paper,light);
}
