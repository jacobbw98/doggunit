# Projectile - Visible bullet that travels through 4D space and damages on hit
class_name Projectile
extends Area3D

## The gun stats that fired this projectile
var gun_stats: GunStats

## Direction of travel (normalized, 3D component)
var direction: Vector3 = Vector3.FORWARD

## Speed in units per second
var speed: float = 20.0

## Damage to deal on hit
var damage: float = 10.0

## The type for damage calculation
var damage_type: GunTypes.Type = GunTypes.Type.EXPLOSIVE

## Who fired this (to avoid self-hits)
var shooter: Node = null

## Time to live before auto-destroy
var lifetime: float = 5.0
var _time_alive: float = 0.0
var _impact_handled: bool = false
var _pending_world_origin := Vector3.ZERO
var _has_pending_world_origin: bool = false
## Item modifiers are set by the gun before launch and inherited by split shots.
var bounce_count: int = 0
var homing_strength: float = 0.0
var laser_guided: bool = false
## Broad stat upgrades scale force/radius separately from pre-scaled damage/speed.
var power_multiplier: float = 1.0
var _launched: bool = false
var _source_room: Node3D
var _source_room_id: int = -1
var _recent_hit_bodies: Array[Node3D] = []
var _impact_target: Node3D
const LASER_RANGE: float = 250.0
const IMPACT_CLEARANCE: float = 0.25

## Detached impact effects keep the shot's W slice after the projectile is freed.
class SliceEffect extends Node3D:
	var impact_w: float = 0.0
	var owning_room: Node3D
	func _process(_delta: float) -> void:
		visible = not is_instance_valid(owning_room) or owning_room.get("graph_visible") != false
		var player := get_tree().get_first_node_in_group("player")
		if player and player.has_method("get_position_4d"):
			visible = visible and absf(player.get_position_4d().w - impact_w) < 5.0

## Visual components
var mesh_instance: MeshInstance3D
var _color: Color = Color.WHITE
var _base_scale: float = 1.0

## 4D Properties
var position_4d: Vector4D = Vector4D.zero()
var velocity_w: float = 0.0  # W-axis velocity (usually 0 - bullets stay in same W)
const PROJECTILE_W_RADIUS: float = 5.0  # W-slice visibility radius (generous)

## Reference to player for W-position tracking
var _player: Node = null

## Bodies already hit by this projectile (for piercing)
var hit_bodies: Array[Node] = []

## AOE Configuration
const EXPLOSION_RADIUS: float = 12.0
const EXPLOSION_KNOCKBACK: float = 20.0
const FREEZE_RADIUS: float = 6.0
const FREEZE_DURATION: float = 2.0
const IMPLOSION_RADIUS: float = 7.0
const IMPLOSION_FORCE: float = 15.0
const SPLIT_ANGLE: float = 0.4  # Radians (~23 degrees)

func _ready() -> void:
	if _has_pending_world_origin:
		global_position = _pending_world_origin
		_has_pending_world_origin = false
	_create_visual()
	_setup_collision()
	add_to_group("projectiles")
	
	# Connect collision signal
	body_entered.connect(_on_body_entered)
	
	# Find player for W-position tracking
	_find_player()

func _find_player() -> void:
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player")

func _process(_delta: float) -> void:
	# Update visibility based on player's current W position
	_update_visibility_from_player()

func _update_visibility_from_player() -> void:
	if not _player:
		visible = true
		return
	
	# Get player's W position
	var player_w: float = 0.0
	if _player.has_method("get_position_4d"):
		player_w = _player.get_position_4d().w
	elif "position_4d" in _player:
		player_w = _player.position_4d.w
	
	# Calculate W-distance from player's current slice
	var w_distance: float = abs(position_4d.w - player_w)
	
	if w_distance >= PROJECTILE_W_RADIUS:
		# Too far in W - hide (but bullet still exists and moves)
		visible = false
		return
	
	# Scale based on W-distance - closer = larger
	var scale_factor: float = 1.0 - (w_distance / PROJECTILE_W_RADIUS) * 0.7
	scale_factor = max(scale_factor, 0.3)
	
	if mesh_instance:
		mesh_instance.scale = Vector3.ONE * scale_factor * _base_scale
	
	visible = true

