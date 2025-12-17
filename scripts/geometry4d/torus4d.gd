# Torus4D - 4D Torus (Clifford torus) shape
# A 4D torus is like a donut in 4D - it has a major radius (ring) and minor radius (tube).
# Walking on its surface loops around in interesting ways through 4D space.
#
# Parametric equations for 4D torus:
# x = (R + r*cos(v)) * cos(u)
# y = (R + r*cos(v)) * sin(u)
# z = r * sin(v) * cos(theta)
# w = r * sin(v) * sin(theta)
# where R = major_radius, r = minor_radius, u,v,theta ∈ [0, 2π]
class_name Torus4D
extends Object4D

## Major radius (distance from center to tube center)
@export var major_radius: float = 8.0

## Minor radius (tube radius)
@export var minor_radius: float = 3.0

## Material color for the glowing visualization
@export var glow_color: Color = Color(1.0, 0.8, 0.2, 1.0)  # Golden yellow

## Resolution of the mesh
@export var resolution: int = 24

## Mesh instance for visualization
var mesh_instance: MeshInstance3D

## Collider
var collider: TorusCollider4D

## Collision for 3D
var collision_body: StaticBody3D
var collision_shape: CollisionShape3D

func _ready() -> void:
	super._ready()
	add_to_group("tori_4d")
	
	# Create collider
	collider = TorusCollider4D.new()
	collider.parent = self
	collider.major_radius = major_radius
	collider.minor_radius = minor_radius
	
	# Create visual mesh
	_create_mesh()

func _create_mesh() -> void:
	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = ArrayMesh.new()
	
	# Try to load the 4D glow shader
	var shader = load("res://resources/shaders/slice_glow_4d.gdshader")
	if shader:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("base_color", glow_color)
		mat.set_shader_parameter("glow_color", glow_color)
		mat.set_shader_parameter("glow_intensity", 2.0)
		mat.set_shader_parameter("max_distance", major_radius + minor_radius)
		mat.set_shader_parameter("object_w", _position_4d.w)
		mat.set_shader_parameter("slice_w", 0.0)
		mesh_instance.material_override = mat
	else:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = glow_color
		mat.emission_enabled = true
		mat.emission = glow_color
		mat.emission_energy_multiplier = 0.5
		mesh_instance.material_override = mat
	
	add_child(mesh_instance)

# Parametric torus point in 4D
func _torus_point(u: float, v: float) -> Vector4D:
	var R := major_radius
	var r := minor_radius
	
	var cos_u := cos(u)
	var sin_u := sin(u)
	var cos_v := cos(v)
	var sin_v := sin(v)
	
	# Standard torus in 4D where W is influenced by v
	var x := (R + r * cos_v) * cos_u
	var y := (R + r * cos_v) * sin_u
	var z := r * sin_v * cos(u * 0.5)  # Twist in Z based on u
	var w := r * sin_v * sin(u * 0.5)  # Twist in W based on u
	
	return Vector4D.new(x, y, z, w).add(_position_4d)

# Override to update mesh when slice changes
func update_slice(slice_w: float) -> void:
	super.update_slice(slice_w)
	_generate_slice_mesh(slice_w)

func _generate_slice_mesh(slice_w: float) -> void:
	if not mesh_instance:
		return
	
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var slice_tolerance: float = minor_radius * 1.5
	var found_points: bool = false
	
	var step := TAU / resolution
	
	for i in range(resolution):
		for j in range(resolution):
			var u := i * step
			var v := j * step
			var u_next := (i + 1) * step
			var v_next := (j + 1) * step
			
			# Get corners of this quad in 4D
			var p00 := _torus_point(u, v)
			var p10 := _torus_point(u_next, v)
			var p01 := _torus_point(u, v_next)
			var p11 := _torus_point(u_next, v_next)
			
			# Check if any corner is near the slice
			var near_slice := false
			for p in [p00, p10, p01, p11]:
				if abs(p.w - slice_w) < slice_tolerance:
					near_slice = true
					break
			
			if near_slice:
				found_points = true
				
				# Project 4D points to 3D by using x, y, z
				var v00 := p00.to_vector3()
				var v10 := p10.to_vector3()
				var v01 := p01.to_vector3()
				var v11 := p11.to_vector3()
				
				# Calculate normal
				var edge1 := v10 - v00
				var edge2 := v01 - v00
				var normal := edge1.cross(edge2).normalized()
				
				# First triangle
				surface_tool.set_normal(normal)
				surface_tool.add_vertex(v00)
				surface_tool.add_vertex(v10)
				surface_tool.add_vertex(v01)
				
				# Second triangle
				surface_tool.set_normal(normal)
				surface_tool.add_vertex(v10)
				surface_tool.add_vertex(v11)
				surface_tool.add_vertex(v01)
	
	if found_points:
		mesh_instance.mesh = surface_tool.commit()
		mesh_instance.visible = true
		
		# Update shader parameters
		var mat: Material = mesh_instance.material_override
		if mat is ShaderMaterial:
			(mat as ShaderMaterial).set_shader_parameter("slice_w", slice_w)
			(mat as ShaderMaterial).set_shader_parameter("object_w", _position_4d.w)
		
		# Update/create collision
		_update_collision()
	else:
		mesh_instance.visible = false
		_remove_collision()

