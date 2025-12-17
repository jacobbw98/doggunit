# RoomSphere4D - Hollow sphere room where entities walk on the INSIDE surface
# Unlike Hypersphere4D (exterior walking), this has inverted normals/gravity
# so entities are pulled toward the inner surface of the sphere.
class_name RoomSphere4D
extends Object4D

## Radius of the room sphere
@export var radius: float = 20.0

## Room type for this room
@export var room_type: int = 0  # RoomTypes.RoomType enum value

## Room identifier for level graph
var room_id: int = 0

## Connected portal doors
var portals: Array = []

## Size multiplier (1.0 = base, 1.5 = large normal, 2.0 = boss)
var size_multiplier: float = 1.0

## Material color for the interior surface
@export var room_color: Color = Color(0.2, 0.8, 1.0, 1.0)  # Cyan default

## Glow color (usually same as room_color)
@export var glow_color: Color = Color(0.2, 0.8, 1.0, 1.0)

## Mesh instance for interior visualization
var mesh_instance: MeshInstance3D

## Collision body for interior walking
var collision_body: StaticBody3D
var collision_shape: CollisionShape3D

## Sun light at room center
var sun_light: OmniLight3D
var sun_mesh: MeshInstance3D
var light_enabled: bool = false  # Start disabled, enabled based on player proximity

func _ready() -> void:
	super._ready()
	add_to_group("room_spheres_4d")
	add_to_group("hyperspheres_4d")  # Add to surfaces group for SurfaceWalker4D
	
	# Apply size multiplier to radius
	radius *= size_multiplier
	
	# Create interior mesh
	_create_mesh()
	
	# Create collision for interior walking
	_create_collision()
	
	# Create sun light at center
	_create_sun_light()

func _create_mesh() -> void:
	mesh_instance = MeshInstance3D.new()
	
	# Create sphere mesh for interior
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = radius
	sphere_mesh.height = radius * 2
	sphere_mesh.radial_segments = 48
	sphere_mesh.rings = 32
	sphere_mesh.is_hemisphere = false
	mesh_instance.mesh = sphere_mesh
	
	# Use shader material with portal holes support
	var shader = load("res://resources/shaders/room_sphere_portals.gdshader")
	if shader:
		var shader_mat := ShaderMaterial.new()
		shader_mat.shader = shader
		
		# Set base properties - white albedo to not tint texture
		shader_mat.set_shader_parameter("albedo_color", Color.WHITE)
		shader_mat.set_shader_parameter("emission_color", glow_color * 0.3)
		shader_mat.set_shader_parameter("emission_strength", 0.15)
		shader_mat.set_shader_parameter("uv_scale", Vector2(8.0, 4.0))
		
		# Load grass texture
		var grass_texture = load("res://assets/textures/grass_lowpoly.png")
		if grass_texture:
			shader_mat.set_shader_parameter("albedo_texture", grass_texture)
		
		# Portal holes will be updated when portals are added
		shader_mat.set_shader_parameter("portal_count", 0)
		
		mesh_instance.material_override = shader_mat
	else:
		# Fallback to standard material if shader not found
		var mat := StandardMaterial3D.new()
		var grass_texture = load("res://assets/textures/grass_lowpoly.png")
		if grass_texture:
			mat.albedo_texture = grass_texture
			mat.uv1_scale = Vector3(8, 4, 1)
		else:
			mat.albedo_color = room_color
		mat.emission_enabled = true
		mat.emission = glow_color * 0.3
		mat.emission_energy_multiplier = 0.5
		mat.cull_mode = BaseMaterial3D.CULL_FRONT
		mesh_instance.material_override = mat
	
	add_child(mesh_instance)

func _create_collision() -> void:
	# Interior collision is handled manually in player_controller.gd
	# by constraining player position to stay inside the sphere radius
	# No 3D collision shape needed here - it would push player out
	pass

## Create a small glowing sun sphere with OmniLight at room center
func _create_sun_light() -> void:
	# Create small glowing sphere (the "sun")
	sun_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 16
	sphere.rings = 8
	sun_mesh.mesh = sphere
	
	# Bright emissive material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.95, 0.8)  # Warm white
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.95, 0.8)
	mat.emission_energy_multiplier = 2.0  # Reduced for less brightness
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sun_mesh.material_override = mat
	sun_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	add_child(sun_mesh)
	
	# Create OmniLight for actual lighting
	sun_light = OmniLight3D.new()
	sun_light.light_color = Color(1.0, 0.95, 0.85)  # Warm white
	sun_light.light_energy = 1.5  # Reduced for less brightness
	sun_light.omni_range = radius * 1.5  # Light reaches entire room
	sun_light.omni_attenuation = 0.7  # Gentler falloff
	sun_light.shadow_enabled = false  # No shadows for performance
	
	add_child(sun_light)
	
	# Start with light disabled
	set_light_enabled(false)

## Enable or disable this room's light
func set_light_enabled(enabled: bool) -> void:
	light_enabled = enabled
	if sun_light:
		sun_light.visible = enabled
	if sun_mesh:
		sun_mesh.visible = enabled

## Add a portal to this room's portal list and update shader holes
func add_portal(portal: Node) -> void:
	if portal and portal not in portals:
		portals.append(portal)
		# Defer shader update to next frame so portal position is set
		call_deferred("_update_shader_portal_holes")