func _create_visual() -> void:
	mesh_instance = MeshInstance3D.new()
	
	var sphere := SphereMesh.new()
	var size: float = 0.15
	if gun_stats:
		size = 0.1 + gun_stats.projectile_size * 0.1
	_base_scale = 1.0  # The mesh already contains projectile_size; do not scale it twice.
	sphere.radius = size
	sphere.height = size * 2
	mesh_instance.mesh = sphere
	
	# Material based on damage type
	var mat := StandardMaterial3D.new()
	match damage_type:
		GunTypes.Type.EXPLOSIVE:
			_color = Color(1.0, 0.5, 0.1)  # Orange
		GunTypes.Type.IMPLOSIVE:
			_color = Color(0.6, 0.2, 1.0)  # Purple
		GunTypes.Type.FREEZING:
			_color = Color(0.3, 0.8, 1.0)  # Cyan
		GunTypes.Type.ACCELERATING:
			_color = Color(0.3, 1.0, 0.5)  # Green
	
	mat.albedo_color = _color
	mat.emission_enabled = true
	mat.emission = _color
	mat.emission_energy_multiplier = 2.0
	mesh_instance.material_override = mat
	
	add_child(mesh_instance)

func _setup_collision() -> void:
	var collision_shape := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = 0.2
	collision_shape.shape = sphere_shape
	add_child(collision_shape)
	
	# Set collision layers
	collision_layer = 2  # Projectiles layer
	collision_mask = 1 | 4  # Collide with default and enemies
	
	# Enable monitorable so portals can detect us
	monitorable = true

## Launch after parenting: factories retain a pending world muzzle origin.
func launch(launch_direction: Vector3) -> void:
	if _launched or _impact_handled:
		return
	direction = launch_direction.normalized() if not launch_direction.is_zero_approx() else Vector3.FORWARD
	_launched = true
	_capture_source_room()
	if laser_guided:
		_update_homing(1.0)
		_fire_laser()

func _capture_source_room(prefer_shooter: bool = true) -> void:
	if is_instance_valid(_source_room):
		return
	var desired_id := int(shooter.get_meta("encounter_room", -1)) if prefer_shooter and is_instance_valid(shooter) else -1
	if prefer_shooter and desired_id < 0 and is_instance_valid(shooter) and shooter.is_in_group("player"):
		var run := get_tree().get_first_node_in_group("run_manager")
		if run:
			desired_id = int(run.get("current_room_id"))
	var nearest_ratio := INF
	for room in get_tree().get_nodes_in_group("room_spheres_4d"):
		if not room is Node3D or not is_instance_valid(room):
			continue
		if room.get("_position_4d") != null and absf(room._position_4d.w - position_4d.w) > 0.5:
			continue
		if desired_id >= 0:
			if room.get("room_id") == desired_id:
				_source_room = room
				break
			continue
		var radius: float = float(room.get("radius"))
		var ratio: float = global_position.distance_to(room.global_position) / maxf(radius, 0.01)
		if ratio <= 1.05 and ratio < nearest_ratio:
			_source_room = room
			nearest_ratio = ratio
	if is_instance_valid(_source_room) and _source_room.get("room_id") != null:
		_source_room_id = int(_source_room.get("room_id"))

## The portal plane changes the shot's W/room ownership without moving XYZ.
## Native Area3D portal callbacks delegate here too; a stale callback from an
## already-crossed source cannot overwrite a later destination.
func notify_portal_crossing(portal: Node3D) -> void:
	if _impact_handled or not is_instance_valid(portal) or portal.get("available") == false or portal.get("combat_locked") == true or portal.get("key_locked") == true:
		return
	if is_instance_valid(_source_room) and portal.get("source_room") != _source_room:
		return
	var receiver := portal.get("target_portal") as Node3D
	var destination := receiver.get("source_room") as Node3D if is_instance_valid(receiver) else null
	if not is_instance_valid(destination):
		return
	_source_room = destination
	_source_room_id = int(destination.get("room_id")) if destination.get("room_id") != null else -1
	var point = destination.get("position_4d")
	if point == null:
		point = destination.get("_position_4d")
	position_4d = Vector4D.from_vector3(global_position, float(point.w) if point != null else position_4d.w)

