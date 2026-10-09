shader_type spatial;
uniform mat4 mesh_to_mascot;
uniform float extension = 0.0;
uniform vec4 fur_color : source_color = vec4(1.0);
uniform sampler2D fur_texture : source_color, hint_default_white;
void vertex() {
	vec3 p = (mesh_to_mascot * vec4(VERTEX, 1.0)).xyz;
	p.y += smoothstep(0.72, 0.92, p.y) * extension;
	VERTEX = (inverse(mesh_to_mascot) * vec4(p, 1.0)).xyz;
}
void fragment() {
	ALBEDO = fur_color.rgb * texture(fur_texture, UV).rgb;
	ROUGHNESS = 0.85;
}
