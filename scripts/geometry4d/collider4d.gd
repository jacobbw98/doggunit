# Collider4D - Base class for 4D collision shapes
# Override the collision methods in subclasses for specific shapes
class_name Collider4D
extends RefCounted

## Friction override for surface walking
var friction_override: float = 0.0

## Restitution (bounciness) for elastic collisions
var restitution: float = 0.8

## Parent Object4D reference
var parent: Object4D = null

## Collision hit result
class Hit:
	var collider: Collider4D
	var displacement: Vector4D
	var floor_normal: Vector4D
	var distance: float
	
	func _init() -> void:
		collider = null
		displacement = Vector4D.zero()
		floor_normal = Vector4D.zero()
		distance = 0.0
	
	static func empty() -> Hit:
		return Hit.new()

# Get signed distance from point to surface
# Negative = inside, Positive = outside, 0 = on surface
func get_signed_distance(point: Vector4D) -> float:
	push_error("Collider4D.get_signed_distance() must be overridden")
	return 0.0

# Get surface normal at closest point to given point
func get_surface_normal(point: Vector4D) -> Vector4D:
	push_error("Collider4D.get_surface_normal() must be overridden")
	return Vector4D.unit_y()

# Get closest point on surface to given point
func get_closest_point(point: Vector4D) -> Vector4D:
	push_error("Collider4D.get_closest_point() must be overridden")
	return point

# Check collision with sphere at given position and return hit info
func collide(point: Vector4D, radius: float, hit: Hit) -> bool:
	var dist := get_signed_distance(point)
	if dist < radius:
		var normal := get_surface_normal(point)
		hit.displacement = normal.multiply(radius - dist)
		hit.distance = dist
		hit.collider = self
		hit.floor_normal = normal
		return true
	return false

# Get the center of this collider in world space
func get_center() -> Vector4D:
	if parent:
		return parent.get_position_4d()
	return Vector4D.zero()