## Update the shader with portal positions for hole rendering
func _update_shader_portal_holes() -> void:
	if not mesh_instance or not mesh_instance.material_override:
		return
	
	var mat = mesh_instance.material_override
	if not mat is ShaderMaterial:
		return
	
	var shader_mat: ShaderMaterial = mat as ShaderMaterial
	
	# Collect portal positions in LOCAL space (relative to this room's center)
	var positions: Array[Vector3] = []
	var radii: Array[float] = []
	
	for portal in portals:
		if not is_instance_valid(portal):
			continue
		# Portal position relative to room center (local space)
		var local_pos: Vector3 = portal.global_position - global_position
		var portal_radius: float = portal.portal_radius if portal.get("portal_radius") else 2.0
		
		# Use exact portal radius for hole (no scaling)
		positions.append(local_pos)
		radii.append(portal_radius)
		
		print("[RoomSphere] Portal hole at local_pos=%s, radius=%.1f (room=%s)" % [local_pos, portal_radius, name])
	
	# Update shader uniforms
	shader_mat.set_shader_parameter("portal_count", positions.size())
	
	# Pad arrays to 8 elements (shader expects fixed size)
	while positions.size() < 8:
		positions.append(Vector3.ZERO)
		radii.append(0.0)
	
	shader_mat.set_shader_parameter("portal_positions", positions)
	shader_mat.set_shader_parameter("portal_radii", radii)
	
	print("[RoomSphere] Updated shader with %d portal holes for %s" % [portals.size(), name])

## Get all portals connected to this room
func get_portals() -> Array:
	return portals

# Override to update mesh when slice changes
func update_slice(slice_w: float) -> void:
	super.update_slice(slice_w)
	_update_slice_mesh(slice_w)

func _update_slice_mesh(slice_w: float) -> void:
	# Standard 4D slicing - room visible when player's W is within radius
	# W-sync from portals ensures destination rooms are visible by moving their W coordinate
	var w_distance: float = abs(_position_4d.w - slice_w)
	
	# DEBUG: Show visibility calculation
	var will_be_visible: bool = w_distance < radius
	if name.begins_with("Room"):
		print("[Room] %s: _position_4d.w=%.1f, slice_w=%.1f, w_dist=%.1f, radius=%.1f -> visible=%s" % [name, _position_4d.w, slice_w, w_distance, radius, will_be_visible])
	
	# Room is visible if within radius
	if w_distance >= radius:
		# Sphere is outside the slice - not visible
		if mesh_instance:
			mesh_instance.visible = false
		if collision_body:
			collision_body.set_collision_layer_value(1, false)
			collision_body.set_collision_mask_value(1, false)
		return
	
	# Calculate slice radius
	var clamped_w_dist: float = min(w_distance, radius * 0.99)
	var slice_radius: float = sqrt(radius * radius - clamped_w_dist * clamped_w_dist)
	
	if mesh_instance and mesh_instance.mesh is SphereMesh:
		var sphere_mesh := mesh_instance.mesh as SphereMesh
		sphere_mesh.radius = slice_radius
		sphere_mesh.height = slice_radius * 2
		mesh_instance.visible = true
		
		# Update shader parameters
		var mat: Material = mesh_instance.material_override
		if mat is ShaderMaterial:
			(mat as ShaderMaterial).set_shader_parameter("slice_w", slice_w)
			(mat as ShaderMaterial).set_shader_parameter("object_w", _position_4d.w)
	
	# Update collision shape to match visual
	if collision_shape and collision_shape.shape is SphereShape3D:
		(collision_shape.shape as SphereShape3D).radius = slice_radius
		collision_body.set_collision_layer_value(1, true)
		collision_body.set_collision_mask_value(1, true)

## Signed distance for interior walking sphere
## Returns NEGATIVE when entity penetrates past the inner surface (toward outside)
## Returns small POSITIVE when entity is inside but close to the wall
## This allows collision when entity approaches or passes through the wall
func get_signed_distance(point: Vector4D) -> float:
	var dist_from_center := Vector4D.distance(point, _position_4d)
	# For interior walking: entity should stay INSIDE the sphere
	# When dist_from_center approaches radius, entity is at the wall
	# When dist_from_center > radius, entity is outside (penetrating)
	# SDF: negative when penetrating wall, zero at wall, positive when inside
	return radius - dist_from_center

## INVERTED surface normal - points INWARD toward center
## This makes gravity pull entities toward the inner surface
func get_surface_normal(point: Vector4D) -> Vector4D:
	# Normal points inward (from point toward center)
	return _position_4d.subtract(point).normalized()

## Project point onto interior surface
func project_to_surface(point: Vector4D) -> Vector4D:
	var dir := point.subtract(_position_4d).normalized()
	return _position_4d.add(dir.multiply(radius))

## Get gravity direction for interior walking (toward inner surface = outward from center)
func get_gravity_direction(point: Vector4D) -> Vector4D:
	# Gravity points from center toward surface (outward)
	return point.subtract(_position_4d).normalized()

## Override ghost mesh creation for room sphere
func _create_ghost_mesh() -> void:
	ghost_mesh = MeshInstance3D.new()
	
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = radius / size_multiplier  # Use base radius for ghost
	sphere_mesh.height = (radius / size_multiplier) * 2
	sphere_mesh.radial_segments = 32
	sphere_mesh.rings = 16
	ghost_mesh.mesh = sphere_mesh
	ghost_mesh.name = "GhostMesh_" + name
	
	_apply_ghost_material(ghost_mesh)
	
	if get_tree() and get_tree().root:
		get_tree().root.add_child(ghost_mesh)

## Set room type and update visuals
func set_room_type(type: int) -> void:
	room_type = type
	# Update color based on room type - colors will be set by RoomTypes class

## Get the spawn position inside this room
func get_spawn_position() -> Vector3:
	# Spawn inside the sphere, near the bottom
	# Position well inside the sphere wall so player doesn't clip
	var spawn_offset: float = radius - 5.0  # 5 units inside from the wall
	return global_position + Vector3(0, -spawn_offset, 0)
