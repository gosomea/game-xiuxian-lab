shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform float drift = 0.35;
uniform float opacity = 0.70;
varying vec3 world_position;
varying float side;
void vertex() {
	world_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	VERTEX.y += sin(world_position.x*.027+TIME*.035)*cos(world_position.z*.023)*1.6;
	side = (MODEL_NORMAL_MATRIX*NORMAL).y;
}
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1.0,0.0)),f.x),mix(hash(i+vec2(0.0,1.0)),hash(i+vec2(1.0)),f.x),f.y);
}
void fragment() {
	vec2 p = world_position.xz*.023+vec2(TIME*drift*.012,TIME*drift*.004);
	float n=noise(p)*.62+noise(p*2.13)*.28+noise(p*4.2)*.10;
	float mask=smoothstep(.37,.62,n);
	vec3 cream=mix(vec3(.66,.72,.69),vec3(.94,.88,.76),n);
	ALBEDO=cream;
	ALPHA=mask*opacity;
}
