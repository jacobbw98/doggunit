shader_type spatial;
render_mode cull_front; // See inside of sphere

// Base material properties
uniform vec4 albedo_color : source_color = vec4(0.2, 0.8, 1.0, 1.0);
uniform sampler2D albedo_texture : hint_default_white;
uniform vec4 emission_color : source_color = vec4(0.2, 0.8, 1.0, 1.0);
uniform float emission_strength : hint_range(0.0, 2.0) = 0.15;
uniform vec2 uv_scale = vec2(8.0, 4.0);

// Portal hole data - up to 8 portals per room
uniform int portal_count = 0;
uniform vec3 portal_positions[8]; // Positions in LOCAL space
uniform float portal_radii[8];    // Radius of each portal hole

// Sphere center (usually origin in local space)
uniform vec3 sphere_center = vec3(0.0, 0.0, 0.0);

varying vec3 world_vertex;
varying vec3 local_vertex;

float moss_hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float moss_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(moss_hash(cell), moss_hash(cell + vec3(1,0,0)), f.x),
			mix(moss_hash(cell + vec3(0,1,0)), moss_hash(cell + vec3(1,1,0)), f.x), f.y),
		mix(mix(moss_hash(cell + vec3(0,0,1)), moss_hash(cell + vec3(1,0,1)), f.x),
			mix(moss_hash(cell + vec3(0,1,1)), moss_hash(cell + vec3(1,1,1)), f.x), f.y), f.z);
}

void vertex() {
	world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_vertex = VERTEX;
}

void fragment() {
	// Check if this fragment is inside any portal hole
	for (int i = 0; i < portal_count && i < 8; i++) {
		vec3 portal_pos = portal_positions[i];
		float portal_radius = portal_radii[i];
		
		// Skip if portal radius is 0 (unused slot)
		if (portal_radius < 0.1) continue;
		
		// Get direction from sphere center to this fragment (in local space)
		vec3 frag_dir = normalize(local_vertex - sphere_center);
		
		// Get direction from sphere center to portal
		vec3 portal_dir = normalize(portal_pos - sphere_center);
		
		// Calculate angle between fragment and portal
		float dot_product = dot(frag_dir, portal_dir);
		
		// Calculate the angular radius of the portal hole
		float sphere_radius = length(local_vertex - sphere_center);
		float angular_radius = portal_radius / sphere_radius;
		
		// If the dot product is high enough, we're inside the portal cone
		// cos(angle) > cos(angular_radius) means angle < angular_radius
		if (dot_product > (1.0 - angular_radius * angular_radius * 0.5)) {
			discard; // Create the hole!
		}
	}
	
	// Seamless object-space moss: constant detail size on every curved floor.
	vec3 p = local_vertex - sphere_center;
	float cushions = moss_noise(p * 0.62);
	float broad = moss_noise(p * 0.19 + vec3(8.0));
	float grain = moss_noise(p * 8.0);
	float flecks = moss_noise(p * 23.0);
	vec3 forest = mix(vec3(0.075, 0.17, 0.095), vec3(0.27, 0.43, 0.16),
		smoothstep(0.23, 0.78, cushions));
	forest = mix(forest, vec3(0.40, 0.52, 0.23), smoothstep(0.59, 0.83, broad) * 0.42);
	forest *= 0.88 + grain * 0.23;
	// Tiny warm leaf litter and pale moss spores, kept sparse.
	float litter = smoothstep(0.79, 0.91, moss_noise(p * 3.8 + vec3(42.0)));
	forest = mix(forest, vec3(0.47, 0.32, 0.14), litter * 0.48);
	forest += vec3(0.12, 0.15, 0.06) * smoothstep(0.84, 0.96, flecks);
	ALBEDO = forest * albedo_color.rgb;
	ROUGHNESS = 0.94;
	EMISSION = ALBEDO * 0.035 + emission_color.rgb * emission_strength * 0.15;
}