func _physics_process(delta: float) -> void:
	if _impact_handled or get_tree().paused:
		return
	if not _launched:
		launch(direction)
		if _impact_handled:
			return
	_clear_departed_hits()
	_update_homing(delta)
	var remaining := speed * delta
	# Resolve several impacts in one high-speed tick without tunnelling.
	while remaining > 0.0001 and not _impact_handled:
		var start := global_position
		var finish := start + direction * remaining
		var hit := _trace_segment(start, finish)
		if hit.is_empty():
			global_position = finish
			break
		global_position = hit.position
		remaining = maxf(0.0, remaining - start.distance_to(global_position))
		position_4d = Vector4D.from_vector3(global_position, position_4d.w)
		if hit.has("portal"):
			notify_portal_crossing(hit.portal)
			continue
		_resolve_collision(hit.get("collider") as Node3D, hit.normal)
	position_4d = Vector4D.from_vector3(global_position, position_4d.w + velocity_w * delta)
	_time_alive += delta
	if _time_alive >= lifetime:
		queue_free()

func _update_homing(delta: float) -> void:
	if homing_strength <= 0.0:
		return
	var nearest: Node3D
	var nearest_distance := INF
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if not candidate is Node3D or not is_instance_valid(candidate) or candidate == shooter or candidate.get("_dead") == true:
			continue
		if not _target_matches_w(candidate) or not _target_matches_room(candidate) or _body_is_blocked(candidate):
			continue
		var distance := global_position.distance_squared_to(candidate.global_position)
		if distance < nearest_distance:
			nearest = candidate
			nearest_distance = distance
	if is_instance_valid(nearest):
		var toward := (_body_center(nearest) - global_position).normalized()
		direction = direction.lerp(toward, 1.0 - exp(-homing_strength * delta)).normalized()

func _clear_departed_hits() -> void:
	for index in range(_recent_hit_bodies.size() - 1, -1, -1):
		var body := _recent_hit_bodies[index]
		if not is_instance_valid(body) or global_position.distance_to(_body_center(body)) > _body_clearance(body):
			_recent_hit_bodies.remove_at(index)

func _body_center(body: Node3D) -> Vector3:
	var shape := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	return shape.global_position if shape else body.global_position

func _body_clearance(body: Node3D) -> float:
	var radius := 0.5
	var shape := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape and shape.shape:
		if shape.shape is CapsuleShape3D:
			radius = maxf(float(shape.shape.radius), float(shape.shape.height) * 0.5)
		elif shape.shape is SphereShape3D:
			radius = float(shape.shape.radius)
	return radius + 0.4

func _body_is_blocked(body: Node3D) -> bool:
	return body in _recent_hit_bodies or (damage_type == GunTypes.Type.ACCELERATING and body in hit_bodies)

## Physics and analytic room walls share the same closest-hit calculation.
func _trace_segment(start: Vector3, finish: Vector3) -> Dictionary:
	var closest := _trace_sphere_wall(start, finish)
	var crossing := _trace_portal_plane(start, finish)
	if not crossing.is_empty() and (closest.is_empty() or start.distance_squared_to(crossing.position) < start.distance_squared_to(closest.position)):
		closest = crossing
	var query := PhysicsRayQueryParameters3D.create(start, finish, collision_mask)
	var exclusions: Array[RID] = []
	if is_instance_valid(shooter) and shooter is CollisionObject3D:
		exclusions.append(shooter.get_rid())
	for body in _recent_hit_bodies:
		if is_instance_valid(body) and body is CollisionObject3D:
			exclusions.append(body.get_rid())
	if damage_type == GunTypes.Type.ACCELERATING:
		for body in hit_bodies:
			if is_instance_valid(body) and body is CollisionObject3D:
				exclusions.append(body.get_rid())
	for attempt in range(32):
		query.exclude = exclusions
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			break
		var body := hit.collider as Node3D
		if body and body.has_method("take_damage") and (not _target_matches_w(body) or not _target_matches_room(body)):
			exclusions.append(hit.rid)
			continue
		if closest.is_empty() or start.distance_squared_to(hit.position) < start.distance_squared_to(closest.position):
			closest = hit
		break
	return closest

