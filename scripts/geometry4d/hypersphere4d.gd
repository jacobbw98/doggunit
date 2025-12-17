# Hypersphere4D - 4D Sphere (3-sphere) collider
# A hypersphere is the 4D equivalent of a sphere.
# Walking on the surface works like walking on a regular sphere, but in 4D.
# Gravity points toward center, so you can walk around the entire surface.
class_name Hypersphere4D
extends Object4D

## Radius of the hypersphere
@export var radius: float = 10.0

## The collider component
var collider: HypersphereCollider4D

## Material color for the glowing visualization
@export var glow_color: Color = Color(0.2, 0.6, 1.0, 1.0)

## Mesh instance for 3D slice visualization
var mesh_instance: MeshInstance3D

func _ready() -> void:
	super._ready()
	add_to_group("hyperspheres_4d")
	
	# Create collider
	collider = HypersphereCollider4D.new()
	collider.parent = self
	collider.radius = radius
	
	# Create visual representation
	_create_mesh()
	
	# Create physics collision for player to walk on
	_create_collision()

func _create_mesh() -> void:
	mesh_instance = MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = radius
	sphere_mesh.height = radius * 2
	sphere_mesh.radial_segments = 64
	sphere_mesh.rings = 32
	mesh_instance.mesh = sphere_mesh
	
	# Try to load the 4D glow shader
	var shader = load("res://resources/shaders/slice_glow_4d.gdshader")
	if shader:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("base_color", glow_color)
		mat.set_shader_parameter("glow_color", glow_color)
		mat.set_shader_parameter("glow_intensity", 2.0)
		mat.set_shader_parameter("max_distance", radius)
		mat.set_shader_parameter("object_w", _position_4d.w)
		mat.set_shader_parameter("slice_w", 0.0)
		mesh_instance.material_override = mat
	else:
		# Fallback to standard material
		var mat := StandardMaterial3D.new()
		mat.albedo_color = glow_color
		mat.emission_enabled = true
		mat.emission = glow_color
		mat.emission_energy_multiplier = 0.5
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.3
		mesh_instance.material_override = mat
	
	add_child(mesh_instance)

## Collision body so player can walk on the sphere
var collision_body: StaticBody3D
var collision_shape: CollisionShape3D

func _create_collision() -> void:
	collision_body = StaticBody3D.new()
	collision_body.name = "CollisionBody"
	
	collision_shape = CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = radius
	collision_shape.shape = sphere_shape
	
	collision_body.add_child(collision_shape)
	add_child(collision_body)

# Override to update mesh when slice changes
func update_slice(slice_w: float) -> void:
	super.update_slice(slice_w)
	_update_slice_mesh(slice_w)

func _update_slice_mesh(slice_w: float) -> void:
	# The 3D cross-section of a 4D hypersphere at W=slice_w is a 3D sphere
	# whose radius depends on the distance from center
	var w_distance: float = abs(_position_4d.w - slice_w)
	
	if w_distance >= radius:
		# Sphere is outside the slice - not visible
		if mesh_instance:
			mesh_instance.visible = false
		if collision_body:
			collision_body.set_collision_layer_value(1, false)
			collision_body.set_collision_mask_value(1, false)
		return
	
	# Calculate the cross-section radius using Pythagorean theorem
	# If hypersphere has radius R and we slice at distance d from center,
	# the cross-section sphere has radius sqrt(R² - d²)
	var slice_radius: float = sqrt(radius * radius - w_distance * w_distance)
	
	if mesh_instance and mesh_instance.mesh is SphereMesh:
		var sphere_mesh := mesh_instance.mesh as SphereMesh
		sphere_mesh.radius = slice_radius
		sphere_mesh.height = slice_radius * 2
		mesh_instance.visible = true
		
		# Update shader parameters for glow effect
		var mat: Material = mesh_instance.material_override
		if mat is ShaderMaterial:
			(mat as ShaderMaterial).set_shader_parameter("slice_w", slice_w)
			(mat as ShaderMaterial).set_shader_parameter("object_w", _position_4d.w)
		elif mat is StandardMaterial3D:
			# Fallback: adjust glow intensity based on how close to center
			var intensity: float = 1.0 - (w_distance / radius)
			(mat as StandardMaterial3D).emission_energy_multiplier = intensity * 1.5
	
	# Update collision shape to match visual
	if collision_shape and collision_shape.shape is SphereShape3D:
		(collision_shape.shape as SphereShape3D).radius = slice_radius
		collision_body.set_collision_layer_value(1, true)
		collision_body.set_collision_mask_value(1, true)

# Override collision methods for hypersphere
func get_signed_distance(point: Vector4D) -> float:
	var dist_from_center := Vector4D.distance(point, _position_4d)
	return dist_from_center - radius

func get_surface_normal(point: Vector4D) -> Vector4D:
	# Normal points outward from center
	return point.subtract(_position_4d).normalized()

func project_to_surface(point: Vector4D) -> Vector4D:
	# Project point onto sphere surface
	var dir := point.subtract(_position_4d).normalized()
	return _position_4d.add(dir.multiply(radius))

# Get gravity direction for a point (toward center, for surface walking)
func get_gravity_direction(point: Vector4D) -> Vector4D:
	return _position_4d.subtract(point).normalized()

## Override ghost mesh creation to show full-size sphere
func _create_ghost_mesh() -> void:
	ghost_mesh = MeshInstance3D.new()
	
	# Create a full-size sphere mesh (not the slice-adjusted size)
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = radius
	sphere_mesh.height = radius * 2
	sphere_mesh.radial_segments = 32
	sphere_mesh.rings = 16
	ghost_mesh.mesh = sphere_mesh
	ghost_mesh.name = "GhostMesh_" + name
	
	# Apply ghost material
	_apply_ghost_material(ghost_mesh)
	
	# Add to scene root
	if get_tree() and get_tree().root:
		get_tree().root.add_child(ghost_mesh)


# Hypersphere-specific collider implementation
class HypersphereCollider4D extends Collider4D:
	var radius: float = 10.0
	
	func get_signed_distance(point: Vector4D) -> float:
		var center := get_center()
		return Vector4D.distance(point, center) - radius
	
	func get_surface_normal(point: Vector4D) -> Vector4D:
		return point.subtract(get_center()).normalized()
	
	func get_closest_point(point: Vector4D) -> Vector4D:
		var center := get_center()
		var dir := point.subtract(center).normalized()
		return center.add(dir.multiply(radius))
