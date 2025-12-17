# Enemy4D_P - Enemy that stays at Player's W axis (doesn't use 4D slicing visibility)
# Uses SurfaceWalker4D for movement with sticky gravity on hyperspheres etc.
class_name Enemy4DP
extends CharacterBody3D

signal died(enemy: Enemy4DP)
signal damaged(current_health: int, max_health: int)

@export_group("Stats")
@export var max_health: int = 50
@export var move_speed: float = 3.0
@export var enemy_type: GunTypes.Type = GunTypes.Type.EXPLOSIVE

@export_group("AI")
@export var spin_speed: float = 2.0
@export var view_range: float = 15.0
@export var view_angle: float = 60.0
@export var attack_range: float = 12.0
@export var fire_rate: float = 1.0

@export_group("4D Settings")
## Enable 4D movement on surfaces
@export var enable_4d_mode: bool = true
## Initial W coordinate
@export var initial_w: float = 0.0

enum State { SEARCHING, CHASING, ATTACKING }

var current_state: State = State.SEARCHING
var current_health: int
var target: Node3D = null
var fire_cooldown: float = 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# 4D Components
var position_4d: Vector4D = Vector4D.zero()
var surface_walker: SurfaceWalker4D = null

# Gun for drops and attacks
var gun_stats: GunStats

func _ready() -> void:
	current_health = max_health
	add_to_group("enemies")
	
	# Create visual mesh if not already present
	if get_node_or_null("MeshInstance3D") == null:
		_create_visual()
	
	# Create collision shape if not already present  
	if get_node_or_null("CollisionShape3D") == null:
		_create_collision()
	
	# Setup gun
	gun_stats = GunStats.new()
	gun_stats.gun_name = "Enemy Pup"
	gun_stats.gun_type = enemy_type
	gun_stats.rarity = GunTypes.Rarity.POOR
	
	# Initialize 4D mode
	if enable_4d_mode:
		_init_4d_mode()
	
	# Find player after a frame
	await get_tree().process_frame
	_find_target()

func _create_visual() -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "MeshInstance3D"
	
	# Create a capsule mesh (enemy body)
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.5
	mesh_instance.mesh = capsule
	
	# Red/orange enemy material based on type
	var mat := StandardMaterial3D.new()
	match enemy_type:
		GunTypes.Type.EXPLOSIVE:
			mat.albedo_color = Color(1.0, 0.3, 0.1)  # Orange-red
		GunTypes.Type.IMPLOSIVE:
			mat.albedo_color = Color(0.6, 0.1, 0.8)  # Purple
		GunTypes.Type.FREEZING:
			mat.albedo_color = Color(0.2, 0.6, 1.0)  # Ice blue
		GunTypes.Type.ACCELERATING:
			mat.albedo_color = Color(0.2, 1.0, 0.4)  # Green
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = 0.3
	mesh_instance.material_override = mat
	
	# Position mesh so it stands on ground
	mesh_instance.position.y = 0.75
	add_child(mesh_instance)
	
	# Create gun mesh (cylinder)
	var gun_mesh := MeshInstance3D.new()
	gun_mesh.name = "GunMesh"
	var gun_cyl := CylinderMesh.new()
	gun_cyl.top_radius = 0.05
	gun_cyl.bottom_radius = 0.08
	gun_cyl.height = 0.5
	gun_mesh.mesh = gun_cyl
	gun_mesh.rotation_degrees.x = 90  # Point forward
	gun_mesh.position = Vector3(0.3, 0.9, -0.3)  # Right side, chest height, forward
	
	var gun_mat := StandardMaterial3D.new()
	gun_mat.albedo_color = Color(0.2, 0.2, 0.2)
	gun_mat.metallic = 0.8
	gun_mesh.material_override = gun_mat
	add_child(gun_mesh)
	
	# Create muzzle flash (initially invisible)
	var muzzle := MeshInstance3D.new()
	muzzle.name = "MuzzleFlash"
	var muzzle_sphere := SphereMesh.new()
	muzzle_sphere.radius = 0.15
	muzzle_sphere.height = 0.3
	muzzle.mesh = muzzle_sphere
	muzzle.position = Vector3(0.3, 0.9, -0.6)
	
	var muzzle_mat := StandardMaterial3D.new()
	muzzle_mat.albedo_color = Color(1.0, 0.8, 0.2)
	muzzle_mat.emission_enabled = true
	muzzle_mat.emission = Color(1.0, 0.6, 0.1)
	muzzle_mat.emission_energy_multiplier = 3.0
	muzzle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	muzzle_mat.albedo_color.a = 0.8
	muzzle.material_override = muzzle_mat
	muzzle.visible = false
	add_child(muzzle)
	
	print("[Enemy4D] Created visual mesh")