func _trace_portal_plane(start: Vector3, finish: Vector3) -> Dictionary:
	var nearest: Dictionary = {}
	var portals: Array = _source_room.get_portals() if is_instance_valid(_source_room) and _source_room.has_method("get_portals") else get_tree().get_nodes_in_group("portal_doors")
	for candidate in portals:
		var portal := candidate as Node3D
		if not is_instance_valid(portal) or not portal.has_method("contains_aperture"):
			continue
		if is_instance_valid(_source_room) and portal.get("source_room") != _source_room:
			continue
		var receiver := portal.get("target_portal") as Node3D
		if not is_instance_valid(receiver) or not is_instance_valid(receiver.get("source_room")):
			continue
		var entry := portal.to_local(start)
		var exit := portal.to_local(finish)
		if entry.z <= 0.000001 or exit.z > 0.0:
			continue
		var fraction := entry.z / (entry.z - exit.z)
		var point := start.lerp(finish, fraction)
		if not portal.contains_aperture(point, 2.0):
			continue
		if nearest.is_empty() or start.distance_squared_to(point) < start.distance_squared_to(nearest.position):
			nearest = {"position": point, "normal": Vector3.ZERO, "collider": null, "portal": portal}
	return nearest

func _trace_sphere_wall(start: Vector3, finish: Vector3) -> Dictionary:
	var nearest: Dictionary = {}
	for room in get_tree().get_nodes_in_group("room_spheres_4d"):
		if not is_instance_valid(room):
			continue
		if is_instance_valid(_source_room) and room != _source_room:
			continue
		if room.get("_position_4d") != null and absf(room._position_4d.w - position_4d.w) > 0.5:
			continue
		var radius: float = float(room.get("radius")) if room.get("radius") != null else 20.0
		var relative_start: Vector3 = start - room.global_position
		var movement := finish - start
		var relative_end: Vector3 = finish - room.global_position
		if relative_start.length() > radius or relative_end.length() < radius - 0.15 or movement.dot(relative_end) <= 0.0:
			continue
		var a := movement.length_squared()
		var b := 2.0 * relative_start.dot(movement)
		var c := relative_start.length_squared() - pow(radius - 0.15, 2)
		var discriminant := b * b - 4.0 * a * c
		if a <= 0.00001 or discriminant < 0.0:
			continue
		var fraction := (-b + sqrt(discriminant)) / (2.0 * a)
		if fraction < 0.0 or fraction > 1.0:
			continue
		var point := start.lerp(finish, fraction)
		var through_portal := false
		if room.has_method("get_portals"):
			for portal in room.get_portals():
				if is_instance_valid(portal) and portal.has_method("contains_aperture") and portal.contains_aperture(point, 2.0):
					through_portal = true
					break
		if through_portal:
			continue
		if nearest.is_empty() or start.distance_squared_to(point) < start.distance_squared_to(nearest.position):
			nearest = {"position": point, "normal": -(point - room.global_position).normalized(), "collider": null}
	return nearest

## Compatibility helpers for callers that explicitly sweep or check a wall.
func _check_swept_collision(previous_position: Vector3) -> void:
	var hit := _trace_segment(previous_position, global_position)
	if not hit.is_empty():
		global_position = hit.position
		position_4d = Vector4D.from_vector3(global_position, position_4d.w)
		if hit.has("portal"):
			notify_portal_crossing(hit.portal)
		else:
			_resolve_collision(hit.get("collider") as Node3D, hit.normal)

func _check_wall_collision(distance_moved: float) -> void:
	var hit := _trace_sphere_wall(global_position - direction * distance_moved, global_position)
	if not hit.is_empty():
		global_position = hit.position
		position_4d = Vector4D.from_vector3(global_position, position_4d.w)
		_handle_wall_collision(hit.normal)

