# Enemy4D - Base class for enemies that can navigate 4D surfaces
# Uses SurfaceWalker4D for movement with sticky gravity on hyperspheres etc.
class_name Enemy4D
extends CharacterBody3D

signal died(enemy: Enemy4D)
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
var aggro_enabled: bool = true  # When false, enemy won't spot or chase player

# Status effects
var frozen_timer: float = 0.0  # Time remaining frozen
var external_velocity: Vector3 = Vector3.ZERO  # Applied by implosive/knockback effects
const EXTERNAL_VELOCITY_DECAY: float = 5.0  # How fast external velocity decays

# Stuck detection
var _last_position: Vector3 = Vector3.ZERO
var _stuck_timer: float = 0.0
var _escape_timer: float = 0.0
var _is_escaping: bool = false
var _escape_direction: Vector3 = Vector3.ZERO
var _floor_only_mode: bool = false  # When true, permanently ignore 4D gravity until back on hypersphere
const STUCK_THRESHOLD: float = 0.1  # Minimum distance to move per check
const STUCK_TIME: float = 0.5  # Time without movement to be considered stuck
const ESCAPE_TIME: float = 1.0  # How long to escape for

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
	
	# Update health bar to show full health
	call_deferred("_update_health_bar")
	
	# Check global aggro state from debug console
	call_deferred("_check_global_aggro")
	
	# Find player after a frame
	await get_tree().process_frame
	_find_target()

## Check global aggro state from debug console
func _check_global_aggro() -> void:
	var debug_console = get_tree().get_first_node_in_group("debug_console")
	if debug_console and "aggro_enabled" in debug_console:
		aggro_enabled = debug_console.aggro_enabled

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
	
	# Create health bar above head
	_create_health_bar()
	
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
	
	# Set collision layers: Layer 4 = enemies
	# Collide with world (1) and player (2) for physics-based gameplay
	collision_layer = 4  # Enemy layer
	collision_mask = 1 | 2  # Collide with world and player
	
	print("[Enemy4D] Created collision shape")

var health_bar_fill: MeshInstance3D

func _create_health_bar() -> void:
	# Health bar container
	var health_bar_container := Node3D.new()
	health_bar_container.name = "HealthBarContainer"
	health_bar_container.position = Vector3(0, 2.2, 0)  # Above head
	add_child(health_bar_container)
	
	# Background (dark quad)
	var bg := MeshInstance3D.new()
	bg.name = "HealthBarBG"
	var bg_mesh := QuadMesh.new()
	bg_mesh.size = Vector2(1.0, 0.15)
	bg.mesh = bg_mesh
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.1, 0.1, 0.1, 0.8)
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED  # Always face camera
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.no_depth_test = true  # Always visible
	bg.material_override = bg_mat
	health_bar_container.add_child(bg)
	
	# Fill (colored bar)
	health_bar_fill = MeshInstance3D.new()
	health_bar_fill.name = "HealthBarFill"
	var fill_mesh := QuadMesh.new()
	fill_mesh.size = Vector2(0.95, 0.12)
	health_bar_fill.mesh = fill_mesh
	var fill_mat := StandardMaterial3D.new()
	fill_mat.albedo_color = Color(0.2, 0.9, 0.2)  # Green
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED  # Always face camera
	fill_mat.emission_enabled = true
	fill_mat.emission = Color(0.2, 0.9, 0.2)
	fill_mat.emission_energy_multiplier = 1.0
	fill_mat.no_depth_test = true  # Always visible
	health_bar_fill.material_override = fill_mat
	health_bar_fill.position.z = 0.01  # Slightly in front
	health_bar_container.add_child(health_bar_fill)

