# Test Enemy - Spins looking for player, then chases and shoots
extends CharacterBody3D

signal died(enemy: Node3D)

@export var max_health: int = 50
@export var move_speed: float = 3.0
@export var spin_speed: float = 2.0
@export var view_range: float = 15.0
@export var view_angle: float = 60.0  # Degrees
@export var attack_range: float = 12.0
@export var fire_rate: float = 1.0

enum State { SEARCHING, CHASING, ATTACKING }

var current_state: State = State.SEARCHING
var current_health: int
var target: Node3D = null
var fire_cooldown: float = 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Gun stats for this enemy
var gun_stats: GunStats

func _ready() -> void:
	current_health = max_health
	add_to_group("enemies")
	
	# Create gun stats for drops
	gun_stats = GunStats.new()
	gun_stats.gun_name = "Enemy Pup"
	gun_stats.gun_type = GunTypes.Type.EXPLOSIVE
	gun_stats.rarity = GunTypes.Rarity.POOR
	
	# Find player
	await get_tree().process_frame
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		target = players[0]

func _physics_process(delta: float) -> void:
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	# Update fire cooldown
	if fire_cooldown > 0:
		fire_cooldown -= delta
	
	match current_state:
		State.SEARCHING:
			_state_searching(delta)
		State.CHASING:
			_state_chasing(delta)
		State.ATTACKING:
			_state_attacking(delta)
	
	move_and_slide()

func _state_searching(delta: float) -> void:
	# Spin around looking for player
	rotate_y(spin_speed * delta)
	velocity.x = 0
	velocity.z = 0
	
	# Check if we can see the player
	if target and _can_see_target():
		current_state = State.CHASING
		print("[Enemy] Spotted player!")

func _state_chasing(delta: float) -> void:
	if not target:
		current_state = State.SEARCHING
		return
	
	var distance = global_position.distance_to(target.global_position)
	
	# Check if we lost sight
	if not _can_see_target():
		current_state = State.SEARCHING
		print("[Enemy] Lost sight of player")
		return
	
	# Move towards player
	var direction = (target.global_position - global_position).normalized()
	direction.y = 0
	
	# Face target
	if direction.length() > 0.1:
		look_at(global_position + direction)
	
	# If close enough, attack
	if distance <= attack_range:
		current_state = State.ATTACKING
		velocity.x = 0
		velocity.z = 0
	else:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed

func _state_attacking(delta: float) -> void:
	if not target:
		current_state = State.SEARCHING
		return
	
	var distance = global_position.distance_to(target.global_position)
	
	# Face target
	var direction = (target.global_position - global_position).normalized()
	direction.y = 0
	if direction.length() > 0.1:
		look_at(global_position + direction)
	
	# If player moved out of range, chase again
	if distance > attack_range * 1.2:
		current_state = State.CHASING
		return
	
	# If lost sight, go back to searching
	if not _can_see_target():
		current_state = State.SEARCHING
		return
	
	# Shoot!
	if fire_cooldown <= 0:
		_fire_at_target()
		fire_cooldown = fire_rate
	
	velocity.x = 0
	velocity.z = 0

func _can_see_target() -> bool:
	if not target:
		return false
	
	var to_target = target.global_position - global_position
	var distance = to_target.length()
	
	# Check range
	if distance > view_range:
		return false
	
	# Check angle
	var forward = -global_transform.basis.z
	var angle = rad_to_deg(forward.angle_to(to_target.normalized()))
	if angle > view_angle:
		return false
	
	# Raycast to check for obstacles
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 1, 0),
		target.global_position + Vector3(0, 1, 0)
	)
	query.exclude = [self]
	
	var result = space_state.intersect_ray(query)
	if result and result.collider == target:
		return true
	
	# If no obstacle hit, we can see
	return result.is_empty()

func _fire_at_target() -> void:
	if not target:
		return
	
	var direction = (target.global_position - global_position).normalized()
	print("[Enemy] BANG! Firing at player")
	
	# TODO: Spawn actual projectile
	# For now, do direct damage with some inaccuracy
	var accuracy_roll = randf()
	if accuracy_roll > 0.4:  # 60% hit chance
		if target.has_method("take_damage"):
			var damage = gun_stats.get_scaled_damage()
			target.take_damage(int(damage), gun_stats.gun_type)
			print("[Enemy] Hit player for %d damage!" % int(damage))

func take_damage(amount: int, damage_type: GunTypes.Type) -> void:
	# Apply type effectiveness
	var my_type = gun_stats.gun_type if gun_stats else GunTypes.Type.EXPLOSIVE
	var effectiveness = GunTypes.get_effectiveness(damage_type, my_type)
	var final_damage = int(amount * effectiveness)
	
	current_health -= final_damage
	current_health = max(current_health, 0)
	
	# Wake up if hit while searching
	if current_state == State.SEARCHING and target:
		current_state = State.CHASING
	
	print("[Enemy] Took %d damage (%d%% effective), HP: %d/%d" % [
		final_damage, int(effectiveness * 100), current_health, max_health
	])
	
	if current_health <= 0:
		_die()

func _die() -> void:
	print("[Enemy] Died! Dropping: %s" % gun_stats.get_display_name())
	died.emit(self)
	GameManager.enemy_killed()
	queue_free()
