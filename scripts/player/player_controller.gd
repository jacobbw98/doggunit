# FPS Player Controller with 4D Support
# Can operate in standard 3D mode or 4D mode (walking on hyperspheres, etc.)
extends CharacterBody3D

signal health_changed(current: int, max_health: int)
signal player_died()
signal position_4d_changed(pos: Vector4D)

@export_group("Movement")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var jump_velocity: float = 9.0
@export var mouse_sensitivity: float = 0.003
@export var slide_speed: float = 12.0
@export var slide_friction: float = 0.98
@export var bhop_speed_bonus: float = 1.1  # 10% speed boost on successful bhop

@export_group("Movement Feel")
## Ground acceleration rate (units/sec²) - higher = snappier
@export var acceleration: float = 50.0
## Ground deceleration rate (units/sec²) - higher = faster stops
@export var deceleration: float = 60.0
## Air acceleration - lower than ground for less floaty air control
@export var air_acceleration: float = 10.0
## Air deceleration - lower for momentum preservation in air
@export var air_deceleration: float = 5.0
## Gravity multiplier - higher = faster falls, snappier jumps
@export var gravity_multiplier: float = 2.0
## Fall gravity extra multiplier - makes apex feel snappier
@export var fall_gravity_multiplier: float = 1.5
## Velocity below this snaps to zero for crisp stops
@export var stop_threshold: float = 0.5

@export_group("Stats")
@export var max_health: int = 100

@export_group("4D Settings")
## Enable 4D physics mode (walking on hyperspheres, etc.)
@export var enable_4d_mode: bool = false
## Initial W coordinate
@export var initial_w: float = 0.0

# Node references
@onready var camera: Camera3D = $Camera3D
@onready var weapon_manager: WeaponManager = $Camera3D/WeaponManager

# State
var current_health: int
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# 4D State
var position_4d: Vector4D = Vector4D.zero()
var surface_walker: SurfaceWalker4D = null
var scroll_4d_enabled: bool = false  # Controlled by debug console "4d" command
var fly_mode: bool = false  # Controlled by debug console "noclip" command

# Sphere walking state
var sphere_facing: Vector3 = Vector3.FORWARD  # Facing direction on surface (tangent to surface)
var current_gravity_up: Vector3 = Vector3.UP  # Current surface up direction

# Slide and bhop state
var is_sliding: bool = false
var slide_direction: Vector3 = Vector3.ZERO
var current_momentum: float = 0.0  # Accumulated bhop momentum
var was_grounded_last_frame: bool = false
var bhop_window_timer: float = 0.0  # Time since landing for bhop window
const BHOP_WINDOW: float = 0.15  # 150ms window for bhop

# Status effects (from explosions, freezing, implosion pulls)
var frozen_timer: float = 0.0
var external_velocity: Vector3 = Vector3.ZERO
const EXTERNAL_VELOCITY_DECAY: float = 5.0

func _ready() -> void:
	current_health = max_health
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	add_to_group("player")
	
	# Initialize 4D mode if enabled
	if enable_4d_mode:
		_init_4d_mode()

func _init_4d_mode() -> void:
	# Create surface walker for 4D physics
	surface_walker = SurfaceWalker4D.new()
	surface_walker.move_speed = walk_speed
	surface_walker.jump_velocity = jump_velocity
	add_child(surface_walker)
	
	# Set initial 4D position (XYZ from 3D position, W from setting)
	position_4d = Vector4D.from_vector3(global_position, initial_w)
	surface_walker.set_position(position_4d)
	
	# Connect signals
	surface_walker.position_changed.connect(_on_4d_position_changed)
	surface_walker.grounded_changed.connect(_on_4d_grounded_changed)
	
	print("[Player] 4D mode enabled at W=%.2f" % initial_w)

func _unhandled_input(event: InputEvent) -> void:
	# Mouse look
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if fly_mode:
			# In fly mode: use direct rotation around world Y axis
			rotate_y(-event.relative.x * mouse_sensitivity)
		else:
			# Normal mode: rotate facing vector around current gravity up axis
			var yaw_amount: float = -event.relative.x * mouse_sensitivity
			sphere_facing = sphere_facing.rotated(current_gravity_up, yaw_amount)
		
		# Vertical look: rotate camera locally (works in both modes)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, -PI/2, PI/2)
	
	# Toggle mouse capture
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Reload (still event-based)
	if event.is_action_pressed("reload"):
		weapon_manager.reload()
	
	# 4D scroll wheel movement (when enabled by debug console)
	if scroll_4d_enabled and enable_4d_mode and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			position_4d.w += 0.2
			_sync_4d_position()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			position_4d.w -= 0.2
			_sync_4d_position()