func _target_matches_w(body: Node) -> bool:
	var target_w := 0.0
	if body.has_method("get_position_4d"):
		target_w = body.get_position_4d().w
	elif "position_4d" in body:
		target_w = body.position_4d.w
	return absf(position_4d.w - target_w) <= PROJECTILE_W_RADIUS

func _target_matches_room(body: Node3D) -> bool:
	if _source_room_id < 0:
		return true
	var owner_id := int(body.get_meta("encounter_room", body.get_meta("room_id", -1)))
	if body.is_in_group("player"):
		var run := get_tree().get_first_node_in_group("run_manager")
		if run:
			owner_id = int(run.get("current_room_id"))
	if owner_id >= 0:
		return owner_id == _source_room_id
	return not is_instance_valid(_source_room) or body.global_position.distance_to(_source_room.global_position) <= float(_source_room.get("radius"))

func _on_body_entered(body: Node3D) -> void:
	_resolve_collision(body, Vector3.ZERO)

func _handle_wall_collision(normal: Vector3 = Vector3.ZERO) -> void:
	_resolve_collision(null, normal)

func _resolve_collision(body: Node3D, normal: Vector3) -> void:
	if _impact_handled or (is_instance_valid(body) and (body == shooter or _body_is_blocked(body))):
		return
	var direct_target := is_instance_valid(body) and body.has_method("take_damage")
	if direct_target and (not _target_matches_w(body) or not _target_matches_room(body)):
		return
	_impact_target = body if direct_target else null
	if direct_target:
		_recent_hit_bodies.append(body)
		if body not in hit_bodies:
			hit_bodies.append(body)
		if damage_type == GunTypes.Type.FREEZING:
			if body.has_method("register_freezing_hit"):
				body.register_freezing_hit()
			elif body.has_method("freeze") and randf() < 0.01:
				body.freeze(FREEZE_DURATION)
		body.take_damage(int(damage), damage_type)
	match damage_type:
		GunTypes.Type.EXPLOSIVE:
			_explode()
		GunTypes.Type.FREEZING:
			_spawn_freeze_effect()
		GunTypes.Type.IMPLOSIVE:
			_implode_nearby()
	if damage_type == GunTypes.Type.ACCELERATING and direct_target:
		if bounce_count > 0:
			_bounce(normal, body)
		_impact_handled = true
		_pierce_and_split(body)
		return
	if bounce_count > 0:
		_bounce(normal, body)
	else:
		_impact_handled = true
		queue_free()

func _bounce(normal: Vector3, body: Node3D = null) -> void:
	bounce_count -= 1
	var surface_normal := normal.normalized()
	if surface_normal.is_zero_approx():
		surface_normal = (global_position - _body_center(body)).normalized() if is_instance_valid(body) else -direction
	if surface_normal.is_zero_approx() or direction.dot(surface_normal) >= -0.001:
		surface_normal = -direction
	direction = direction.bounce(surface_normal).normalized()
	global_position += direction * IMPACT_CLEARANCE
	position_4d = Vector4D.from_vector3(global_position, position_4d.w)

func _fire_laser() -> void:
	set_physics_process(false)
	var remaining := LASER_RANGE
	while remaining > 0.001 and not _impact_handled:
		var start := global_position
		var hit := _trace_segment(start, start + direction * remaining)
		var finish: Vector3 = start + direction * remaining if hit.is_empty() else hit.position
		_spawn_laser_segment(start, finish)
		global_position = finish
		position_4d = Vector4D.from_vector3(global_position, position_4d.w)
		remaining = maxf(0.0, remaining - start.distance_to(finish))
		if hit.is_empty():
			break
		if hit.has("portal"):
			notify_portal_crossing(hit.portal)
			continue
		_resolve_collision(hit.get("collider") as Node3D, hit.normal)
		if _impact_handled or remaining <= 0.001:
			return
	_impact_handled = true
	queue_free()

