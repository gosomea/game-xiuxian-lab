shader_type spatial;
render_mode unshaded;
uniform sampler2D garment_texture : source_color;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool has_texture = false;
varying vec3 world_normal;

void vertex() {
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 color = tint.rgb;
	if (has_texture) { color *= texture(garment_texture, UV).rgb; }
	float grey = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(vec3(grey), color, 0.65);
	ALBEDO = color * (0.85 + 0.15 * abs(world_normal.y));
}