func _physics_process(delta: float) -> void:
	# DEBUG - print once per second to confirm this is running
	if Engine.get_frames_drawn() % 60 == 0:
		print("[Player] _physics_process running, fly_mode=%s" % fly_mode)
	
	# Handle frozen state - skip movement controls but still apply physics
	if frozen_timer > 0:
		frozen_timer -= delta
		# Still apply external velocity while frozen
		if external_velocity.length_squared() > 0.01:
			velocity = external_velocity
			external_velocity = external_velocity.lerp(Vector3.ZERO, EXTERNAL_VELOCITY_DECAY * delta)
			move_and_slide()
		return
	
	# Decay and apply external velocity (knockback, implosion pull)
	if external_velocity.length_squared() > 0.01:
		velocity += external_velocity
		external_velocity = external_velocity.lerp(Vector3.ZERO, EXTERNAL_VELOCITY_DECAY * delta)
	
	# Continuous fire while holding shoot button
	if Input.is_action_pressed("shoot"):
		_fire_weapon()
	
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var speed = sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	
	# Pass both world direction AND raw input for sphere walking
	_physics_process_3d(delta, direction, speed, Vector3(input_dir.x, 0, input_dir.y))

func _physics_process_3d(delta: float, direction: Vector3, speed: float, raw_input: Vector3 = Vector3.ZERO) -> void:
	if fly_mode:
		# Fly mode - simple free movement with standard Y-up orientation
		# Gradually lerp orientation to world up (prevents jarring snap)
		var current_up := global_transform.basis.y
		if current_up.dot(Vector3.UP) < 0.99:
			# Smoothly rotate toward world up
			var target_basis := Basis()
			target_basis.y = Vector3.UP
			target_basis.z = -global_transform.basis.z
			target_basis.z.y = 0
			if target_basis.z.length_squared() < 0.01:
				target_basis.z = Vector3.BACK
			target_basis.z = target_basis.z.normalized()
			target_basis.x = target_basis.y.cross(target_basis.z).normalized()
			target_basis.z = target_basis.x.cross(target_basis.y).normalized()
			global_transform.basis = global_transform.basis.slerp(target_basis, delta * 5.0)
		
		# Set up CharacterBody3D for standard movement
		up_direction = Vector3.UP
		
		# Movement relative to player facing
		var fly_velocity := Vector3.ZERO
		fly_velocity.x = direction.x * speed
		fly_velocity.z = direction.z * speed
		if Input.is_action_pressed("jump"):
			fly_velocity.y = speed
		elif Input.is_action_pressed("crouch") or Input.is_key_pressed(KEY_CTRL):
			fly_velocity.y = -speed
		velocity = fly_velocity
		move_and_slide()
		
		# Reset gravity up for when we exit fly mode
		current_gravity_up = Vector3.UP
		sphere_facing = -global_transform.basis.z
		return
	
	# Find which room sphere we're in (if any)
	# Use generous detection to include portal transition zones
	var current_room: Node = null
	var room_center := Vector3.ZERO
	var room_radius := 20.0
	var best_inside_dist: float = -INF  # Most inside = highest value
	
	# DEBUG: Count rooms in group
	var rooms_in_group: Array = get_tree().get_nodes_in_group("room_spheres_4d")
	if Engine.get_frames_drawn() % 120 == 0:
		print("[Player] Checking %d rooms in 'room_spheres_4d' group, player pos=%s" % [rooms_in_group.size(), global_position])
	
	# Find the room we're MOST INSIDE of (highest score = best match)
	# IMPORTANT: Only consider rooms at matching W coordinate to prevent
	# interaction with overlapping rooms at different W slices
	for room in rooms_in_group:
		if room.has_method("get_spawn_position"):
			var r_center: Vector3 = room.global_position
			var r_radius: float = room.radius if room.get("radius") else 20.0
			var dist_to_center := global_position.distance_to(r_center)
			
			# FIRST: Check W-coordinate match - SKIP rooms with mismatched W
			if room.get("_position_4d") != null and position_4d != null:
				var room_w: float = room._position_4d.w
				var player_w: float = position_4d.w
				var w_dist: float = abs(room_w - player_w)
				# Only consider rooms within W-radius (visible to player)
				if w_dist > r_radius:
					continue  # Skip this room entirely - wrong W slice
			
			# Check if inside this room OR very close to its surface (for transitions)
			if dist_to_center < r_radius + 5.0:
				# inside_dist: positive = inside, higher = deeper inside
				var inside_dist := r_radius - dist_to_center
				# Prefer the room we're MOST INSIDE of
				if inside_dist > best_inside_dist:
					best_inside_dist = inside_dist
					current_room = room
					room_center = r_center
					room_radius = r_radius
	
	# DEBUG: Show result of room search
	if Engine.get_frames_drawn() % 120 == 0:
		if current_room:
			print("[Player] Found room: %s (inside_dist=%.1f)" % [current_room.name, best_inside_dist])
		else:
			print("[Player] NO ROOM FOUND! Falling into space...")
	
	if current_room:
		# DYNAMIC GRAVITY: Pull player toward the sphere wall (outward from center)
		var dir_from_center := (global_position - room_center)
		if dir_from_center.length_squared() < 0.01:
			dir_from_center = Vector3.DOWN  # Fallback if at exact center
		dir_from_center = dir_from_center.normalized()
		
		# The "up" direction for the player is TOWARD the center (opposite of gravity)
		var surface_up := -dir_from_center  # Points toward center
		var grav_dir := dir_from_center  # Gravity pulls toward wall
		
		# Set CharacterBody3D up direction for move_and_slide
		up_direction = surface_up
		
		# Distance from sphere surface (player is INSIDE, so this is positive when inside)
		var dist_to_wall := room_radius - global_position.distance_to(room_center)
		
		# Use a grounded threshold that works with our clamp buffer
		var grounded_threshold := 3.0  # Matches clamp buffer + some margin
		var is_grounded := dist_to_wall < grounded_threshold
		
		# Check if player is in a portal hole (for physics exemptions)
		var in_portal := _is_in_portal_hole(global_position, current_room)
		
		# Apply gravity toward the wall (with multiplier for snappy feel)
		if not is_grounded:
			# Use higher gravity when falling (velocity toward wall = falling)
			var grav_mult := gravity_multiplier
			if velocity.dot(grav_dir) > 0:  # Moving toward wall = falling
				grav_mult *= fall_gravity_multiplier
			velocity += grav_dir * gravity * grav_mult * delta
		else:
			# On the wall - reduce velocity toward wall UNLESS in portal hole
			# Portal holes need to allow outward velocity to pass through
			if not in_portal:
				var vel_toward_wall := velocity.dot(grav_dir)
				if vel_toward_wall > 0:
					velocity -= grav_dir * vel_toward_wall * 0.9
		
		# Clamp player to stay inside sphere (portal holes in mesh will allow traversal)
		# Skip clamping if aligned with a portal hole (allows natural walk-through)
		var max_dist := room_radius - 2.0
		var current_dist := global_position.distance_to(room_center)
		
		if current_dist > max_dist:
			# Only clamp if NOT in a portal hole
			if not in_portal:
				global_position = room_center + dir_from_center * max_dist
		
		# CONSTRUCT PLAYER ORIENTATION from facing vector + gravity up
		
		# Smoothly interpolate the gravity up direction
		var old_up := current_gravity_up
		current_gravity_up = current_gravity_up.lerp(surface_up, 8.0 * delta).normalized()
		
		# When gravity up changes, re-project facing onto new tangent plane
		sphere_facing = sphere_facing - current_gravity_up * sphere_facing.dot(current_gravity_up)
		if sphere_facing.length_squared() < 0.001:
			sphere_facing = Vector3.FORWARD - current_gravity_up * Vector3.FORWARD.dot(current_gravity_up)
		sphere_facing = sphere_facing.normalized()
		
		# Construct orthonormal basis from facing + up
		# In Godot: -Z is forward, Y is up, X is right
		var forward := sphere_facing
		var up := current_gravity_up
		var right := forward.cross(up).normalized()
		forward = up.cross(right).normalized()  # Re-orthogonalize
		
		global_transform.basis = Basis(right, up, -forward)
		
		# Separate velocity into surface-tangent (horizontal) and surface-normal (vertical)
		var vertical_vel := current_gravity_up * velocity.dot(current_gravity_up)
		var horizontal_vel := velocity - vertical_vel
		
		# Detect landing for bhop
		if is_grounded and not was_grounded_last_frame:
			# Just landed! Check for bhop timing
			bhop_window_timer = BHOP_WINDOW
		was_grounded_last_frame = is_grounded
		
		# Update bhop window timer
		if bhop_window_timer > 0:
			bhop_window_timer -= delta
		
		# Check for slide input (crouch while moving)
		var crouch_pressed := Input.is_action_pressed("crouch") or Input.is_key_pressed(KEY_CTRL)
		var has_movement := raw_input.length_squared() > 0.01
		var horizontal_speed := horizontal_vel.length()
		
		# Start sliding
		if crouch_pressed and has_movement and is_grounded and horizontal_speed > 2.0 and not is_sliding:
			is_sliding = true
			slide_direction = horizontal_vel.normalized()
			# Boost speed when entering slide
			current_momentum = maxf(horizontal_speed, slide_speed)
		
		# Stop sliding
		if is_sliding and (not crouch_pressed or horizontal_speed < 1.0):
			is_sliding = false
		
		# Movement logic
		if is_sliding:
			# Sliding: maintain direction with friction
			current_momentum *= slide_friction
			horizontal_vel = slide_direction * current_momentum
		elif raw_input.length_squared() > 0.01:
			# Normal movement with acceleration (snappy feel)
			var move_speed := speed + current_momentum * 0.5  # Momentum adds to speed
			var local_move := Vector3(raw_input.x * move_speed, 0, raw_input.z * move_speed)
			var target_vel := global_transform.basis * local_move
			
			# Use acceleration rate (different for ground vs air)
			var accel := acceleration if is_grounded else air_acceleration
			horizontal_vel = horizontal_vel.move_toward(target_vel, accel * delta)
			
			# Slowly decay momentum when walking
			current_momentum = lerpf(current_momentum, 0.0, 2.0 * delta)
		else:
			# Deceleration: 60 when standing, 0 when crouching (infinite bhop speed!)
			# crouch_pressed already declared above in slide logic
			if crouch_pressed:
				# No deceleration while crouching - preserve all momentum for bhops
				pass
			else:
				# Snappy deceleration when standing
				horizontal_vel = horizontal_vel.move_toward(Vector3.ZERO, deceleration * delta)
				
				# Snap to zero below threshold for crisp stops
				if horizontal_vel.length() < stop_threshold:
					horizontal_vel = Vector3.ZERO
			
			current_momentum = lerpf(current_momentum, 0.0, 3.0 * delta)
		
		# Recombine: gravity/jump stays, movement is applied horizontally
		velocity = horizontal_vel + vertical_vel
		
		# Jump toward center (away from wall) - only when grounded
		if Input.is_action_just_pressed("jump") and is_grounded:
			velocity += surface_up * jump_velocity
			
			# Bunny hop bonus: if jumping within bhop window, boost momentum (UNCAPPED!)
			if bhop_window_timer > 0:
				current_momentum = current_momentum * bhop_speed_bonus + 1.0
				bhop_window_timer = 0.0
	else:
		# NOT IN ANY ROOM - find nearest room and clamp to it (recovery mode)
		var nearest_room: Node = null
		var nearest_dist: float = INF
		var nearest_center: Vector3 = Vector3.ZERO
		var nearest_radius: float = 20.0
		
		for room in get_tree().get_nodes_in_group("room_spheres_4d"):
			if room.has_method("get_spawn_position"):
				var r_center: Vector3 = room.global_position
				var r_radius: float = room.radius if room.get("radius") else 20.0
				var dist: float = global_position.distance_to(r_center)
				if dist < nearest_dist:
					nearest_dist = dist
					nearest_room = room
					nearest_center = r_center
					nearest_radius = r_radius
		
		if nearest_room:
			# CLAMP to the nearest room's interior surface
			var dir_from_center := (global_position - nearest_center)
			if dir_from_center.length_squared() < 0.01:
				dir_from_center = Vector3.DOWN
			dir_from_center = dir_from_center.normalized()
			
			# Clamp to inside the sphere with buffer
			var max_dist := nearest_radius - 2.0
			if nearest_dist > max_dist or nearest_dist < 1.0:
				# Teleport to safe position inside the room
				global_position = nearest_center + dir_from_center * max_dist
				velocity = Vector3.ZERO
				print("[Player] RECOVERY: Clamped to room at %s" % nearest_center)
			
			# Apply gravity toward that sphere (with multiplier for snappy feel)
			var grav_dir := dir_from_center
			velocity += grav_dir * gravity * gravity_multiplier * delta
			
			# Update orientation
			current_gravity_up = current_gravity_up.lerp(-dir_from_center, 8.0 * delta).normalized()
		else:
			# No rooms at all - standard Y-down gravity
			if not is_on_floor():
				velocity.y -= gravity * delta
			
			if Input.is_action_just_pressed("jump") and is_on_floor():
				velocity.y = jump_velocity
			
			if direction.length_squared() > 0.01:
				velocity.x = direction.x * speed
				velocity.z = direction.z * speed
			else:
				velocity.x = move_toward(velocity.x, 0, speed)
				velocity.z = move_toward(velocity.z, 0, speed)
	
	move_and_slide()

