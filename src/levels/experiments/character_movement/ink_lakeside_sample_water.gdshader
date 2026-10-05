shader_type spatial;
render_mode unshaded, cull_disabled;
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float ripple = sin(world_position.z * 8.0 + sin(world_position.x * 0.6) + TIME * 0.3);
	float stroke = smoothstep(0.94, 1.0, ripple) * (0.5 + 0.5 * sin(world_position.x * 3.0));
	vec3 near_color = vec3(0.36, 0.42, 0.43);
	vec3 far_color = vec3(0.82, 0.83, 0.77);
	float distance_wash = 1.0 - smoothstep(-85.0, -25.0, world_position.z);
	ALBEDO = mix(near_color, far_color, distance_wash) + stroke * 0.018;
}