func _update_health_bar() -> void:
	if not health_bar_fill:
		return
	
	var health_percent: float = float(current_health) / float(max_health)
	
	# Update mesh size directly (scale doesn't work with billboard)
	var fill_mesh: QuadMesh = health_bar_fill.mesh as QuadMesh
	if fill_mesh:
		fill_mesh.size.x = 0.95 * max(health_percent, 0.01)
	
	# Color based on health
	var mat: StandardMaterial3D = health_bar_fill.material_override as StandardMaterial3D
	if mat:
		if health_percent < 0.25:
			mat.albedo_color = Color(0.9, 0.2, 0.2)  # Red
			mat.emission = Color(0.9, 0.2, 0.2)
		elif health_percent < 0.5:
			mat.albedo_color = Color(0.9, 0.6, 0.2)  # Orange
			mat.emission = Color(0.9, 0.6, 0.2)
		else:
			mat.albedo_color = Color(0.2, 0.9, 0.2)  # Green
			mat.emission = Color(0.2, 0.9, 0.2)

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
	
	# Handle frozen state
	if frozen_timer > 0:
		frozen_timer -= delta
		# Still apply external velocity even when frozen
		if external_velocity.length_squared() > 0.01:
			velocity = external_velocity
			external_velocity = external_velocity.lerp(Vector3.ZERO, EXTERNAL_VELOCITY_DECAY * delta)
			move_and_slide()
		return  # Skip all AI logic when frozen
	
	# Decay external velocity
	if external_velocity.length_squared() > 0.01:
		velocity += external_velocity
		external_velocity = external_velocity.lerp(Vector3.ZERO, EXTERNAL_VELOCITY_DECAY * delta)
	
	# Update visibility based on current slice (every frame for smooth scaling)
	var slicers = get_tree().get_nodes_in_group("slicer_4d")
	if slicers.size() > 0:
		var slicer: Slicer4D = slicers[0] as Slicer4D
		if slicer and slicer.scroll_4d_enabled:
			_update_slice_visibility(slicer.slice_w)
		else:
			# 4D mode not active - ensure full visibility
			_reset_to_full_visibility()
	else:
		# No slicer - ensure full visibility
		_reset_to_full_visibility()
	
	# Check if we should use 4D physics (only if surfaces exist)
	var use_4d_physics: bool = enable_4d_mode and surface_walker and surface_walker.physics.surfaces.size() > 0
	
	if use_4d_physics:
		_physics_process_4d(delta)
	else:
		_physics_process_3d(delta)

func _reset_to_full_visibility() -> void:
	visible = true
	var mesh_node = get_node_or_null("MeshInstance3D")
	if mesh_node:
		mesh_node.scale = Vector3.ONE
	var gun_node = get_node_or_null("GunMesh")
	if gun_node:
		gun_node.scale = Vector3.ONE
	var collision_node = get_node_or_null("CollisionShape3D")
	if collision_node:
		collision_node.scale = Vector3.ONE

