# Base Gun Class - Dogs that shoot from their mouths
class_name Gun
extends Node3D

signal ammo_changed(current: int, max_ammo: int)
signal gun_fired()
signal gun_reloaded()

@export var stats: GunStats

# Current ammo state
var current_ammo: int = 0
var can_fire: bool = true
var fire_timer: float = 0.0

# Visual components
var mesh_instance: MeshInstance3D

func _ready() -> void:
	if stats:
		current_ammo = stats.max_ammo
		ammo_changed.emit(current_ammo, stats.max_ammo)
	
	# Create visual mesh if not present
	if get_node_or_null("MeshInstance3D") == null:
		_create_visual()

func _create_visual() -> void:
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "MeshInstance3D"
	
	# Create a simple box to represent the gun
	var box := BoxMesh.new()
	box.size = Vector3(0.1, 0.15, 0.4)  # Small rectangle
	mesh_instance.mesh = box
	
	# Color based on gun type
	var mat := StandardMaterial3D.new()
	if stats:
		match stats.gun_type:
			GunTypes.Type.EXPLOSIVE:
				mat.albedo_color = Color(0.9, 0.4, 0.2)  # Orange
			GunTypes.Type.IMPLOSIVE:
				mat.albedo_color = Color(0.6, 0.3, 0.9)  # Purple
			GunTypes.Type.FREEZING:
				mat.albedo_color = Color(0.3, 0.7, 0.9)  # Cyan
			GunTypes.Type.ACCELERATING:
				mat.albedo_color = Color(0.3, 0.9, 0.5)  # Green
		mat.emission_enabled = true
		mat.emission = mat.albedo_color
		mat.emission_energy_multiplier = 0.2
	else:
		mat.albedo_color = Color(0.5, 0.5, 0.5)
	
	mesh_instance.material_override = mat
	add_child(mesh_instance)
	
	# Add barrel (cylinder pointing forward)
	var barrel := MeshInstance3D.new()
	barrel.name = "Barrel"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.04
	cyl.height = 0.25
	barrel.mesh = cyl
	barrel.rotation_degrees.x = 90  # Point forward
	barrel.position = Vector3(0, 0, -0.3)
	barrel.material_override = mat.duplicate()
	add_child(barrel)

func _process(delta: float) -> void:
	if not can_fire:
		fire_timer -= delta
		if fire_timer <= 0:
			can_fire = true

func fire(origin: Vector3, direction: Vector3, w_position: float = 0.0) -> void:
	if not stats:
		print("[Gun] No stats - cannot fire")
		return
	
	if not can_fire:
		return
	
	if current_ammo <= 0:
		print("[Gun] Out of ammo!")
		return
	
	# Consume ammo
	current_ammo -= 1
	ammo_changed.emit(current_ammo, stats.max_ammo)
	
	# Fire rate cooldown
	can_fire = false
	fire_timer = stats.fire_rate
	
	# Check for crit
	var is_crit = stats.roll_crit()
	
	# Calculate how many projectiles to spawn
	var projectile_count = stats.get_projectile_count()
	
	for i in range(projectile_count):
		var spread_direction = _apply_accuracy_spread(direction)
		_spawn_projectile(origin, spread_direction, is_crit, w_position)
	
	gun_fired.emit()
	print("[Gun] Fired %d projectile(s) at W=%.2f!" % [projectile_count, w_position])

func _apply_accuracy_spread(direction: Vector3) -> Vector3:
	if not stats:
		return direction
	
	# Higher accuracy = less spread
	var spread_amount = (1.0 - stats.accuracy) * 0.15
	
	# Random spread within cone
	var spread_x = randf_range(-spread_amount, spread_amount)
	var spread_y = randf_range(-spread_amount, spread_amount)
	
	var spread_dir = direction + Vector3(spread_x, spread_y, 0)
	return spread_dir.normalized()

func _spawn_projectile(origin: Vector3, direction: Vector3, is_crit: bool, w_position: float = 0.0) -> void:
	# Create actual projectile with 4D position
	var projectile: Projectile = Projectile.create_from_stats(stats, origin, direction, get_parent(), w_position)
	
	# Apply crit damage
	if is_crit:
		projectile.damage *= stats.get_scaled_crit_damage()
		print("[Gun] CRITICAL HIT!")
	
	# Add to scene safely
	var tree = get_tree()
	if tree and tree.current_scene:
		tree.current_scene.add_child(projectile)
	elif get_parent():
		get_parent().add_child(projectile)
	else:
		projectile.queue_free()
		print("[Gun] Error: Could not add projectile to scene")

func reload() -> void:
	if not stats:
		return
	
	current_ammo = stats.max_ammo
	ammo_changed.emit(current_ammo, stats.max_ammo)
	gun_reloaded.emit()
	print("[Gun] Reloaded! Ammo: %d" % current_ammo)

func get_display_info() -> Dictionary:
	if not stats:
		return {}
	
	return {
		"name": stats.get_display_name(),
		"ammo": "%d / %d" % [current_ammo, stats.max_ammo],
		"type": GunTypes.get_type_name(stats.gun_type),
		"rarity": GunTypes.get_rarity_name(stats.rarity),
		"rarity_color": GunTypes.RARITY_COLORS[stats.rarity]
	}
