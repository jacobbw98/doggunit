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
	
	// Sample texture with proper UV scaling
	vec2 scaled_uv = UV * uv_scale;
	vec4 tex_color = texture(albedo_texture, scaled_uv);
	
	// Apply albedo color tint to texture
	ALBEDO = tex_color.rgb * albedo_color.rgb;
	
	// Subtle emission
	EMISSION = emission_color.rgb * emission_strength;
}
