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
	_base_scale = size / 0.15  # Store base scale for 4D scaling
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

func _physics_process(delta: float) -> void:
	# Move forward in 3D
	var movement: Vector3 = direction * speed * delta
	global_position += movement
	
	# Update 4D position (W stays same unless velocity_w is set)
	position_4d = Vector4D.from_vector3(global_position, position_4d.w + velocity_w * delta)
	
	# Raycast ahead to detect walls (backup for body_entered)
	_check_wall_collision(movement.length())
	
	# Track lifetime
	_time_alive += delta
	if _time_alive >= lifetime:
		queue_free()

## Check for wall collision - uses both raycast (for regular walls) and distance-based detection (for room spheres)
func _check_wall_collision(distance_moved: float) -> void:
	# Method 1: Check distance to room sphere walls (room spheres have no physics collision)
	for room in get_tree().get_nodes_in_group("room_spheres_4d"):
		if not room or not is_instance_valid(room):
			continue
		
		var room_center: Vector3 = room.global_position
		var room_radius: float = room.radius if room.get("radius") else 20.0
		var dist_to_center: float = global_position.distance_to(room_center)
		
		# First check: Are we actually inside this room sphere?
		# (inside = dist_to_center < room_radius)
		if dist_to_center >= room_radius:
			continue  # Not inside this room, skip it
		
		# We're inside this room - check if we're close to the wall
		var dist_to_wall: float = room_radius - dist_to_center
		if dist_to_wall < 1.5:  # Within 1.5 units of the wall
			print("[Projectile] Room sphere wall hit! (dist_to_wall=%.2f)" % dist_to_wall)
			_handle_wall_collision()
			return
	
	# Method 2: Raycast for regular physics walls (floors, ceilings, static bodies)
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space_state:
		var ray_length: float = max(distance_moved * 2.0, 0.5)
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			global_position - direction * 0.2,
			global_position + direction * ray_length
		)
		query.collision_mask = 1  # World layer
		query.exclude = []
		
		var result: Dictionary = space_state.intersect_ray(query)
		if result and result.position.distance_to(global_position) < 0.5:
			print("[Projectile] Physics wall hit detected!")
			_handle_wall_collision()

## Handle wall collision based on projectile type
func _handle_wall_collision() -> void:
	match damage_type:
		GunTypes.Type.EXPLOSIVE:
			_explode()
			queue_free()
		GunTypes.Type.FREEZING:
			_freeze_nearby()
			queue_free()
		GunTypes.Type.IMPLOSIVE:
			_implode_nearby()
			queue_free()
		GunTypes.Type.ACCELERATING:
			queue_free()  # Accelerating just stops on walls





func _on_body_entered(body: Node3D) -> void:
	# Don't hit shooter
	if body == shooter:
		return
	
	# Don't hit already-hit bodies (for piercing projectiles)
	if body in hit_bodies:
		return
	
	# Check if this is an enemy (has take_damage method)
	var is_enemy: bool = body.has_method("take_damage")
	
	# For enemies, do 4D hit check - verify W-distance
	if is_enemy:
		var target_w: float = 0.0
		if body.has_method("get_position_4d"):
			var target_4d: Vector4D = body.get_position_4d()
			target_w = target_4d.w
		elif "position_4d" in body:
			target_w = body.position_4d.w
		
		var w_distance: float = abs(position_4d.w - target_w)
		if w_distance > PROJECTILE_W_RADIUS:
			# Miss - target is in different W-slice
			print("[Projectile] Near miss - target is %.1f W-units away" % w_distance)
			return
		
		# Mark this body as hit
		hit_bodies.append(body)
		
		# Apply damage to the direct hit target
		body.take_damage(int(damage), damage_type)
		print("[Projectile] Hit %s for %d damage!" % [body.name, int(damage)])
	
	# Apply type-specific effects
	match damage_type:
		GunTypes.Type.EXPLOSIVE:
			# Explosive ALWAYS explodes on any collision (enemy, wall, ground)
			_explode()
			queue_free()
		GunTypes.Type.FREEZING:
			# Freezing explodes on any collision
			_freeze_nearby()
			queue_free()
		GunTypes.Type.IMPLOSIVE:
			# Implosive explodes on any collision
			_implode_nearby()
			queue_free()
		GunTypes.Type.ACCELERATING:
			if is_enemy:
				# Accelerating only pierces through enemies, not walls
				_pierce_and_split(body)
			else:
				# Hit a wall - just destroy
				queue_free()


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
	
	var nearby: Array[Node] = _get_nearby_targets(EXPLOSION_RADIUS)
	var impact_point: Vector3 = global_position
	
	for target in nearby:
		var dist: float = impact_point.distance_to(target.global_position)
		var falloff: float = 1.0 - (dist / EXPLOSION_RADIUS)
		
		# Apply splash damage (skip if already hit by direct impact)
		if target not in hit_bodies:
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
		var knockback_force: Vector3 = knockback_dir * EXPLOSION_KNOCKBACK * falloff
		
		if target.has_method("apply_external_force"):
			target.apply_external_force(knockback_force)
			print("[Projectile] Knocked back %s" % target.name)