func _spawn_laser_segment(start: Vector3, finish: Vector3) -> void:
	var segment := finish - start
	if segment.length_squared() < 0.000001:
		return
	var effect := _new_slice_effect("LaserBeam")
	effect.global_position = (start + finish) * 0.5
	var visual := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.025 * power_multiplier
	cylinder.bottom_radius = 0.025 * power_multiplier
	cylinder.height = segment.length()
	cylinder.radial_segments = 8
	visual.mesh = cylinder
	visual.basis = Basis(Quaternion(Vector3.UP, segment.normalized()))
	visual.material_override = _effect_material(Color(_color, 0.9))
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	effect.add_child(visual)
	var tween := effect.create_tween()
	tween.tween_property(visual.material_override, "albedo_color:a", 0.0, 0.12)
	tween.tween_callback(effect.queue_free)

## Get enemies AND player within a radius, respecting 4D W-slice
## Returns all valid targets for AOE effects (enemies + player if not shooter)
func _get_nearby_targets(radius: float) -> Array[Node]:
	var result: Array[Node] = []
	var all_targets: Array[Node] = []
	
	# Add all enemies
	all_targets.append_array(get_tree().get_nodes_in_group("enemies"))
	
	# Add player (so enemy explosions can affect player too)
	var player = get_tree().get_first_node_in_group("player")
	if player:
		all_targets.append(player)
	
	for target in all_targets:
		if not is_instance_valid(target) or target == shooter:
			continue
		if target is Node3D and not _target_matches_room(target):
			continue
		
		# Check 3D distance
		var dist: float = global_position.distance_to(target.global_position)
		if dist > radius:
			continue
		
		# Check 4D W-distance
		var target_w: float = 0.0
		if target.has_method("get_position_4d"):
			target_w = target.get_position_4d().w
		elif "position_4d" in target:
			target_w = target.position_4d.w
		
		if abs(position_4d.w - target_w) <= PROJECTILE_W_RADIUS:
			result.append(target)
	
	return result


## EXPLOSIVE: Deal radial damage to nearby targets and knock them back
func _explode() -> void:
	print("[Projectile] EXPLOSION!")
	
	# Spawn visual effect
	_spawn_explosion_effect()
	
	var radius := EXPLOSION_RADIUS * power_multiplier
	var nearby: Array[Node] = _get_nearby_targets(radius)
	var impact_point: Vector3 = global_position
	
	for target in nearby:
		var dist: float = impact_point.distance_to(target.global_position)
		var falloff: float = 1.0 - (dist / radius)
		
		# Apply splash damage (skip if already hit by direct impact)
		if target != _impact_target:
			var aoe_damage: int = int(damage * falloff)  # 100% AOE damage with distance falloff
			if aoe_damage > 0 and target.has_method("take_damage"):
				target.take_damage(aoe_damage, damage_type)
				print("[Projectile] Explosion hit %s for %d splash damage" % [target.name, aoe_damage])
		
		# Apply knockback to ALL targets in range (including direct hit)
		var knockback_dir: Vector3 = (target.global_position - impact_point).normalized()
		if knockback_dir.length_squared() < 0.01:
			knockback_dir = Vector3.UP  # Fallback if at exact center
		
		# Add upward component for a more dramatic effect
		knockback_dir = (knockback_dir + Vector3.UP * 0.5).normalized()
		var knockback_force: Vector3 = knockback_dir * EXPLOSION_KNOCKBACK * power_multiplier * falloff
		
		if target.has_method("apply_external_force"):
			target.apply_external_force(knockback_force)
			print("[Projectile] Knocked back %s" % target.name)


## Spawn the expanding sphere visual effect for explosions
func _spawn_explosion_effect() -> void:
	var effect := _new_slice_effect("ExplosionEffect")
	var shell := _effect_sphere(effect, Color(1.0, 0.4, 0.06, 0.16))
	shell.scale = Vector3.ONE * 0.15
	var tween := effect.create_tween().set_parallel(true)
	tween.tween_property(shell, "scale", Vector3.ONE * EXPLOSION_RADIUS * power_multiplier, 0.4).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(shell.material_override, "albedo_color:a", 0.0, 0.4)
	_add_impact_rings(effect, EXPLOSION_RADIUS * power_multiplier, Color(1.0, 0.55, 0.1, 0.75), false, 0.4)
	tween.chain().tween_callback(effect.queue_free)

