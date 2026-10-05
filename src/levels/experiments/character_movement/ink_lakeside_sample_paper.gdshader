shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 tint : source_color = vec4(0.8, 0.8, 0.75, 1.0);
uniform float grain_strength : hint_range(0.0, 0.1) = 0.012;
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	float grain = fract(sin(dot(floor(world_position * 80.0), vec3(12.9898, 78.233, 39.425))) * 43758.5453);
	float wash = sin(world_position.x * 1.1 + sin(world_position.z * 0.73)) * 0.012;
	float shade = 0.84 + 0.16 * abs(world_normal.y);
	ALBEDO = tint.rgb * shade + vec3((grain - 0.5) * grain_strength + wash);
}