func _physics_process_3d(delta: float) -> void:
	# First check if we're inside a RoomSphere4D
	if _handle_room_sphere_interior(delta):
		# AI states still need processing
		match current_state:
			State.SEARCHING:
				_state_searching(delta)
			State.CHASING:
				_state_chasing_3d(delta)
			State.ATTACKING:
				_state_attacking(delta)
		return
	
	# Standard 3D movement (not in room sphere)
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
	# === STUCK DETECTION ===
	# Check if we've moved since last frame
	var distance_moved: float = global_position.distance_to(_last_position)
	
	if _is_escaping:
		# Currently escaping - use floor gravity only and move away from hypersphere
		_escape_timer -= delta
		if _escape_timer <= 0:
			_is_escaping = false
			_stuck_timer = 0.0
			_floor_only_mode = true  # Switch to permanent floor mode until on hypersphere
			print("[Enemy4D] Escape complete - floor-only mode until back on hypersphere")
		else:
			# Escape movement - use standard 3D physics ONLY (ignore 4D surfaces)
			up_direction = Vector3.UP
			floor_snap_length = 0.1
			floor_stop_on_slope = true
			
			if not is_on_floor():
				velocity.y -= gravity * delta
			
			# Move away from hypersphere
			velocity.x = _escape_direction.x * move_speed * 2.0
			velocity.z = _escape_direction.z * move_speed * 2.0
			
			move_and_slide()
			_last_position = global_position
			return
	
	# First check if we're inside a RoomSphere4D - this takes priority
	if _handle_room_sphere_interior(delta):
		# AI states still need processing
		match current_state:
			State.SEARCHING:
				_state_searching(delta)
			State.CHASING:
				_state_chasing_3d(delta)  # Use 3D chasing inside room sphere
			State.ATTACKING:
				_state_attacking(delta)
		_last_position = global_position
		return
	
	# Check if we should exit floor-only mode (properly on a 4D surface now)
	if _floor_only_mode:
		if _is_properly_on_4d_surface():
			_floor_only_mode = false
			print("[Enemy4D] Now properly on hypersphere - enabling 4D gravity")
	
	if current_state == State.CHASING and distance_moved < STUCK_THRESHOLD and not _floor_only_mode:
		_stuck_timer += delta
		if _stuck_timer >= STUCK_TIME:
			# We're stuck! Calculate escape direction (away from nearest hypersphere)
			_is_escaping = true
			_escape_timer = ESCAPE_TIME
			_escape_direction = _get_escape_direction()
			print("[Enemy4D] STUCK! Escaping away from hypersphere...")
	else:
		_stuck_timer = 0.0
	
	_last_position = global_position
	
	# Check if we're close to a 4D surface (but not in floor-only mode!)
	var near_4d_surface: bool = _is_near_4d_surface() and not _floor_only_mode
	
	# 4D surface-based movement (AI states)
	# In floor-only mode, use 3D chasing to completely avoid surface walker
	match current_state:
		State.SEARCHING:
			_state_searching(delta)
		State.CHASING:
			if _floor_only_mode:
				_state_chasing_3d(delta)  # Use 3D chase in floor-only mode
			else:
				_state_chasing_4d(delta)
		State.ATTACKING:
			_state_attacking(delta)
	
	if near_4d_surface:
		# Use 4D sticky gravity - manually process SurfaceWalker4D physics
		if surface_walker:
			surface_walker.process_physics(delta)
			var velocity_4d: Vector4D = surface_walker.get_velocity()
			velocity = velocity_4d.to_vector3()
			
			# Set up_direction to match 4D surface normal (opposite of gravity)
			var grav_dir: Vector4D = surface_walker.get_gravity_direction()
			var up_dir: Vector3 = grav_dir.negate().to_vector3().normalized()
			if up_dir.length_squared() > 0.01:
				up_direction = up_dir
		
		# Disable floor snap to prevent CharacterBody3D from fighting 4D gravity
		floor_snap_length = 0.0
		floor_stop_on_slope = false
		
		# Use move_and_slide for collision only (not floor logic)
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
		up_direction = Vector3.UP
		floor_snap_length = 0.1
		floor_stop_on_slope = true
		
		if not is_on_floor():
			velocity.y -= gravity * delta
		
		# Use CharacterBody3D physics
		move_and_slide()
		
		# Update 4D position to match 3D (keep W the same) - but skip in floor-only mode
		if not _floor_only_mode:
			position_4d = Vector4D.from_vector3(global_position, position_4d.w)
			if surface_walker:
				surface_walker.set_position(position_4d)
				# Reset 4D velocity to match 3D
				surface_walker.physics.velocity = Vector4D.from_vector3(velocity, 0.0)

## Check if enemy is close enough to a 4D surface to use sticky gravity
func _is_near_4d_surface() -> bool:
	if not surface_walker or surface_walker.physics.surfaces.is_empty():
		return false
	
	# Large threshold to stay on hypersphere (must be bigger than sphere radius + some margin)
	var threshold: float = 12.0  # Distance to switch to 4D gravity
	
	for surface in surface_walker.physics.surfaces:
		if surface and is_instance_valid(surface):
			var dist: float = abs(surface.get_signed_distance(position_4d))
			if dist < threshold:
				return true
	
	return false

## Check if enemy is properly on a 4D surface (close enough to walk on it)
## This is used to re-enable 4D gravity after escaping
func _is_properly_on_4d_surface() -> bool:
	if not surface_walker or surface_walker.physics.surfaces.is_empty():
		return false
	
	# Very close threshold - must be actually touching the surface
	var threshold: float = 1.5
	
	for surface in surface_walker.physics.surfaces:
		if surface and is_instance_valid(surface):
			var dist: float = abs(surface.get_signed_distance(position_4d))
			if dist < threshold:
				return true
	
	return false