## Spawn the expanding sphere visual effect for explosions
func _spawn_explosion_effect() -> void:
	var effect := Node3D.new()
	effect.name = "ExplosionEffect"
	effect.global_position = global_position
	
	# Create expanding sphere mesh
	var mesh_instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.1
	sphere.height = 0.2
	mesh_instance.mesh = sphere
	
	# Transparent orange material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.1, 0.6)  # Orange, semi-transparent
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.0)
	mat.emission_energy_multiplier = 2.0
	mesh_instance.material_override = mat
	
	effect.add_child(mesh_instance)
	get_tree().current_scene.add_child(effect)
	
	# Animate the expansion
	var tween := effect.create_tween()
	tween.set_parallel(true)
	
	# Expand to full radius
	tween.tween_property(mesh_instance, "scale", Vector3.ONE * EXPLOSION_RADIUS * 2.0, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	
	# Fade out
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.3).set_ease(Tween.EASE_IN)
	tween.tween_property(mat, "emission_energy_multiplier", 0.0, 0.3)
	
	# Destroy after animation
	tween.chain().tween_callback(effect.queue_free)


## FREEZING: Freeze nearby targets
func _freeze_nearby() -> void:
	print("[Projectile] FREEZE BURST!")
	
	# Spawn visual effect
	_spawn_freeze_effect()
	
	var nearby: Array[Node] = _get_nearby_targets(FREEZE_RADIUS)
	
	for target in nearby:
		if target.has_method("freeze"):
			target.freeze(FREEZE_DURATION)
			print("[Projectile] Froze %s" % target.name)


## Spawn the translucent blue sphere visual effect for freezing
func _spawn_freeze_effect() -> void:
	var effect := Node3D.new()
	effect.name = "FreezeEffect"
	effect.global_position = global_position
	
	# Create sphere mesh at full radius immediately
	var mesh_instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = FREEZE_RADIUS
	sphere.height = FREEZE_RADIUS * 2.0
	mesh_instance.mesh = sphere
	
	# Translucent blue material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.8, 1.0, 0.5)  # Cyan, semi-transparent
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.8, 1.0)
	mat.emission_energy_multiplier = 1.5
	mesh_instance.material_override = mat
	
	effect.add_child(mesh_instance)
	get_tree().current_scene.add_child(effect)
	
	# Animate a brief flash then fade
	var tween := effect.create_tween()
	tween.set_parallel(true)
	
	# Quick fade out
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.25).set_ease(Tween.EASE_IN)
	tween.tween_property(mat, "emission_energy_multiplier", 0.0, 0.25)
	
	# Destroy after animation
	tween.chain().tween_callback(effect.queue_free)


## IMPLOSIVE: Pull targets toward impact point
func _implode_nearby() -> void:
	print("[Projectile] IMPLOSION!")
	
	# Spawn visual effect
	_spawn_implosion_effect()
	
	var nearby: Array[Node] = _get_nearby_targets(IMPLOSION_RADIUS)
	var impact_point: Vector3 = global_position
	
	for target in nearby:
		# Calculate pull direction (toward impact)
		var pull_dir: Vector3 = (impact_point - target.global_position).normalized()
		
		# Force is stronger the closer they are
		var dist: float = global_position.distance_to(target.global_position)
		var force_mult: float = 1.0 - (dist / IMPLOSION_RADIUS) * 0.5
		var force: Vector3 = pull_dir * IMPLOSION_FORCE * force_mult
		
		if target.has_method("apply_external_force"):
			target.apply_external_force(force)
			print("[Projectile] Pulled %s toward impact" % target.name)