func _physics_process_4d(delta: float, direction: Vector3, speed: float) -> void:
	# Handle FLY MODE (noclip) - same as 3D mode
	if fly_mode:
		var fly_velocity := Vector3.ZERO
		fly_velocity.x = direction.x * speed
		fly_velocity.z = direction.z * speed
		if Input.is_action_pressed("jump"):
			fly_velocity.y = speed
		elif Input.is_action_pressed("crouch") or Input.is_key_pressed(KEY_CTRL):
			fly_velocity.y = -speed
		velocity = fly_velocity
		move_and_slide()
		
		# Sync 4D position
		position_4d = Vector4D.from_vector3(global_position, position_4d.w)
		return
	
	# NORMAL 4D MODE: Use 4D physics for gravity, 3D for collision
	
	# Update surface walker (for tracking nearest surface)
	if surface_walker:
		surface_walker.move_speed = speed
		surface_walker.set_input(direction)
		# Update gravity based on nearest surface
		surface_walker.physics.update_sticky_gravity(position_4d)
	
	# Get gravity direction from 4D physics (points toward nearest surface)
	var grav_dir_3d := Vector3.DOWN  # Default
	if surface_walker and surface_walker.physics:
		var grav_dir_4d = surface_walker.physics.gravity_direction
		if grav_dir_4d:
			grav_dir_3d = grav_dir_4d.to_vector3()
			if grav_dir_3d.length_squared() < 0.01:
				grav_dir_3d = Vector3.DOWN
	
	# Apply gravity
	if not is_on_floor():
		velocity += grav_dir_3d * gravity * delta
	
	# Apply horizontal movement
	if direction.length_squared() > 0.01:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
	
	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity  # Just use Y for simplicity
	
	# Move with 3D collision
	move_and_slide()
	
	# Sync 4D position from 3D
	position_4d = Vector4D.from_vector3(global_position, position_4d.w)
	if surface_walker:
		surface_walker.set_position(position_4d)