## Get direction to escape away from nearest 4D surface (hypersphere)
func _get_escape_direction() -> Vector3:
	if not surface_walker or surface_walker.physics.surfaces.is_empty():
		# No surfaces - just move randomly
		return Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	
	# Find nearest surface and move away from its center
	var nearest_dist: float = INF
	var escape_dir: Vector3 = Vector3.ZERO
	
	for surface in surface_walker.physics.surfaces:
		if surface and is_instance_valid(surface):
			var dist: float = abs(surface.get_signed_distance(position_4d))
			if dist < nearest_dist:
				nearest_dist = dist
				# Direction from surface center to enemy (in 3D)
				var surface_center: Vector3 = surface.global_position
				escape_dir = (global_position - surface_center)
				escape_dir.y = 0  # Flatten to XZ plane for floor movement
				escape_dir = escape_dir.normalized()
	
	# If escape direction is zero, pick random direction
	if escape_dir.length_squared() < 0.01:
		escape_dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	
	return escape_dir

## Handle physics for being inside a RoomSphere4D (hollow sphere)
## Returns true if enemy is inside a room sphere and physics were applied
func _handle_room_sphere_interior(delta: float) -> bool:
	# Find any room sphere we're inside of
	for room in get_tree().get_nodes_in_group("room_spheres_4d"):
		if not room or not is_instance_valid(room):
			continue
		
		var room_center: Vector3 = room.global_position
		var room_radius: float = room.radius if room.get("radius") else 20.0
		var dist_to_center: float = global_position.distance_to(room_center)
		
		# Check if we're inside this sphere (with small margin)
		if dist_to_center < room_radius + 2.0:
			# We're inside a room sphere - apply interior physics
			var dir_from_center: Vector3 = (global_position - room_center)
			if dir_from_center.length_squared() < 0.01:
				dir_from_center = Vector3.DOWN  # Fallback if at exact center
			dir_from_center = dir_from_center.normalized()
			
			# Gravity pulls toward the wall (outward from center)
			var grav_dir: Vector3 = dir_from_center
			
			# "Up" for the enemy is toward center (opposite of gravity)
			var surface_up: Vector3 = -dir_from_center
			up_direction = surface_up
			
			# Check if grounded (close to wall) - tighter threshold
			var dist_to_wall: float = room_radius - dist_to_center
			var grounded_threshold: float = 1.5  # Reduced from 3.0
			var is_grounded: bool = dist_to_wall < grounded_threshold
			
			# Apply gravity toward wall when not grounded
			if not is_grounded:
				velocity += grav_dir * gravity * delta
			else:
				# On the wall - cancel velocity toward wall
				var vel_toward_wall: float = velocity.dot(grav_dir)
				if vel_toward_wall > 0:
					velocity -= grav_dir * vel_toward_wall
			
			# Clamp enemy to stay inside sphere (tight buffer matching enemy size)
			var max_dist: float = room_radius - 0.8  # Enemy capsule radius ~0.4, plus small gap
			if dist_to_center > max_dist:
				global_position = room_center + dir_from_center * max_dist
				# Also zero out velocity toward wall when clamped
				var vel_toward: float = velocity.dot(grav_dir)
				if vel_toward > 0:
					velocity -= grav_dir * vel_toward
			
			# Use move_and_slide for any other collisions
			floor_snap_length = 0.0
			floor_stop_on_slope = false
			move_and_slide()
			
			# Update 4D position
			position_4d = Vector4D.from_vector3(global_position, position_4d.w)
			if surface_walker:
				surface_walker.set_position(position_4d)
			
			# Orient to match surface using Basis - feet toward wall, face forward
			# Get current forward direction (where enemy is looking)
			var current_forward: Vector3 = -global_transform.basis.z
			# Project forward onto tangent plane of sphere
			var tangent_forward: Vector3 = current_forward - surface_up * current_forward.dot(surface_up)
			if tangent_forward.length_squared() < 0.01:
				# Forward is parallel to up, pick arbitrary tangent
				tangent_forward = surface_up.cross(Vector3.RIGHT)
				if tangent_forward.length_squared() < 0.01:
					tangent_forward = surface_up.cross(Vector3.FORWARD)
			tangent_forward = tangent_forward.normalized()
			
			# Build orthonormal basis: up = toward center, forward = tangent, right = cross
			var right: Vector3 = tangent_forward.cross(surface_up).normalized()
			tangent_forward = surface_up.cross(right).normalized()
			
			# Smoothly interpolate toward target orientation
			var target_basis: Basis = Basis(right, surface_up, -tangent_forward)
			global_transform.basis = global_transform.basis.slerp(target_basis, delta * 8.0)
			
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
	
	# Check if we can see player (only if aggro enabled)
	if aggro_enabled and target and _can_see_target():
		current_state = State.CHASING
		print("[Enemy4D] Spotted player!")

