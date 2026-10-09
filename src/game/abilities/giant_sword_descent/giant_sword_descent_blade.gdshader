shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float radiance : hint_range(0.0, 2.0) = 0.7;
varying vec3 local_vertex;

void vertex() {
	local_vertex = VERTEX;
}

void fragment() {
	float blade = 1.0 - smoothstep(-0.030, -0.005, local_vertex.z);
	float core = 1.0 - smoothstep(0.016, 0.040, abs(local_vertex.x));
	float guard = step(0.063, abs(local_vertex.x)) * (1.0 - blade);
	vec3 dark_jade = vec3(0.022, 0.100, 0.115);
	vec3 jade = vec3(0.19, 0.82, 0.71);
	vec3 gold = vec3(0.83, 0.60, 0.18);
	vec3 blade_color = mix(dark_jade, jade, core * 0.78);
	vec3 hilt_color = mix(vec3(0.045, 0.068, 0.09), gold, guard);
	ALBEDO = mix(hilt_color, blade_color, blade);
	METALLIC = 0.62;
	ROUGHNESS = 0.27;
	EMISSION = jade * core * blade * radiance * 0.5 + gold * guard * 0.22;
	ALPHA = opacity;
}