func _on_4d_position_changed(new_pos: Vector4D) -> void:
	position_4d = new_pos
	global_position = new_pos.to_vector3()
	position_4d_changed.emit(new_pos)

func _on_4d_grounded_changed(grounded: bool) -> void:
	if grounded:
		print("[Player] Grounded on 4D surface")

func _sync_4d_position() -> void:
	if surface_walker:
		surface_walker.set_position(position_4d)
	position_4d_changed.emit(position_4d)

func _fire_weapon() -> void:
	if weapon_manager:
		var direction = -camera.global_transform.basis.z
		# Spawn bullets from the gun position (weapon manager), not camera
		var origin = weapon_manager.global_position + direction * 0.5  # Slightly in front of gun
		# Pass player's W-position for 4D-aware projectiles
		# Always use position_4d.w (updated by portal transitions regardless of enable_4d_mode)
		var w_pos: float = position_4d.w
		weapon_manager.fire(origin, direction, w_pos)

func take_damage(amount: int, damage_type: GunTypes.Type = GunTypes.Type.EXPLOSIVE) -> void:
	current_health -= amount
	current_health = max(current_health, 0)
	
	health_changed.emit(current_health, max_health)
	
	if current_health <= 0:
		_die()

func heal(amount: int) -> void:
	current_health += amount
	current_health = min(current_health, max_health)
	health_changed.emit(current_health, max_health)