func _new_slice_effect(effect_name: String) -> SliceEffect:
	var effect := SliceEffect.new()
	effect.name = effect_name
	effect.impact_w = position_4d.w
	effect.owning_room = _source_room
	get_tree().current_scene.add_child(effect, true)
	effect.global_position = global_position
	return effect

func _effect_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.5
	return material

func _effect_sphere(effect: Node3D, color: Color) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	visual.mesh = sphere
	visual.material_override = _effect_material(color)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	effect.add_child(visual)
	return visual

func _add_impact_rings(effect: Node3D, radius: float, color: Color, inward: bool, duration: float) -> void:
	for axis in range(3):
		var visual := MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.inner_radius = 0.975
		ring.outer_radius = 1.0
		ring.rings = 32
		ring.ring_segments = 4
		visual.mesh = ring
		visual.material_override = _effect_material(color)
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.rotation = Vector3(PI * 0.5 if axis == 1 else 0.0, 0.0, PI * 0.5 if axis == 2 else 0.0)
		visual.scale = Vector3.ONE * (radius if inward else 0.15)
		effect.add_child(visual)
		var tween := visual.create_tween().set_parallel(true)
		tween.tween_property(visual, "scale", Vector3.ONE * (0.04 if inward else radius), duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN if inward else Tween.EASE_OUT)
		tween.tween_property(visual, "rotation:y", visual.rotation.y + PI * 0.7, duration)
		tween.tween_property(visual.material_override, "albedo_color:a", 0.0, duration)

func _add_impact_shards(effect: Node3D, radius: float, color: Color, inward: bool, duration: float) -> void:
	for index in range(16):
		# Golden-angle distribution is evenly spaced and stable for every impact.
		var vertical: float = 1.0 - 2.0 * (index + 0.5) / 16.0
		var radial: float = sqrt(1.0 - vertical * vertical)
		var angle: float = index * 2.399963
		var vector := Vector3(cos(angle) * radial, vertical, sin(angle) * radial)
		var shard := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(0.1, 0.4, 0.1)
		shard.mesh = prism
		shard.material_override = _effect_material(color)
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shard.position = vector * (radius if inward else 0.15)
		shard.rotation = Vector3(angle, angle * 0.5, angle)
		effect.add_child(shard)
		var tween := shard.create_tween().set_parallel(true)
		tween.tween_property(shard, "position", vector * (0.05 if inward else radius), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN if inward else Tween.EASE_OUT)
		tween.tween_property(shard, "rotation", shard.rotation + Vector3(2.0, 3.0, 1.0), duration)
		tween.tween_property(shard.material_override, "albedo_color:a", 0.0, duration)

## Compatibility entry point: ice bursts are cosmetic; only direct hits roll.
func _freeze_nearby() -> void:
	_spawn_freeze_effect()


## Spawn the translucent blue sphere visual effect for freezing
func _spawn_freeze_effect() -> void:
	var effect := _new_slice_effect("FreezeEffect")
	var color := Color(0.35, 0.85, 1.0, 0.85)
	_add_impact_rings(effect, FREEZE_RADIUS * power_multiplier, color, false, 0.55)
	_add_impact_shards(effect, FREEZE_RADIUS * power_multiplier, color, false, 0.65)
	var shell := _effect_sphere(effect, Color(0.35, 0.8, 1.0, 0.1))
	shell.scale = Vector3.ONE * FREEZE_RADIUS * power_multiplier
	var tween := effect.create_tween()
	tween.tween_property(shell.material_override, "albedo_color:a", 0.0, 0.7)
	tween.tween_callback(effect.queue_free)

