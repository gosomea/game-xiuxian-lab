shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 tint : source_color = vec4(0.8,0.8,0.7,1.0);
uniform float grain_strength = 0.012;
uniform bool flutter = false;
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
	if (flutter) { VERTEX.y += sin(TIME * 3.0 + VERTEX.x) * 0.12; }
	world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
	float grain = fract(sin(dot(floor(world_position*65.0),vec3(12.9898,78.233,39.425)))*43758.5453);
	float light = dot(world_normal, normalize(vec3(-0.6,0.8,-0.3)));
	float cel = light > 0.35 ? 1.0 : (light > -0.30 ? 0.91 : 0.80);
	float wash = sin(world_position.x*.19 + sin(world_position.z*.24))*.01;
	ALBEDO = tint.rgb*cel + vec3((grain-.5)*grain_strength + wash);
}
