shader_type spatial;
render_mode cull_disabled;

// Shared by a room's batches; no per-blade script or physics bodies.
uniform vec3 player_position = vec3(0.0);
uniform bool player_active = false;
uniform vec4 player_trail[4];
uniform float wind_strength : hint_range(0.0, 0.6) = 0.19;
uniform float interaction_radius = 2.2;
varying float blade_height;
varying vec3 tuft_color;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	vec3 up = normalize(MODEL_MATRIX[1].xyz);
	float height = clamp(UV.y, 0.0, 1.0);
	blade_height = height;
	tuft_color = COLOR.rgb;
	float phase = dot(root, vec3(0.71, 0.37, 0.59));
	vec3 breeze = vec3(0.8, 0.22, 0.5);
	breeze = breeze - up * dot(breeze, up);
	float gust = sin(TIME * 1.4 + phase) * 0.65
		+ sin(TIME * 2.6 + phase * 1.7) * 0.23
		+ sin(TIME * 0.53 + phase * 0.2) * 0.35;
	vec3 offset = breeze * gust * wind_strength;
	float flatten = 0.0;
	if (player_active) {
		for (int i = 0; i < 5; i++) {
			vec3 actor = player_position;
			float strength = 1.0;
			if (i > 0) {
				actor = player_trail[i - 1].xyz;
				strength = player_trail[i - 1].w;
			}
			vec3 away = root - actor;
			float altitude = abs(dot(away, up));
			vec3 tangent = away - up * dot(away, up);
			float distance_to_actor = length(tangent);
			float influence = (1.0 - smoothstep(0.35, interaction_radius, distance_to_actor))
				* (1.0 - smoothstep(2.0, 3.4, altitude)) * strength;
			offset += tangent / max(distance_to_actor, 0.15) * influence * 0.58;
			flatten = max(flatten, influence);
		}
	}
	// Curved blades retain their rooted base; only tips bend.
	vec3 world_offset = (offset - up * flatten * 0.35) * height * height;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * world_offset;
}

void fragment() {
	vec3 root_color = vec3(0.10, 0.22, 0.09);
	vec3 tip_color = vec3(0.48, 0.65, 0.24);
	ALBEDO = mix(root_color, tip_color, smoothstep(0.0, 1.0, blade_height)) * tuft_color;
	ROUGHNESS = 0.9;
	// Keep the reverse face correctly lit on the inside of the sphere.
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
	EMISSION = ALBEDO * 0.045;
}