func _create_collision() -> void:
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.5
	collision.shape = shape
	collision.position.y = 0.75
	
	add_child(collision)
	print("[Enemy4D] Created collision shape")

func _init_4d_mode() -> void:
	surface_walker = SurfaceWalker4D.new()
	surface_walker.move_speed = move_speed
	surface_walker.jump_velocity = 4.0
	surface_walker.auto_process = false  # We control physics manually
	add_child(surface_walker)
	
	# Set initial 4D position
	position_4d = Vector4D.from_vector3(global_position, initial_w)
	surface_walker.set_position(position_4d)
	
	# Connect signals (we won't use these since we control position directly)
	# surface_walker.position_changed.connect(_on_4d_position_changed)
	
	# Register with slicer for visibility
	call_deferred("_register_with_slicer")

func _register_with_slicer() -> void:
	var slicers = get_tree().get_nodes_in_group("slicer_4d")
	if slicers.size() > 0:
		var slicer: Slicer4D = slicers[0] as Slicer4D
		if slicer:
			slicer.slice_changed.connect(_on_slice_changed)
			_update_visibility(slicer.slice_w)

func _on_slice_changed(slice_w: float) -> void:
	_current_slice_w = slice_w
	_update_slice_visibility(slice_w)

## Current slice W value (for attack checks)
var _current_slice_w: float = 0.0

## Enemy "thickness" in W dimension (smaller than hypersphere)
const ENEMY_W_RADIUS: float = 2.0

func _update_slice_visibility(slice_w: float) -> void:
	var w_distance: float = abs(position_4d.w - slice_w)
	
	if w_distance >= ENEMY_W_RADIUS:
		# Enemy is outside the slice - invisible
		visible = false
		set_physics_process(false)
		return
	
	# Calculate scale based on W distance (like hypersphere cross-section)
	# At w_distance=0, scale=1.0; at w_distance=ENEMY_W_RADIUS, scale=0
	var scale_factor: float = sqrt(1.0 - (w_distance / ENEMY_W_RADIUS) * (w_distance / ENEMY_W_RADIUS))
	scale_factor = max(scale_factor, 0.1)  # Minimum scale to stay visible
	
	# Apply scale to mesh
	var mesh_node = get_node_or_null("MeshInstance3D")
	if mesh_node:
		mesh_node.scale = Vector3(scale_factor, scale_factor, scale_factor)
	
	# Scale gun mesh too
	var gun_node = get_node_or_null("GunMesh")
	if gun_node:
		gun_node.scale = Vector3(scale_factor, scale_factor, scale_factor)
	
	# Scale collision shape
	var collision_node = get_node_or_null("CollisionShape3D")
	if collision_node:
		collision_node.scale = Vector3(scale_factor, scale_factor, scale_factor)
	
	visible = true
	set_physics_process(true)

## Check if enemy can attack (must be in similar W position as target)
func _can_attack_target() -> bool:
	if not target:
		return false
	
	# Check W distance to target
	var target_w: float = 0.0
	if target.has_method("get_position_4d"):
		var target_4d: Vector4D = target.get_position_4d()
		target_w = target_4d.w
	
	var w_diff: float = abs(position_4d.w - target_w)
	return w_diff < ENEMY_W_RADIUS * 1.5  # Small tolerance

## Legacy function name for compatibility
func _update_visibility(slice_w: float) -> void:
	_update_slice_visibility(slice_w)

func _find_target() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		target = players[0]

func _physics_process(delta: float) -> void:
	if fire_cooldown > 0:
		fire_cooldown -= delta
	
	# Check if we should use 4D physics (only if surfaces exist)
	var use_4d_physics: bool = enable_4d_mode and surface_walker and surface_walker.physics.surfaces.size() > 0
	
	if use_4d_physics:
		_physics_process_4d(delta)
	else:
		_physics_process_3d(delta)

func _physics_process_3d(delta: float) -> void:
	# Standard 3D movement
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	match current_state:
		State.SEARCHING:
			_state_searching(delta)
		State.CHASING:
			_state_chasing_3d(delta)
		State.ATTACKING:
			_state_attacking(delta)
	
	move_and_slide()

