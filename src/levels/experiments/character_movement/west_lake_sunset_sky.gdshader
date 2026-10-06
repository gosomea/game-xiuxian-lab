shader_type sky;
uniform vec3 horizon : source_color = vec3(0.92,0.74,0.56);
uniform vec3 zenith : source_color = vec3(0.47,0.62,0.68);
void sky() {
	float h = clamp(EYEDIR.y,0.0,1.0);
	vec3 color = mix(horizon,zenith,pow(h,.65));
	color = mix(vec3(.72,.70,.62),color,smoothstep(-.4,.06,EYEDIR.y));
	vec3 sun_direction = normalize(vec3(-1.0,.10,-.18));
	float d = distance(EYEDIR,sun_direction);
	color += vec3(.16,.055,.015)*exp(-d*5.0);
	float disc = 1.0-smoothstep(.055,.059,d);
	color = mix(color,vec3(1.0,.66,.40),disc);
	// Broad horizontal painted wisps; no sharp procedural noise in the sky.
	float wisps = sin(EYEDIR.x*17.0+sin(EYEDIR.z*13.0))*sin(EYEDIR.y*46.0);
	float cloud = smoothstep(.50,.9,wisps)*smoothstep(.10,.22,h)*(1.0-smoothstep(.34,.48,h));
	COLOR = mix(color,vec3(.91,.82,.69),cloud*.18);
}