func _die() -> void:
	player_died.emit()
	print("Player died!")

func get_camera_direction() -> Vector3:
	return -camera.global_transform.basis.z

# Called by debug console to toggle 4D scroll mode
func set_4d_scroll_mode(enabled: bool) -> void:
	scroll_4d_enabled = enabled
	# Also enable 4D mode when scroll is enabled so W-position is tracked
	if enabled:
		enable_4d_mode = true
	print("[Player] 4D scroll mode: %s (4D mode: %s)" % [("ON" if enabled else "OFF"), ("ON" if enable_4d_mode else "OFF")])

# Get current 4D position
func get_position_4d() -> Vector4D:
	return position_4d

# Set current 4D position (also syncs surface walker and 3D position)
func set_position_4d(pos: Vector4D) -> void:
	position_4d = pos
	global_position = pos.to_vector3()
	if surface_walker:
		surface_walker.set_position(pos)
	position_4d_changed.emit(pos)

# Set 4D mode at runtime
func set_4d_mode(enabled: bool) -> void:
	if enabled and not enable_4d_mode:
		enable_4d_mode = true
		_init_4d_mode()
	elif not enabled and enable_4d_mode:
		enable_4d_mode = false
		if surface_walker:
			surface_walker.queue_free()
			surface_walker = null

