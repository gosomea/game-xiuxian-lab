shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 paper_color : source_color = vec4(0.952941, 0.941176, 0.905882, 1.0);
uniform vec4 grid_color : source_color = vec4(0.698039, 0.745098, 0.682353, 1.0);
uniform vec4 major_grid_color : source_color = vec4(0.494118, 0.600000, 0.509804, 1.0);
uniform vec4 x_axis_color : source_color = vec4(0.635294, 0.478431, 0.231373, 1.0);
uniform vec4 z_axis_color : source_color = vec4(0.207843, 0.419608, 0.352941, 1.0);

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 point = world_position.xz;
	vec2 width = max(fwidth(point), vec2(0.001));
	vec2 cell = abs(fract(point - 0.5) - 0.5) / width;
	float grid = 1.0 - min(min(cell.x, cell.y), 1.0);
	vec2 major_cell = abs(fract(point / 5.0 - 0.5) - 0.5) / (width / 5.0);
	float major_grid = 1.0 - min(min(major_cell.x, major_cell.y), 1.0);
	float edge = 1.0 - smoothstep(8.0, 12.0, max(abs(point.x), abs(point.y)));
	vec3 color = mix(paper_color.rgb, grid_color.rgb, grid * 0.6 * edge);
	color = mix(color, major_grid_color.rgb, major_grid * 0.55 * edge);
	float x_axis = 1.0 - smoothstep(0.025, 0.025 + width.y, abs(point.y));
	float z_axis = 1.0 - smoothstep(0.025, 0.025 + width.x, abs(point.x));
	color = mix(color, x_axis_color.rgb, x_axis * edge * 0.85);
	color = mix(color, z_axis_color.rgb, z_axis * edge * 0.85);
	float ring = 1.0 - smoothstep(0.018, 0.018 + length(width), abs(length(point) - 0.38));
	color = mix(color, z_axis_color.rgb, ring);
	ALBEDO = color;
}