func _physics_process_4d(delta: float) -> void:
	# Check if we're close to a 4D surface
	var near_4d_surface: bool = _is_near_4d_surface()
	
	# 4D surface-based movement (AI states)
	match current_state:
		State.SEARCHING:
			_state_searching(delta)
		State.CHASING:
			_state_chasing_4d(delta)
		State.ATTACKING:
			_state_attacking(delta)
	
	if near_4d_surface:
		# Use 4D sticky gravity - manually process SurfaceWalker4D physics
		if surface_walker:
			surface_walker.process_physics(delta)
			var velocity_4d: Vector4D = surface_walker.get_velocity()
			velocity = velocity_4d.to_vector3()
		
		# Still use move_and_slide for wall collision
		move_and_slide()
		
		# Sync back to 4D
		position_4d = Vector4D.from_vector3(global_position, position_4d.w)
		if surface_walker:
			surface_walker.set_position(position_4d)
		
		# Orient to match 4D surface
		if surface_walker:
			var grav_dir: Vector4D = surface_walker.get_gravity_direction()
			var up_dir: Vector3 = grav_dir.negate().to_vector3()
			if up_dir.length_squared() > 0.01:
				var current_up: Vector3 = global_transform.basis.y
				var angle_diff: float = current_up.angle_to(up_dir)
				if angle_diff > 0.01:
					var axis: Vector3 = current_up.cross(up_dir).normalized()
					if axis.length_squared() > 0.01:
						rotate(axis, angle_diff * delta * 5.0)
	else:
		# Use standard 3D physics - normal Y-down gravity
		if not is_on_floor():
			velocity.y -= gravity * delta
		
		# Use CharacterBody3D physics
		move_and_slide()
		
		# Update 4D position to match 3D (keep W the same)
		position_4d = Vector4D.from_vector3(global_position, position_4d.w)
		if surface_walker:
			surface_walker.set_position(position_4d)
			# Reset 4D velocity to match 3D
			surface_walker.physics.velocity = Vector4D.from_vector3(velocity, 0.0)

## Check if enemy is close enough to a 4D surface to use sticky gravity
func _is_near_4d_surface() -> bool:
	if not surface_walker or surface_walker.physics.surfaces.is_empty():
		return false
	
	var threshold: float = 3.0  # Distance to switch to 4D gravity
	
	for surface in surface_walker.physics.surfaces:
		if surface and is_instance_valid(surface):
			var dist: float = abs(surface.get_signed_distance(position_4d))
			if dist < threshold:
				return true
	
	return false

func _state_searching(delta: float) -> void:
	# Spin looking for player
	rotate_y(spin_speed * delta)
	
	if surface_walker:
		surface_walker.set_input(Vector3.ZERO)
	else:
		velocity.x = 0
		velocity.z = 0
	
	# Check if we can see player
	if target and _can_see_target():
		current_state = State.CHASING
		print("[Enemy4D] Spotted player!")

func _state_chasing_3d(delta: float) -> void:
	if not target:
		current_state = State.SEARCHING
		return
	
	if not _can_see_target():
		current_state = State.SEARCHING
		return
	
	var distance: float = global_position.distance_to(target.global_position)
	var direction: Vector3 = (target.global_position - global_position).normalized()
	direction.y = 0
	
	if direction.length() > 0.1:
		look_at(global_position + direction)
	
	if distance <= attack_range:
		current_state = State.ATTACKING
		velocity.x = 0
		velocity.z = 0
	else:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed

func _state_chasing_4d(delta: float) -> void:
	if not target:
		current_state = State.SEARCHING
		return
	
	if not _can_see_target():
		current_state = State.SEARCHING
		return
	
	var distance: float = global_position.distance_to(target.global_position)
	var direction: Vector3 = (target.global_position - global_position).normalized()
	
	# Face target (projected onto surface tangent)
	if direction.length() > 0.1:
		var look_pos: Vector3 = global_position + direction
		look_pos.y = global_position.y  # Keep level with surface
		look_at(look_pos)
	
	if distance <= attack_range:
		current_state = State.ATTACKING
		if surface_walker:
			surface_walker.set_input(Vector3.ZERO)
	else:
		# Move toward target using surface walker
		if surface_walker:
			# Convert world direction to local input
			var local_dir: Vector3 = global_transform.basis.inverse() * direction
			surface_walker.set_input(Vector3(local_dir.x, 0, local_dir.z).normalized())

