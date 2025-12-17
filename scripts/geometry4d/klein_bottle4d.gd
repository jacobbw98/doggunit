# KleinBottle4D - Klein bottle surface in 4D
# A Klein bottle is a non-orientable surface that only truly exists without 
# self-intersection in 4D. Walking on one, you can return to your starting 
# point upside-down!
#
# Parametric equations for Klein bottle in 4D (figure-8 immersion):
# x(u,v) = (a + b*cos(v))*cos(u)
# y(u,v) = (a + b*cos(v))*sin(u)
# z(u,v) = b*sin(v)*cos(u/2)
# w(u,v) = b*sin(v)*sin(u/2)
# where u,v ∈ [0, 2π], a = major radius, b = tube radius
class_name KleinBottle4D
extends Object4D

## Major radius (distance from center to tube center)
@export var major_radius: float = 5.0

## Tube radius
@export var tube_radius: float = 2.0

## Material color for the glowing visualization
@export var glow_color: Color = Color(1.0, 0.3, 0.6, 1.0)

## Resolution of the mesh (lower = better performance, higher = smoother surface)
@export var resolution: int = 16  # Reduced from 32 for performance

## Mesh instance for visualization
var mesh_instance: MeshInstance3D

## Collider (simplified as torus for now)
var collider: KleinBottleCollider4D

func _ready() -> void:
	super._ready()
	add_to_group("klein_bottles_4d")
	
	# Create collider
	collider = KleinBottleCollider4D.new()
	collider.parent = self
	collider.major_radius = major_radius
	collider.tube_radius = tube_radius
	
	# Create visual (will be regenerated on slice change)
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
		mat.set_shader_parameter("glow_intensity", 2.5)
		mat.set_shader_parameter("max_distance", major_radius + tube_radius)
		mat.set_shader_parameter("object_w", _position_4d.w)
		mat.set_shader_parameter("slice_w", 0.0)
		mesh_instance.material_override = mat
	else:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = glow_color
		mat.emission_enabled = true
		mat.emission = glow_color
		mat.emission_energy_multiplier = 1.0
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.5
		mesh_instance.material_override = mat
	
	add_child(mesh_instance)

# Parametric Klein bottle point in 4D
# Using classic bottle-shaped parametric form
func _klein_point(u: float, v: float) -> Vector4D:
	var scale := major_radius
	
	# Classic Klein bottle parametric equations
	var x: float
	var y: float
	var z: float
	var w: float
	
	var cos_u := cos(u)
	var sin_u := sin(u)
	var cos_v := cos(v)
	var sin_v := sin(v)
	
	if u < PI:
		# Bottom half - the bottle body
		x = 6.0 * cos_u * (1.0 + sin_u) + 4.0 * (1.0 - cos_u / 2.0) * cos_u * cos_v
		z = -16.0 * sin_u - 4.0 * (1.0 - cos_u / 2.0) * sin_u * cos_v
	else:
		# Top half - the handle
		x = 6.0 * cos_u * (1.0 + sin_u) + 4.0 * (1.0 - cos_u / 2.0) * cos(v + PI)
		z = -16.0 * sin_u
	
	y = -4.0 * (1.0 - cos_u / 2.0) * sin_v
	
	# W coordinate for 4D - handle passes through in W
	w = tube_radius * sin_u * sin_v
	
	# Scale everything
	var s := scale * 0.2
	return Vector4D.new(x * s, y * s, z * s, w).add(_position_4d)

# Override to update mesh when slice changes
func update_slice(slice_w: float) -> void:
	super.update_slice(slice_w)
	_generate_slice_mesh(slice_w)

func _generate_slice_mesh(slice_w: float) -> void:
	if not mesh_instance:
		return
	
	# Generate 3D cross-section of the Klein bottle at current W slice
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var slice_tolerance: float = 2.0  # Increased for fuller visibility
	var found_points: bool = false
	
	# Sample the parametric surface and find points near the slice
	var step := TAU / resolution
	
	for i in range(resolution):
		for j in range(resolution):
			var u := i * step
			var v := j * step
			var u_next := (i + 1) * step
			var v_next := (j + 1) * step
			
			# Get corners of this quad in 4D
			var p00 := _klein_point(u, v)
			var p10 := _klein_point(u_next, v)
			var p01 := _klein_point(u, v_next)
			var p11 := _klein_point(u_next, v_next)
			
			# Check if any corner is near the slice
			var near_slice: bool = (
				abs(p00.w - slice_w) < slice_tolerance or
				abs(p10.w - slice_w) < slice_tolerance or
				abs(p01.w - slice_w) < slice_tolerance or
				abs(p11.w - slice_w) < slice_tolerance
			)
			
			if near_slice:
				found_points = true
				# Project to 3D by dropping W
				var v00 := p00.to_vector3()
				var v10 := p10.to_vector3()
				var v01 := p01.to_vector3()
				var v11 := p11.to_vector3()
				
				# Calculate normal for lighting
				var normal := (v10 - v00).cross(v01 - v00).normalized()
				
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
	else:
		mesh_instance.visible = false