## IMPLOSIVE: Pull targets toward impact point
func _implode_nearby() -> void:
	print("[Projectile] IMPLOSION!")
	
	# Spawn visual effect
	_spawn_implosion_effect()
	
	var radius := IMPLOSION_RADIUS * power_multiplier
	var nearby: Array[Node] = _get_nearby_targets(radius)
	var impact_point: Vector3 = global_position
	
	for target in nearby:
		# Calculate pull direction (toward impact)
		var pull_dir: Vector3 = (impact_point - target.global_position).normalized()
		
		# Force is stronger the closer they are
		var dist: float = global_position.distance_to(target.global_position)
		var force_mult: float = 1.0 - (dist / radius) * 0.5
		var force: Vector3 = pull_dir * IMPLOSION_FORCE * power_multiplier * force_mult
		
		if target.has_method("apply_external_force"):
			target.apply_external_force(force)
			print("[Projectile] Pulled %s toward impact" % target.name)


## Spawn the purple shrinking sphere visual effect for implosion
func _spawn_implosion_effect() -> void:
	var effect := _new_slice_effect("ImplosionEffect")
	var color := Color(0.75, 0.35, 1.0, 0.85)
	_add_impact_rings(effect, IMPLOSION_RADIUS * power_multiplier, color, true, 0.6)
	_add_impact_shards(effect, IMPLOSION_RADIUS * power_multiplier, color, true, 0.6)
	var core := _effect_sphere(effect, Color(0.35, 0.08, 0.65, 0.7))
	core.scale = Vector3.ONE * 0.45
	var tween := effect.create_tween().set_parallel(true)
	tween.tween_property(core, "scale", Vector3.ONE * 0.04, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(core.material_override, "albedo_color:a", 0.0, 0.7)
	tween.chain().tween_callback(effect.queue_free)

## ACCELERATING: Pierce through and split into two
func _pierce_and_split(_hit_enemy: Node) -> void:
	if damage <= 1.0:
		queue_free()
		return
	var right := direction.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.01:
		right = direction.cross(Vector3.FORWARD).normalized()
	var split_directions := [direction.rotated(right, SPLIT_ANGLE).normalized(), direction.rotated(right, -SPLIT_ANGLE).normalized()]
	for child_direction in split_directions:
		var child := Projectile.new()
		child.direction = child_direction
		child.speed = speed
		child.damage = damage * 0.5
		child.damage_type = damage_type
		child.shooter = shooter
		child.gun_stats = gun_stats
		child.velocity_w = velocity_w
		child.bounce_count = bounce_count
		child.homing_strength = homing_strength
		child.laser_guided = laser_guided
		child.power_multiplier = power_multiplier
		child.scale = scale
		child.lifetime = maxf(0.05, lifetime - _time_alive)
		child._source_room = _source_room
		child._source_room_id = _source_room_id
		child.hit_bodies = hit_bodies.duplicate()
		child._recent_hit_bodies = _recent_hit_bodies.duplicate()
		var spawn_pos: Vector3 = global_position + child_direction * IMPACT_CLEARANCE
		child._set_spawn_origin(spawn_pos)
		child.position_4d = Vector4D.from_vector3(spawn_pos, position_4d.w)
		get_tree().current_scene.add_child(child)
		var flagella := get_node_or_null("Flagella")
		if flagella:
			load("res://scripts/items/item_attachments.gd").decorate_projectile(child, flagella.get_child_count())
		child.launch(child_direction)
	queue_free()

## Factory method to create a projectile from gun stats
static func create_from_stats(stats: GunStats, origin: Vector3, dir: Vector3, shooter_node: Node = null, w_position: float = 0.0, roll_critical: bool = true) -> Projectile:
	var proj := Projectile.new()
	proj.gun_stats = stats
	proj.direction = dir.normalized()
	proj.speed = stats.get_scaled_projectile_speed()
	proj.damage = stats.get_scaled_damage()
	proj.damage_type = stats.gun_type
	proj.shooter = shooter_node
	proj._set_spawn_origin(origin)
	proj.position_4d = Vector4D.from_vector3(origin, w_position)
	
	# Crit check
	if roll_critical and stats.roll_crit():
		proj.damage *= stats.get_scaled_crit_damage()
		print("[Projectile] CRITICAL HIT!")
	
	return proj

## Factories run outside the tree; resolve world coordinates only after parenting.
func _set_spawn_origin(origin: Vector3) -> void:
	position = origin
	_pending_world_origin = origin
	_has_pending_world_origin = true