func _update_collision() -> void:
	if not collision_body:
		collision_body = StaticBody3D.new()
		collision_body.name = "TorusCollision"
		add_child(collision_body)
	
	# Use a simple torus-shaped collision
	# Since Godot doesn't have native torus collision, use multiple spheres
	if collision_shape:
		collision_shape.queue_free()
	
	# Create a concave polygon collision from the mesh
	if mesh_instance.mesh and mesh_instance.mesh.get_surface_count() > 0:
		collision_shape = CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		var arrays = mesh_instance.mesh.surface_get_arrays(0)
		if arrays.size() > 0 and arrays[Mesh.ARRAY_VERTEX]:
			shape.set_faces(arrays[Mesh.ARRAY_VERTEX])
			collision_shape.shape = shape
			collision_body.add_child(collision_shape)

func _remove_collision() -> void:
	if collision_body:
		collision_body.queue_free()
		collision_body = null
		collision_shape = null

# Get signed distance (approximate using parametric sampling)
func get_signed_distance(point: Vector4D) -> float:
	# For a 4D torus, approximate by finding closest parametric point
	var min_dist := INF
	var step := TAU / 16
	
	for i in range(16):
		for j in range(16):
			var u := i * step
			var v := j * step
			var surface_point := _torus_point(u, v)
			var dist := Vector4D.distance(point, surface_point)
			min_dist = min(min_dist, dist)
	
	return min_dist - minor_radius * 0.1

func get_surface_normal(point: Vector4D) -> Vector4D:
	# Find closest point on torus and compute outward normal
	var closest_u := 0.0
	var closest_v := 0.0
	var min_dist := INF
	var step := TAU / 16
	
	for i in range(16):
		for j in range(16):
			var u := i * step
			var v := j * step
			var surface_point := _torus_point(u, v)
			var dist := Vector4D.distance(point, surface_point)
			if dist < min_dist:
				min_dist = dist
				closest_u = u
				closest_v = v
	
	# Compute normal via numerical gradient
	var eps := 0.01
	var p0 := _torus_point(closest_u, closest_v)
	var pu := _torus_point(closest_u + eps, closest_v)
	var pv := _torus_point(closest_u, closest_v + eps)
	
	# Use 4D cross product approximation
	var du := pu.subtract(p0)
	var dv := pv.subtract(p0)
	return Vector4D.make_normal(du, dv, Vector4D.new(0, 0, 0, 1)).normalized()

func get_gravity_direction(point: Vector4D) -> Vector4D:
	# Gravity points from point toward closest surface
	var normal := get_surface_normal(point)
	return normal.negate()

## Override ghost mesh creation to show full torus projection
func _create_ghost_mesh() -> void:
	ghost_mesh = MeshInstance3D.new()
	ghost_mesh.name = "GhostMesh_" + name
	
	# Generate full parametric torus mesh (all points, ignoring W slice)
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var ghost_resolution := 32  # Higher resolution for ghost
	var step := TAU / ghost_resolution
	
	for i in range(ghost_resolution):
		for j in range(ghost_resolution):
			var u := i * step
			var v := j * step
			var u_next := (i + 1) * step
			var v_next := (j + 1) * step
			
			# Get corners in 4D and project to 3D
			var p00 := _torus_point(u, v)
			var p10 := _torus_point(u_next, v)
			var p01 := _torus_point(u, v_next)
			var p11 := _torus_point(u_next, v_next)
			
			# Project all points to 3D (ignoring W)
			var v00 := p00.to_vector3()
			var v10 := p10.to_vector3()
			var v01 := p01.to_vector3()
			var v11 := p11.to_vector3()
			
			# Calculate normal
			var edge1 := v10 - v00
			var edge2 := v01 - v00
			var normal := edge1.cross(edge2).normalized()
			
			# First triangle
			surface_tool.set_normal(normal)
			surface_tool.add_vertex(v00)
			surface_tool.add_vertex(v10)
			surface_tool.add_vertex(v01)
			
			# Second triangle
			surface_tool.set_normal(normal)
			surface_tool.add_vertex(v10)
			surface_tool.add_vertex(v11)
			surface_tool.add_vertex(v01)
	
	ghost_mesh.mesh = surface_tool.commit()
	
	# Apply ghost material
	_apply_ghost_material(ghost_mesh)
	
	# Add to scene root
	if get_tree() and get_tree().root:
		get_tree().root.add_child(ghost_mesh)


# Torus-specific collider
class TorusCollider4D extends Collider4D:
	var major_radius: float = 8.0
	var minor_radius: float = 3.0
	
	func get_signed_distance(point: Vector4D) -> float:
		var center := get_center()
		var local := point.subtract(center)
		
		# Distance from point to the ring (major circle)
		var ring_dist := sqrt(local.x * local.x + local.y * local.y) - major_radius
		var tube_dist := sqrt(ring_dist * ring_dist + local.z * local.z + local.w * local.w)
		
		return tube_dist - minor_radius
	
	func get_surface_normal(point: Vector4D) -> Vector4D:
		var center := get_center()
		var local := point.subtract(center)
		
		# Find point on ring closest to projection
		var ring_angle := atan2(local.y, local.x)
		var ring_point := Vector4D.new(
			major_radius * cos(ring_angle),
			major_radius * sin(ring_angle),
			0, 0
		)
		
		return local.subtract(ring_point).normalized()
	
	func get_closest_point(point: Vector4D) -> Vector4D:
		var center := get_center()
		var local := point.subtract(center)
		
		# Find closest point on ring
		var ring_angle := atan2(local.y, local.x)
		var ring_point := Vector4D.new(
			major_radius * cos(ring_angle),
			major_radius * sin(ring_angle),
			0, 0
		)
		
		# Extend from ring point to surface
		var to_point := local.subtract(ring_point).normalized()
		return center.add(ring_point).add(to_point.multiply(minor_radius))
