shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// 4D Slice Glow Shader
// Creates a glowing laser-beam effect at the slice intersection
// Objects glow brighter when closer to the current W-slice plane

uniform vec4 base_color : source_color = vec4(0.2, 0.6, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.4, 0.8, 1.0, 1.0);
uniform float glow_intensity : hint_range(0.0, 5.0) = 2.0;
uniform float slice_w : hint_range(-50.0, 50.0) = 0.0;
uniform float object_w : hint_range(-50.0, 50.0) = 0.0;
uniform float max_distance : hint_range(0.1, 20.0) = 10.0;
uniform float edge_glow_width : hint_range(0.01, 2.0) = 0.3;
uniform float pulse_speed : hint_range(0.0, 5.0) = 1.0;
uniform bool enable_pulse = true;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Calculate distance from current W-slice
	float w_distance = abs(object_w - slice_w);
	float normalized_distance = clamp(w_distance / max_distance, 0.0, 1.0);
	
	// Base visibility falloff
	float visibility = 1.0 - normalized_distance;
	visibility = pow(visibility, 0.5); // Softer falloff
	
	// Early discard for objects too far from slice
	if (visibility < 0.01) {
		discard;
	}
	
	// Fresnel effect for edge glow (more glow at grazing angles)
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_position);
	float fresnel = 1.0 - abs(dot(view_dir, world_normal));
	fresnel = pow(fresnel, 2.0);
	
	// Pulsing effect
	float pulse = 1.0;
	if (enable_pulse) {
		pulse = 0.8 + 0.2 * sin(TIME * pulse_speed * 3.14159);
	}
	
	// Edge glow intensity increases as we get closer to slice plane
	float edge_intensity = smoothstep(edge_glow_width, 0.0, w_distance) * fresnel;
	
	// Mix base color with glow based on slice proximity
	vec3 final_color = mix(base_color.rgb, glow_color.rgb, visibility * 0.5);
	
	// Apply glow
	float glow = (visibility * 0.5 + edge_intensity) * glow_intensity * pulse;
	
	ALBEDO = final_color;
	EMISSION = glow_color.rgb * glow;
	ALPHA = visibility * base_color.a;
	
	// Metallic/roughness for nice reflections
	METALLIC = 0.3;
	ROUGHNESS = 0.4;
}