## Spawn the purple shrinking sphere visual effect for implosion
func _spawn_implosion_effect() -> void:
	var effect := Node3D.new()
	effect.name = "ImplosionEffect"
	effect.global_position = global_position
	
	# Create sphere mesh starting at full radius
	var mesh_instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.1
	sphere.height = 0.2
	mesh_instance.mesh = sphere
	mesh_instance.scale = Vector3.ONE * IMPLOSION_RADIUS * 2.0  # Start big
	
	# Translucent purple material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.2, 1.0, 0.6)  # Purple, semi-transparent
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.1, 0.9)
	mat.emission_energy_multiplier = 2.0
	mesh_instance.material_override = mat
	
	effect.add_child(mesh_instance)
	get_tree().current_scene.add_child(effect)
	
	# Animate the shrink (opposite of explosion)
	var tween := effect.create_tween()
	tween.set_parallel(true)
	
	# Shrink to zero
	tween.tween_property(mesh_instance, "scale", Vector3.ZERO, 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_EXPO)
	
	# Fade out
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.25).set_ease(Tween.EASE_IN)
	tween.tween_property(mat, "emission_energy_multiplier", 0.0, 0.25)
	
	# Destroy after animation
	tween.chain().tween_callback(effect.queue_free)


## ACCELERATING: Pierce through and split into two
func _pierce_and_split(hit_enemy: Node) -> void:
	print("[Projectile] PIERCE!")
	
	# Check if we can split (damage > 1)
	if damage <= 1:
		print("[Projectile] Minimum damage reached, no more splitting")
		queue_free()
		return
	
	# Create two child projectiles with half damage
	var half_damage: float = damage / 2.0
	
	# Calculate split directions (rotate from current direction)
	var right: Vector3 = direction.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.01:
		right = direction.cross(Vector3.FORWARD).normalized()
	
	var dir_left: Vector3 = direction.rotated(right, SPLIT_ANGLE).normalized()
	var dir_right: Vector3 = direction.rotated(right, -SPLIT_ANGLE).normalized()
	
	# Spawn child projectiles
	var spawn_pos: Vector3 = global_position + direction * 0.5  # Slightly ahead
	
	var child1: Projectile = Projectile.new()
	child1.direction = dir_left
	child1.speed = speed
	child1.damage = half_damage
	child1.damage_type = damage_type
	child1.shooter = shooter
	child1.global_position = spawn_pos
	child1.position_4d = Vector4D.from_vector3(spawn_pos, position_4d.w)
	child1.hit_bodies = hit_bodies.duplicate()  # Inherit hit list
	
	var child2: Projectile = Projectile.new()
	child2.direction = dir_right
	child2.speed = speed
	child2.damage = half_damage
	child2.damage_type = damage_type
	child2.shooter = shooter
	child2.global_position = spawn_pos
	child2.position_4d = Vector4D.from_vector3(spawn_pos, position_4d.w)
	child2.hit_bodies = hit_bodies.duplicate()  # Inherit hit list
	
	# Add children to scene
	get_tree().current_scene.add_child(child1)
	get_tree().current_scene.add_child(child2)
	
	print("[Projectile] Split into 2 projectiles with %.1f damage each" % half_damage)
	
	# Destroy parent
	queue_free()


## Factory method to create a projectile from gun stats
static func create_from_stats(stats: GunStats, origin: Vector3, dir: Vector3, shooter_node: Node = null, w_position: float = 0.0) -> Projectile:
	var proj := Projectile.new()
	proj.gun_stats = stats
	proj.direction = dir.normalized()
	proj.speed = stats.get_scaled_projectile_speed()
	proj.damage = stats.get_scaled_damage()
	proj.damage_type = stats.gun_type
	proj.shooter = shooter_node
	proj.global_position = origin
	proj.position_4d = Vector4D.from_vector3(origin, w_position)
	
	# Crit check
	if stats.roll_crit():
		proj.damage *= stats.get_scaled_crit_damage()
		print("[Projectile] CRITICAL HIT!")
	
	return proj

