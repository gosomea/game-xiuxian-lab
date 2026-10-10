shader_type spatial;
render_mode unshaded;
// 柔和的近景填光：保证强环境光与身体阴影中仍能读出掌部和指节体积。
uniform vec4 skin_color : source_color = vec4(0.79, 0.66, 0.59, 1.0);
void fragment() {
	vec3 n = normalize(NORMAL);
	float key = max(dot(n, normalize(vec3(-0.4, 0.65, 1.0))), 0.0);
	float volume = 0.57 + 0.43 * sqrt(key);
	float sheen = pow(max(dot(n, normalize(vec3(0.2, 0.4, 1.0))), 0.0), 18.0) * 0.035;
	ALBEDO = skin_color.rgb * volume + vec3(sheen);
}
