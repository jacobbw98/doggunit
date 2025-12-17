# Physical4D - 4D Physics body with gravity, velocity, and collision
# Ported from HackerPoet's Engine4D (Physical4D.cs)
class_name Physical4D
extends RefCounted

## Global gravity strength (acceleration in units/s²)
static var GRAVITY: float = 9.81

## Maximum upward velocity when grounded (prevents jumping uphill)
const MAX_UP_VELOCITY_GROUNDED: float = 1.0

## Seconds to reach half-velocity (friction/drag)
var velocity_decay: float = 1.0

## Enable/disable collision detection
var collisions_enabled: bool = true

## Collision sphere radius
var collider_radius: float = 0.5

## If true, bounces off surfaces
var elastic: bool = false

## Minimum cos(angle) of walkable slope (0 = all slopes, 1 = only flat)
var limit_slope: float = 0.7

## Proportion of velocity lost on bounce (0-1)
var restitution: float = 0.5

## Current velocity in 4D
var velocity: Vector4D = Vector4D.zero()

## Direction of gravity (local, can change per surface)
var gravity_direction: Vector4D = Vector4D.new(0, -1, 0, 0)

## Enable/disable gravity
var use_gravity: bool = true

## True if on a walkable surface this frame
var is_grounded: bool = false

## Colliders hit this frame
var last_hit: Array[Collider4D] = []

## Reference to surfaces in the scene
var surfaces: Array[Object4D] = []

## Walking mode (for surface-sticking physics)
func _is_walking() -> bool:
	return limit_slope > 0.0

## Update physics for one frame
func update_physics(position: Vector4D, delta: float, clear_hits: bool = true) -> Vector4D:
	# Apply velocity decay with extra drag at low speeds
	var drag_mul := 10.0 * exp(-1.8 * velocity.magnitude()) if not _is_walking() else 0.0
	var decay := velocity_decay / (1.0 + drag_mul)
	
	# Velocity decay (exponential)
	var velocity_decay_factor := pow(2.0, -delta / decay)
	var orig_up := Vector4D.dot(velocity, gravity_direction)
	velocity = velocity.multiply(velocity_decay_factor)
	
	if use_gravity:
		# Preserve upward velocity component during decay
		velocity = velocity.add(gravity_direction.multiply(orig_up * (1.0 - velocity_decay_factor)))
	
	# Apply gravity if not walking or collisions disabled
	if use_gravity and (not _is_walking() or not collisions_enabled):
		velocity = velocity.add(gravity_direction.multiply(GRAVITY * delta))
	
	# Reset grounded state
	is_grounded = false
	
	# Calculate new position
	var v_step := velocity.multiply(delta)
	var new_pos := position.add(v_step)
	
	# Handle collisions
	if collisions_enabled:
		var max_sin_up := 0.0
		new_pos = handle_colliders(new_pos, max_sin_up, clear_hits)
		var delta_pos := new_pos.subtract(position)
		
		if _is_walking():
			var grounded := max_sin_up > limit_slope
			if grounded:
				# Limit upward velocity on walkable surfaces
				var up_velocity := Vector4D.dot(velocity, gravity_direction)
				velocity = velocity.add(gravity_direction.multiply(
					min(0.0, MAX_UP_VELOCITY_GROUNDED - up_velocity)
				))
				is_grounded = true
			elif use_gravity:
				# Apply gravity when not grounded
				velocity = velocity.add(gravity_direction.multiply(GRAVITY * delta))
			
			new_pos = position.add(delta_pos)
	
	return new_pos

## Handle collision detection and resolution
func handle_colliders(pos: Vector4D, max_sin_up: float, clear_hits: bool = true) -> Vector4D:
	if clear_hits:
		last_hit.clear()
	
	var orig_pos := pos.duplicate()
	max_sin_up = 0.0
	
	for surface in surfaces:
		if not surface or not is_instance_valid(surface):
			continue
		
		# Check collision with surface
		var dist := surface.get_signed_distance(pos)
		if dist < collider_radius:
			# We're intersecting the surface
			var normal := surface.get_surface_normal(pos)
			var displacement := normal.multiply(collider_radius - dist)
			pos = pos.add(displacement)
			
			# Track floor normal for grounding
			var d_mag := displacement.magnitude()
			if d_mag > 0.0 and d_mag < collider_radius * 1.01:
				var s_up := Vector4D.dot(displacement, gravity_direction) / d_mag
				max_sin_up = max(max_sin_up, s_up)
	
	# Calculate velocity adjustment from collision
	var displacement := pos.subtract(orig_pos)
	var disp_mag_sq := displacement.sqr_magnitude()
	
	if disp_mag_sq > 1e-12:
		var dot_prod := Vector4D.dot(displacement, velocity)
		
		if elastic:
			# Bounce
			var bounce := 1.0 + restitution
			velocity = velocity.subtract(displacement.multiply(bounce * dot_prod / disp_mag_sq))
		else:
			# Slide along surface
			var cancel_up := max_sin_up <= limit_slope and _is_walking()
			var orig_v_up := Vector4D.dot(velocity, gravity_direction)
			velocity = velocity.subtract(displacement.multiply(dot_prod / disp_mag_sq))
			if cancel_up:
				velocity = velocity.add(gravity_direction.multiply(
					orig_v_up - Vector4D.dot(velocity, gravity_direction)
				))
	
	return pos

## Add a surface to track for collisions
func add_surface(surface: Object4D) -> void:
	if surface and not surfaces.has(surface):
		surfaces.append(surface)

## Remove a surface from tracking
func remove_surface(surface: Object4D) -> void:
	surfaces.erase(surface)

## Update gravity direction based on nearest surface (sticky gravity)
func update_sticky_gravity(position: Vector4D) -> void:
	var closest_surface: Object4D = null
	var closest_dist: float = INF
	
	for surface in surfaces:
		if not surface:
			continue
		var dist: float = abs(surface.get_signed_distance(position))
		if dist < closest_dist:
			closest_dist = dist
			closest_surface = surface
	
	if closest_surface:
		# Gravity points toward surface
		gravity_direction = closest_surface.get_surface_normal(position).negate()
	else:
		# No surfaces - use standard Y-down gravity
		gravity_direction = Vector4D.new(0, -1, 0, 0)
