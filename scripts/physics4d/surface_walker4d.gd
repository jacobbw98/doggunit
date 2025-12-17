# SurfaceWalker4D - Specialized physics for entities walking on 4D surfaces
# Combines Physical4D with surface-relative movement and sticky gravity
class_name SurfaceWalker4D
extends Node

## Physics instance
var physics: Physical4D

## Current 4D position
var position_4d: Vector4D = Vector4D.zero()

## Movement speed
@export var move_speed: float = 5.0

## Jump velocity
@export var jump_velocity: float = 5.0

## The current surface being walked on
var current_surface: Object4D = null

## Input movement (set by controller)
var input_direction: Vector3 = Vector3.ZERO

## Jump requested flag
var jump_requested: bool = false

signal position_changed(new_pos: Vector4D)
signal grounded_changed(grounded: bool)
signal surface_changed(new_surface: Object4D)

func _ready() -> void:
	add_to_group("surface_walkers_4d")
	
	physics = Physical4D.new()
	physics.velocity_decay = 0.5
	physics.collider_radius = 0.5
	physics.limit_slope = 0.7
	physics.use_gravity = true
	
	# Find all 4D surfaces in scene
	call_deferred("refresh_surfaces")

## Refresh list of 4D surfaces - call after spawning new hyperspheres
func refresh_surfaces() -> void:
	physics.surfaces.clear()
	# Get all hyperspheres and add them as surfaces
	for node in get_tree().get_nodes_in_group("hyperspheres_4d"):
		if node is Object4D:
			physics.add_surface(node)
	# Also get Klein bottles
	for node in get_tree().get_nodes_in_group("klein_bottles_4d"):
		if node is Object4D:
			physics.add_surface(node)
	# Also get tori
	for node in get_tree().get_nodes_in_group("tori_4d"):
		if node is Object4D:
			physics.add_surface(node)
	# Also get room spheres (hollow spheres for interior walking)
	for node in get_tree().get_nodes_in_group("room_spheres_4d"):
		if node is Object4D:
			physics.add_surface(node)
	print("[SurfaceWalker4D] Found %d surfaces" % physics.surfaces.size())

## If false, physics processing must be done manually via process_physics()
var auto_process: bool = true

func _physics_process(delta: float) -> void:
	if not auto_process:
		return
	process_physics(delta)

## Manually process physics - call this if auto_process is false
func process_physics(delta: float) -> void:
	# Update sticky gravity toward nearest surface
	physics.update_sticky_gravity(position_4d)
	
	# Handle jump
	if jump_requested and physics.is_grounded:
		# Jump is along negative gravity direction (away from surface)
		physics.velocity = physics.velocity.add(physics.gravity_direction.negate().multiply(jump_velocity))
		jump_requested = false
	
	# Apply movement input
	if input_direction.length_squared() > 0.01:
		var move_4d := _get_surface_relative_movement(input_direction)
		physics.velocity = physics.velocity.add(move_4d.multiply(move_speed * delta * 10.0))
	
	# Update physics
	var was_grounded := physics.is_grounded
	position_4d = physics.update_physics(position_4d, delta)
	
	# Notify of changes
	position_changed.emit(position_4d)
	
	if physics.is_grounded != was_grounded:
		grounded_changed.emit(physics.is_grounded)

## Convert 3D input to surface-relative 4D movement
func _get_surface_relative_movement(input: Vector3) -> Vector4D:
	# Get the "up" direction (negative gravity)
	var up := physics.gravity_direction.negate()
	
	# Build a tangent space on the surface
	# Find two vectors perpendicular to up
	var right: Vector4D
	var forward: Vector4D
	
	if abs(up.x) < 0.9:
		right = Vector4D.new(1, 0, 0, 0)
	else:
		right = Vector4D.new(0, 0, 1, 0)
	
	# Gram-Schmidt orthogonalization
	right = right.subtract(up.multiply(Vector4D.dot(right, up))).normalized()
	forward = Vector4D.make_normal(up, right, Vector4D.unit_w()).normalized()
	
	# Map input to surface tangent space
	return right.multiply(input.x).add(forward.multiply(-input.z))

## Set 4D position directly
func set_position(pos: Vector4D) -> void:
	position_4d = pos
	position_changed.emit(position_4d)

## Get current 4D position
func get_position() -> Vector4D:
	return position_4d

## Get current velocity
func get_velocity() -> Vector4D:
	return physics.velocity

## Check if grounded
func is_grounded() -> bool:
	return physics.is_grounded

## Get gravity direction
func get_gravity_direction() -> Vector4D:
	return physics.gravity_direction

## Request a jump
func jump() -> void:
	jump_requested = true

## Set movement input
func set_input(direction: Vector3) -> void:
	input_direction = direction