# Called by debug console to toggle fly mode (noclip)
func set_fly_mode(enabled: bool) -> void:
	fly_mode = enabled
	print("[Player] Fly mode: %s" % ("ON" if enabled else "OFF"))

## Check if player is near a portal in the given room (allows passage through sphere boundary)
func _is_near_portal(room: Node) -> bool:
	if not room or not room.has_method("get_portals"):
		# Try to find portals as children
		for child in room.get_children():
			if child.is_in_group("portal_doors"):
				var portal_pos: Vector3 = child.global_position
				var portal_radius: float = child.get("portal_radius") if child.get("portal_radius") else 2.0
				# Check distance - allow passage if within 1.5x portal radius
				if global_position.distance_to(portal_pos) < portal_radius * 3.0:
					return true
		return false
	
	# Room has get_portals method
	var portals: Array = room.get_portals()
	for portal in portals:
		if not is_instance_valid(portal):
			continue
		var portal_pos: Vector3 = portal.global_position
		var portal_radius: float = portal.get("portal_radius") if portal.get("portal_radius") else 2.0
		if global_position.distance_to(portal_pos) < portal_radius * 3.0:
			return true
	return false

## Freeze the player for the given duration (status effect from enemy projectiles)
func freeze(duration: float) -> void:
	frozen_timer = max(frozen_timer, duration)
	print("[Player] FROZEN for %.1f seconds!" % duration)

## Apply an external force to the player (explosion knockback, implosion pull)
func apply_external_force(force: Vector3) -> void:
	external_velocity += force
	print("[Player] External force applied: %s" % str(force))

## Check if player is in any portal's hole (either in transition zone OR standing on portal)
## This makes portals act like holes you fall through, not surfaces you stand on
func _is_in_portal_hole(pos: Vector3, room: Node) -> bool:
	# Check all portal doors
	var all_portals = get_tree().get_nodes_in_group("portal_doors")
	for portal in all_portals:
		if not is_instance_valid(portal):
			continue
		
		# Method 1: Check if player is in the transition zone (Area3D detection)
		# This is the most reliable - if Area3D says we're in, we're in
		if portal.get("_players_in_zone") != null:
			var players_in_zone: Array = portal._players_in_zone
			if self in players_in_zone:
				return true
		
		# Method 2: Check if player is NEAR the portal's position (within hole radius)
		# This catches cases where player is standing ON the portal before entering the box
		# Use a tighter radius (2.0x) to prevent premature floor clipping
		# The transition Area3D is portal_radius * 2.5 wide, so 2.0x is safe
		var portal_radius = portal.get("portal_radius")
		if portal_radius == null:
			portal_radius = 2.0  # Default portal radius
		
		var dist_to_portal: float = pos.distance_to(portal.global_position)
		# Use 2.0x portal radius - tight enough to prevent floor clipping,
		# but large enough to allow walking into the hole
		if dist_to_portal < portal_radius * 2.0:
			return true
			
	return false
