# PortalTube - Traversable cylindrical tunnel connecting two portal doors
# Players walk through this tube to travel between rooms
class_name PortalTube
extends Node3D

## Source portal door
var source_portal: Node = null

## Target portal door
var target_portal: Node = null

## Tube visual mesh
var tube_mesh: MeshInstance3D

## Collision for walking inside tube
var collision_body: StaticBody3D

## Tube properties
var tube_radius: float = 2.5
var tube_length: float = 10.0

## Color of the tube
var tube_color: Color = Color(0.3, 0.6, 1.0, 0.6)

func _ready() -> void:
	add_to_group("portal_tubes")

## Setup tube between two world points
func setup_between_points(start_pos: Vector3, end_pos: Vector3) -> void:
	tube_length = start_pos.distance_to(end_pos)
	
	# Position at midpoint
	global_position = (start_pos + end_pos) / 2.0
	
	# Orient to face from start to end
	if tube_length > 0.1:
		look_at(end_pos)
	
	_create_tube_mesh()
	_create_tube_collision()

func _create_tube_mesh() -> void:
	tube_mesh = MeshInstance3D.new()
	
	# Create cylinder for tube
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = tube_radius
	cylinder.bottom_radius = tube_radius
	cylinder.height = tube_length
	cylinder.radial_segments = 24
	cylinder.rings = 4
	tube_mesh.mesh = cylinder
	
	# Rotate to align with Z axis (cylinder default is Y-up, we want Z-forward)
	tube_mesh.rotation_degrees.x = 90
	
	# Translucent glowing material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tube_color
	mat.emission_enabled = true
	mat.emission = tube_color
	mat.emission_energy_multiplier = 1.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.5
	# Cull front faces so we see inside the tube
	mat.cull_mode = BaseMaterial3D.CULL_FRONT
	tube_mesh.material_override = mat
	
	add_child(tube_mesh)

func _create_tube_collision() -> void:
	collision_body = StaticBody3D.new()
	collision_body.name = "TubeCollision"
	
	# Create floor inside the tube for easier walking
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(tube_radius * 1.8, 0.3, tube_length)
	floor_shape.shape = box
	
	# Position at bottom of tube
	floor_shape.position = Vector3(0, -tube_radius + 0.15, 0)
	floor_shape.rotation_degrees.x = 90  # Match tube rotation
	
	collision_body.add_child(floor_shape)
	add_child(collision_body)
	
	# Also create visual floor
	_create_floor_visual()

func _create_floor_visual() -> void:
	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(tube_radius * 1.8, 0.15, tube_length)
	floor_mesh.mesh = floor_box
	floor_mesh.position = Vector3(0, -tube_radius + 0.1, 0)
	floor_mesh.rotation_degrees.x = 90  # Match tube rotation
	
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = tube_color * 0.8
	floor_mat.emission_enabled = true
	floor_mat.emission = tube_color * 0.6
	floor_mesh.material_override = floor_mat
	
	add_child(floor_mesh)

## Set tube color
func set_color(color: Color) -> void:
	tube_color = color
	if tube_mesh and tube_mesh.material_override is StandardMaterial3D:
		var mat := tube_mesh.material_override as StandardMaterial3D
		mat.albedo_color = tube_color
		mat.emission = tube_color
