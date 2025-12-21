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
	global_position += direction * speed * delta
	
	# Update 4D position (W stays same unless velocity_w is set)
	position_4d = Vector4D.from_vector3(global_position, position_4d.w + velocity_w * delta)
	
	# Track lifetime
	_time_alive += delta
	if _time_alive >= lifetime:
		queue_free()

func _on_body_entered(body: Node3D) -> void:
	# Don't hit shooter
	if body == shooter:
		return
	
	# 4D hit check - verify W-distance
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
	
	# Apply damage
	if body.has_method("take_damage"):
		body.take_damage(int(damage), damage_type)
		print("[Projectile] Hit %s for %d damage!" % [body.name, int(damage)])
	
	# Destroy on hit
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