func _state_attacking(delta: float) -> void:
	if not target:
		current_state = State.SEARCHING
		return
	
	var distance: float = global_position.distance_to(target.global_position)
	var direction: Vector3 = (target.global_position - global_position).normalized()
	
	# Face target
	if direction.length() > 0.1:
		var look_pos: Vector3 = global_position + direction
		look_at(look_pos)
	
	# Stop moving
	if surface_walker:
		surface_walker.set_input(Vector3.ZERO)
	else:
		velocity.x = 0
		velocity.z = 0
	
	# Check if player moved out of range
	if distance > attack_range * 1.2:
		current_state = State.CHASING
		return
	
	# Lost sight
	if not _can_see_target():
		current_state = State.SEARCHING
		return
	
	# Fire only if in same W slice
	if fire_cooldown <= 0 and _can_attack_target():
		_fire_at_target()
		fire_cooldown = fire_rate

func _can_see_target() -> bool:
	if not target:
		return false
	
	var to_target: Vector3 = target.global_position - global_position
	var distance: float = to_target.length()
	
	if distance > view_range:
		return false
	
	var forward: Vector3 = -global_transform.basis.z
	var angle: float = rad_to_deg(forward.angle_to(to_target.normalized()))
	if angle > view_angle:
		return false
	
	# 4D check: also need to be in same W-slice
	if enable_4d_mode and target.has_method("get_position_4d"):
		var target_4d: Vector4D = target.get_position_4d()
		var w_diff: float = abs(position_4d.w - target_4d.w)
		if w_diff > 3.0:  # W visibility threshold
			return false
	
	# Raycast for obstacles
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 1, 0),
		target.global_position + Vector3(0, 1, 0)
	)
	query.exclude = [self]
	
	var result: Dictionary = space_state.intersect_ray(query)
	if result and result.collider == target:
		return true
	
	return result.is_empty()

func _fire_at_target() -> void:
	if not target:
		return
	
	print("[Enemy4D] BANG!")
	
	# Show muzzle flash
	var muzzle = get_node_or_null("MuzzleFlash")
	if muzzle:
		muzzle.visible = true
		# Hide after a short delay
		get_tree().create_timer(0.1).timeout.connect(func(): 
			if muzzle and is_instance_valid(muzzle):
				muzzle.visible = false
		)
	
	# Spawn visible projectile instead of hitscan
	if target:
		var shoot_dir: Vector3 = (target.global_position - global_position).normalized()
		var muzzle_pos: Vector3 = global_position + Vector3(0, 0.9, 0) + shoot_dir * 0.6
		
		# Add some inaccuracy based on gun stats
		var spread: float = (1.0 - gun_stats.accuracy) * 0.2
		shoot_dir.x += randf_range(-spread, spread)
		shoot_dir.y += randf_range(-spread, spread)
		shoot_dir.z += randf_range(-spread, spread)
		shoot_dir = shoot_dir.normalized()
		
		var projectile: Projectile = Projectile.create_from_stats(gun_stats, muzzle_pos, shoot_dir, self, position_4d.w)
		get_tree().current_scene.add_child(projectile)

func _on_4d_position_changed(new_pos: Vector4D) -> void:
	position_4d = new_pos
	global_position = new_pos.to_vector3()

func take_damage(amount: int, damage_type: GunTypes.Type) -> void:
	var effectiveness: float = GunTypes.get_effectiveness(damage_type, enemy_type)
	var final_damage: int = int(amount * effectiveness)
	
	current_health -= final_damage
	current_health = max(current_health, 0)
	
	damaged.emit(current_health, max_health)
	
	# Wake up if hit while searching
	if current_state == State.SEARCHING and target:
		current_state = State.CHASING
	
	print("[Enemy4D] %d damage (%d%%), HP: %d/%d" % [
		final_damage, int(effectiveness * 100), current_health, max_health
	])
	
	if current_health <= 0:
		_die()

func _die() -> void:
	print("[Enemy4D] Died! Dropping: %s" % gun_stats.get_display_name())
	died.emit(self)
	GameManager.enemy_killed()
	queue_free()

# Get 4D position for visibility checks
func get_position_4d() -> Vector4D:
	return position_4d

# Set 4D position
func set_position_4d(pos: Vector4D) -> void:
	position_4d = pos
	if surface_walker:
		surface_walker.set_position(pos)
	global_position = pos.to_vector3()