# Set aggro enabled/disabled (called by debug console)
func set_aggro_enabled(enabled: bool) -> void:
	aggro_enabled = enabled
	if not enabled:
		current_state = State.SEARCHING  # Reset to searching when aggro disabled
		print("[Enemy4D] Aggro disabled - returning to patrol")

func _state_chasing_3d(delta: float) -> void:
	if not target:
		current_state = State.SEARCHING
		return
	
	# Stop chasing if aggro disabled
	if not aggro_enabled:
		current_state = State.SEARCHING
		velocity.x = 0
		velocity.z = 0
		return
	
	var distance: float = global_position.distance_to(target.global_position)
	var direction: Vector3 = (target.global_position - global_position).normalized()
	direction.y = 0
	
	if direction.length() > 0.1:
		look_at(global_position + direction)
	
	# Shoot while chasing (no range limit)
	if fire_cooldown <= 0 and _can_attack_target():
		_fire_at_target()
		fire_cooldown = fire_rate
	
	# Always keep moving toward player - never stop
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed

func _state_chasing_4d(delta: float) -> void:
	if not target:
		current_state = State.SEARCHING
		return
	
	# Stop chasing if aggro disabled
	if not aggro_enabled:
		current_state = State.SEARCHING
		if surface_walker:
			surface_walker.set_input(Vector3.ZERO)
		return
	
	var distance: float = global_position.distance_to(target.global_position)
	var direction: Vector3 = (target.global_position - global_position).normalized()
	
	# Project direction onto surface tangent plane for 4D surface movement
	if surface_walker:
		var grav_dir: Vector4D = surface_walker.get_gravity_direction()
		var up_dir: Vector3 = grav_dir.negate().to_vector3().normalized()
		if up_dir.length_squared() > 0.01:
			# Remove the up component from direction to get surface-parallel movement
			var up_component: float = direction.dot(up_dir)
			direction = (direction - up_dir * up_component).normalized()
	
	# Face target (projected onto surface)
	if direction.length() > 0.1:
		var look_pos: Vector3 = global_position + direction
		look_at(look_pos)
		# Correct pitch to stay aligned with surface
		rotation.x = 0
	
	# Shoot while chasing (no range limit - shoot immediately when spotted)
	if fire_cooldown <= 0 and _can_attack_target():
		_fire_at_target()
		fire_cooldown = fire_rate
	
	# Always keep moving toward target using surface walker
	if surface_walker:
		surface_walker.set_input(Vector3(0, 0, -1))  # Always move forward (we're facing target)

func _state_attacking(delta: float) -> void:
	# Redirect to chasing - enemies now chase and shoot at the same time
	_state_chasing_4d(delta)

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
	_update_health_bar()  # Update visual health bar
	
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

## Freeze the enemy for the given duration (status effect)
func freeze(duration: float) -> void:
	frozen_timer = max(frozen_timer, duration)  # Don't reduce existing freeze
	print("[Enemy4D] FROZEN for %.1f seconds!" % duration)

## Apply an external force (implosion/knockback)
func apply_external_force(force: Vector3) -> void:
	external_velocity += force
	print("[Enemy4D] External force applied: %s" % str(force))

# Get 4D position for visibility checks
func get_position_4d() -> Vector4D:
	return position_4d

# Set 4D position
func set_position_4d(pos: Vector4D) -> void:
	position_4d = pos
	if surface_walker:
		surface_walker.set_position(pos)
	global_position = pos.to_vector3()