# Get signed distance (approximate using parametric sampling)
func get_signed_distance(point: Vector4D) -> float:
	var min_dist := INF
	var step := TAU / 16  # Coarse sampling for speed
	
	for i in range(16):
		for j in range(16):
			var u := i * step
			var v := j * step
			var surface_point := _klein_point(u, v)
			var dist := Vector4D.distance(point, surface_point)
			min_dist = min(min_dist, dist)
	
	return min_dist - tube_radius * 0.1  # Approximate surface offset

# Get surface normal (numerical approximation)
func get_surface_normal(point: Vector4D) -> Vector4D:
	# Find closest point on surface and compute normal
	var closest_u := 0.0
	var closest_v := 0.0
	var min_dist := INF
	var step := TAU / 16
	
	for i in range(16):
		for j in range(16):
			var u := i * step
			var v := j * step
			var surface_point := _klein_point(u, v)
			var dist := Vector4D.distance(point, surface_point)
			if dist < min_dist:
				min_dist = dist
				closest_u = u
				closest_v = v
	
	# Compute numerical normal using central differences
	var epsilon := 0.01
	var du := _klein_point(closest_u + epsilon, closest_v).subtract(
		_klein_point(closest_u - epsilon, closest_v)
	).multiply(0.5 / epsilon)
	var dv := _klein_point(closest_u, closest_v + epsilon).subtract(
		_klein_point(closest_u, closest_v - epsilon)
	).multiply(0.5 / epsilon)
	
	# 4D normal is perpendicular to both tangent vectors
	# Use make_normal with a third vector
	var tangent3 := Vector4D.unit_w()  # Use W as third reference
	return Vector4D.make_normal(du, dv, tangent3).normalized()

# Get gravity direction (toward surface center approximated)
func get_gravity_direction(point: Vector4D) -> Vector4D:
	return _position_4d.subtract(point).normalized()

## Override ghost mesh creation to show full Klein bottle projection
func _create_ghost_mesh() -> void:
	ghost_mesh = MeshInstance3D.new()
	ghost_mesh.name = "GhostMesh_" + name
	
	# Generate full parametric surface mesh (all points, ignoring W slice)
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var ghost_resolution := 24  # Higher resolution for ghost
	var step := TAU / ghost_resolution
	
	for i in range(ghost_resolution):
		for j in range(ghost_resolution):
			var u := i * step
			var v := j * step
			var u_next := (i + 1) * step
			var v_next := (j + 1) * step
			
			# Get corners in 4D and project to 3D
			var p00 := _klein_point(u, v)
			var p10 := _klein_point(u_next, v)
			var p01 := _klein_point(u, v_next)
			var p11 := _klein_point(u_next, v_next)
			
			# Project all points to 3D (ignoring W)
			var v00 := p00.to_vector3()
			var v10 := p10.to_vector3()
			var v01 := p01.to_vector3()
			var v11 := p11.to_vector3()
			
			# Calculate normal
			var normal := (v10 - v00).cross(v01 - v00).normalized()
			
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


# Klein bottle specific collider
class KleinBottleCollider4D extends Collider4D:
	var major_radius: float = 5.0
	var tube_radius: float = 2.0
	
	func get_signed_distance(point: Vector4D) -> float:
		# Simplified: treat as a thick torus for collision
		var center := get_center()
		var local := point.subtract(center)
		
		# Distance to the ring (in XY plane)
		var ring_dist := sqrt(local.x * local.x + local.y * local.y) - major_radius
		var tube_dist := sqrt(ring_dist * ring_dist + local.z * local.z + local.w * local.w)
		
		return tube_dist - tube_radius
	
	func get_surface_normal(point: Vector4D) -> Vector4D:
		var center := get_center()
		var local := point.subtract(center)
		
		# Point on ring closest to point
		var ring_angle := atan2(local.y, local.x)
		var ring_point := Vector4D.new(
			major_radius * cos(ring_angle),
			major_radius * sin(ring_angle),
			0, 0
		)
		
		# Normal points from ring to point
		return local.subtract(ring_point).normalized()
	
	func get_closest_point(point: Vector4D) -> Vector4D:
		var normal := get_surface_normal(point)
		var center := get_center()
		var local := point.subtract(center)
		
		# Project onto surface
		var ring_angle := atan2(local.y, local.x)
		var ring_point := Vector4D.new(
			major_radius * cos(ring_angle),
			major_radius * sin(ring_angle),
			0, 0
		)
		
		var to_point := local.subtract(ring_point).normalized()
		return center.add(ring_point).add(to_point.multiply(tube_radius))
