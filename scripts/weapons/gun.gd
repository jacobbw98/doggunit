# Base Gun Class - Dogs that shoot from their mouths
class_name Gun
extends Node3D

signal ammo_changed(current: int, max_ammo: int)
signal gun_fired()
signal gun_reloaded()
signal reload_started(duration: float)

@export var stats: GunStats

# Current ammo state
var current_ammo: int = 0
var can_fire: bool = true
var fire_timer: float = 0.0
var is_reloading: bool = false
var reload_remaining: float = 0.0
var reload_duration: float = 0.0
var _reload_delay: float = 0.0
var _reload_base_transform := Transform3D.IDENTITY
var _reload_treat: MeshInstance3D
var _reload_head: Node3D
var _reload_head_base_basis := Basis.IDENTITY
var _reload_barked: bool = false
var _reload_head_transform := Transform3D.IDENTITY
var _reload_head_attachments: Array[Dictionary] = []
const RELOAD_MOTION := preload("res://scripts/weapons/dog_reload_motion.gd")

# Visual components
var mesh_instance: MeshInstance3D
var mascot_model: Node3D
var breed_model: Node3D
var _mascot_recoil: Tween
var _breed_recoil: Tween
const BREED_HELD_POSITION := Vector3(-0.02, -0.29, -0.24)
const BREED_HELD_SCALE := 0.30
const MAPPO_SCENE := "res://scenes/mascot/mascot_dog.tscn"
const MAPPO_HELD_POSITION := Vector3(-0.02, -0.32, -0.30)
const MAPPO_HELD_SCALE := 0.32
const MAPPO_HELD_YAW := 0.0
const MAPPO_RENDER_LAYER := 1 << 19

func _ready() -> void:
	if stats:
		current_ammo = get_magazine_size()
		ammo_changed.emit(current_ammo, get_magazine_size())
	
	# Create visual mesh if not present
	if get_node_or_null("MeshInstance3D") == null:
		_create_visual()
	refresh_item_visuals()

func _create_visual() -> void:
	if stats and not stats.breed_id.is_empty() and _create_breed_visual():
		return
	if stats and stats.mascot_visual and _create_mascot_visual():
		return
	var fur := Color("d4a56b")
	if stats:
		match stats.gun_type:
			GunTypes.Type.IMPLOSIVE: fur = Color("a589cf")
			GunTypes.Type.FREEZING: fur = Color("a4dce6")
			GunTypes.Type.ACCELERATING: fur = Color("97ca92")
	# A small low-poly pup held beneath the crosshair, muzzle facing forward.
	mesh_instance = _dog_part("MeshInstance3D", Vector3(0.20, 0.24, 0.30), Vector3(0, 0.01, 0), fur)
	_dog_part("Muzzle", Vector3(0.17, 0.12, 0.16), Vector3(0, -0.04, -0.20), Color("f5dfb6"))
	_dog_part("Nose", Vector3(0.08, 0.055, 0.035), Vector3(0, -0.012, -0.29), Color("17202b"))
	_dog_part("Mouth", Vector3(0.13, 0.022, 0.06), Vector3(0, -0.086, -0.27), Color("17202b"))
	for side in [-1.0, 1.0]:
		var ear := _dog_part("Ear", Vector3(0.075, 0.22, 0.12), Vector3(side * 0.12, -0.01, 0.01), fur.darkened(0.32))
		ear.rotation.z = side * 0.16
		_dog_part("Eye", Vector3(0.025, 0.035, 0.026), Vector3(side * 0.061, 0.074, -0.154), Color("17202b"))
		_dog_part("EyeGlint", Vector3(0.009, 0.012, 0.006), Vector3(side * 0.062, 0.08, -0.169), Color.WHITE)
	_dog_part("Collar", Vector3(0.21, 0.05, 0.27), Vector3(0, -0.13, 0.04), Color("5fcca7"))
	for part in get_children():
		if part is MeshInstance3D:
			part.scale *= 0.7
			part.position *= 0.7

func _create_breed_visual() -> bool:
	var path := DogBreeds.model_path(stats.breed_id)
	if path.is_empty():
		return false
	var scene := load(path) as PackedScene
	if scene == null:
		push_warning("Breed model unavailable: %s" % stats.breed_id)
		return false
	breed_model = scene.instantiate() as Node3D
	breed_model.name = "BreedDog"
	breed_model.position = BREED_HELD_POSITION
	breed_model.scale = Vector3.ONE * BREED_HELD_SCALE
	add_child(breed_model)
	var type_color := Color("ff8a57")
	match stats.gun_type:
		GunTypes.Type.IMPLOSIVE: type_color = Color("ad83d4")
		GunTypes.Type.FREEZING: type_color = Color("74d8ed")
		GunTypes.Type.ACCELERATING: type_color = Color("9be472")
	for part in breed_model.find_children("*", "MeshInstance3D", true, false):
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		part.layers = MAPPO_RENDER_LAYER
		for surface in range(part.mesh.get_surface_count()):
			var material: Material = part.get_active_material(surface)
			if material is StandardMaterial3D and material.resource_name == "TypeCollar":
				var collar := material.duplicate() as StandardMaterial3D
				collar.albedo_color = type_color
				part.set_surface_override_material(surface, collar)
	var fill := OmniLight3D.new()
	fill.name = "BreedFill"
	fill.position = Vector3(0.0, 0.3, 0.1)
	fill.light_color = Color(1.0, 0.94, 0.86)
	fill.light_energy = 0.03
	fill.omni_range = 2.0
	fill.light_cull_mask = MAPPO_RENDER_LAYER
	fill.shadow_enabled = false
	fill.light_bake_mode = Light3D.BAKE_DISABLED
	fill.light_volumetric_fog_energy = 0.0
	add_child(fill)
	return true

func get_breed_anchor(anchor_name: String) -> Vector3:
	if not is_instance_valid(breed_model):
		return Vector3.ZERO
	var anchor := breed_model.find_child(anchor_name, true, false) as Node3D
	if anchor == null:
		return Vector3.ZERO
	var relative := Transform3D.IDENTITY
	var cursor: Node = anchor
	while cursor and cursor != self:
		if cursor is Node3D:
			relative = cursor.transform * relative
		cursor = cursor.get_parent()
	return relative.origin

func _animate_breed_shot() -> void:
	if not is_instance_valid(breed_model):
		return
	if _breed_recoil and _breed_recoil.is_valid():
		_breed_recoil.kill()
	_breed_recoil = create_tween()
	_breed_recoil.tween_property(breed_model, "position", BREED_HELD_POSITION + Vector3(0, 0.004, 0.02), 0.035)
	_breed_recoil.tween_property(breed_model, "position", BREED_HELD_POSITION, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _create_mascot_visual() -> bool:
	var scene := load(MAPPO_SCENE) as PackedScene
	if scene == null:
		push_warning("Mappo's model could not be loaded; using the regular pup visual.")
		return false
	mascot_model = scene.instantiate() as Node3D
	if mascot_model == null:
		return false
	mascot_model.name = "Mappo"
	mascot_model.set("animate", false)
	mascot_model.position = MAPPO_HELD_POSITION
	mascot_model.scale = Vector3.ONE * MAPPO_HELD_SCALE
	mascot_model.rotation_degrees.y = MAPPO_HELD_YAW
	add_child(mascot_model)
	# The front paws sit below the muzzle; upright ears remain below the reticle.
	# Disable held-model shadows so the camera weapon does not darken the room.
	for part in mascot_model.find_children("*", "MeshInstance3D", true, false):
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		part.layers = MAPPO_RENDER_LAYER
	var fill := OmniLight3D.new()
	fill.name = "MappoFill"
	fill.position = Vector3(0.0, 0.4, 0.2)
	fill.light_color = Color(1.0, 0.94, 0.86)
	fill.light_energy = 0.75
	fill.omni_range = 2.0
	fill.light_cull_mask = MAPPO_RENDER_LAYER
	fill.shadow_enabled = false
	fill.light_bake_mode = Light3D.BAKE_DISABLED
	fill.light_volumetric_fog_energy = 0.0
	# A weapon child inherits visibility on slot changes; its private layer keeps
	# this soft camera-side fill off rooms, enemies, and the regular pup weapons.
	add_child(fill)
	return true

func _animate_mascot_shot() -> void:
	if not is_instance_valid(mascot_model):
		return
	if mascot_model.has_method("bark"):
		mascot_model.bark()
	if _mascot_recoil and _mascot_recoil.is_valid():
		_mascot_recoil.kill()
	_mascot_recoil = create_tween()
	_mascot_recoil.tween_property(mascot_model, "position", MAPPO_HELD_POSITION + Vector3(0, 0.005, 0.025), 0.035)
	_mascot_recoil.tween_property(mascot_model, "position", MAPPO_HELD_POSITION, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _dog_part(part_name: String, dimensions: Vector3, offset: Vector3, color: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	var box := BoxMesh.new()
	box.size = dimensions
	part.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	part.material_override = mat
	part.position = offset
	add_child(part)
	return part


func _process(delta: float) -> void:
	if not can_fire:
		fire_timer = maxf(0.0, fire_timer - delta)
		if fire_timer <= 0:
			can_fire = not is_reloading
	if is_reloading:
		var animation_delta := delta
		if _reload_delay > 0.0:
			animation_delta = maxf(0.0, delta - _reload_delay)
			_reload_delay = maxf(0.0, _reload_delay - delta)
		reload_remaining = maxf(0.0, reload_remaining - animation_delta)
		_animate_reload()
		if reload_remaining <= 0.0 and _reload_delay <= 0.0:
			_finish_reload()

func fire(origin: Vector3, direction: Vector3, w_position: float = 0.0) -> void:
	if not stats:
		print("[Gun] No stats - cannot fire")
		return
	
	if not can_fire or is_reloading:
		return
	
	if current_ammo <= 0:
		reload()
		return
	
	# Consume ammo
	current_ammo -= 1
	ammo_changed.emit(current_ammo, get_magazine_size())
	
	# Fire rate cooldown
	can_fire = false
	fire_timer = get_shot_interval()
	
	# Check for crit
	var crit_tiers := roll_crit_tiers()
	
	# Calculate how many projectiles to spawn
	var projectile_count: int = maxi(1, roundi((stats.get_projectile_count() + _bonus("extra_shots")) * _all_stats_factor()))
	
	for i in range(projectile_count):
		var spread_direction = _apply_accuracy_spread(direction)
		_spawn_projectile(origin, spread_direction, crit_tiers > 0, w_position, crit_tiers)
	
	_animate_mascot_shot()
	_animate_breed_shot()
	gun_fired.emit()
	if current_ammo == 0:
		reload()

func _apply_accuracy_spread(direction: Vector3) -> Vector3:
	if not stats:
		return direction
	
	# Higher accuracy = less spread
	var spread_amount = (1.0 - clampf(stats.accuracy * _all_stats_factor(), 0.0, 1.0)) * 0.15
	
	# Random spread within cone
	var spread_x = randf_range(-spread_amount, spread_amount)
	var spread_y = randf_range(-spread_amount, spread_amount)
	
	var spread_dir = direction + Vector3(spread_x, spread_y, 0)
	return spread_dir.normalized()

func _spawn_projectile(origin: Vector3, direction: Vector3, is_crit: bool, w_position: float = 0.0, crit_tiers: int = 1) -> void:
	# Create actual projectile with 4D position
	var shooter: Node3D = get_tree().get_first_node_in_group("player")
	var projectile: Projectile = Projectile.create_from_stats(stats, origin, direction, shooter, w_position, false)
	projectile.damage *= _multiplier("damage")
	projectile.speed *= _multiplier("projectile_speed")
	var homing_copies := _bonus_count("homing")
	projectile.speed += homing_copies
	projectile.homing_strength = 0.0 if homing_copies == 0 else 6.0 + homing_copies
	var bounce_copies := _bonus_count("bounce")
	projectile.bounce_count = 0 if bounce_copies == 0 else 2 + bounce_copies
	projectile.laser_guided = _bonus_count("lazer") > 0
	projectile.power_multiplier = _all_stats_factor()
	projectile.scale *= _all_stats_factor()
	# The projectile keeps this resource after its dog switches slots or reloads.
	projectile.gun_stats = stats.duplicate() as GunStats
	projectile.gun_stats.knockback_force *= _all_stats_factor()
	
	# Apply crit damage
	if is_crit:
		projectile.damage *= pow(stats.get_scaled_crit_damage() * _all_stats_factor(), crit_tiers)
		print("[Gun] CRITICAL HIT!")
	
	# Add to scene safely
	var tree = get_tree()
	if tree and tree.current_scene:
		tree.current_scene.add_child(projectile)
		load("res://scripts/items/item_attachments.gd").decorate_projectile(projectile, int(_bonus_count("flagella")))
		projectile.launch(direction)
	elif get_parent():
		get_parent().add_child(projectile)
		projectile.launch(direction)
	else:
		projectile.queue_free()
		print("[Gun] Error: Could not add projectile to scene")

func reload() -> void:
	if not stats or is_reloading or current_ammo >= get_magazine_size():
		return
	is_reloading = true
	can_fire = false
	_reload_delay = maxf(0.0, fire_timer)
	reload_duration = get_reload_seconds()
	reload_remaining = reload_duration
	_reload_base_transform = transform
	for recoil in [_mascot_recoil, _breed_recoil]:
		if recoil and recoil.is_valid():
			recoil.kill()
	if is_instance_valid(breed_model):
		breed_model.position = BREED_HELD_POSITION
	if is_instance_valid(mascot_model):
		mascot_model.position = MAPPO_HELD_POSITION
	_reload_head = breed_model.find_child("HeadRoot", true, false) as Node3D if is_instance_valid(breed_model) else null
	if is_instance_valid(_reload_head):
		_reload_head_base_basis = _reload_head.basis
	_capture_reload_head_attachments()
	_reload_barked = false
	_reload_treat = _dog_part("ReloadTreat", Vector3(0.07, 0.035, 0.04), Vector3.ZERO, Color("e8ba6b"))
	_reload_treat.layers = MAPPO_RENDER_LAYER
	_reload_treat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	reload_started.emit(reload_duration + _reload_delay)
	_animate_reload()

func _animate_reload() -> void:
	var progress := 1.0 - reload_remaining / maxf(reload_duration, 0.001)
	var envelope := sin(PI * progress)
	var signature := float(abs(hash(stats.breed_id if not stats.breed_id.is_empty() else stats.gun_name)) % 1024) / 256.0
	var wag := sin(progress * TAU * (2.0 + signature * 0.5)) * envelope
	var motion: Dictionary = RELOAD_MOTION.sample(progress, stats.breed_id if not stats.breed_id.is_empty() else stats.gun_name)
	var body_rotation := Vector3(0.45 * envelope, 0.1 * wag, 0.18 * wag)
	if not motion.is_empty():
		body_rotation = motion.body_rotation * envelope + Vector3(0, 0.035 * wag, 0.04 * wag)
		if is_instance_valid(_reload_head):
			_reload_head.basis = _reload_head_base_basis * Basis.from_euler(motion.head_rotation * envelope)
			var head_delta := _relative_to_gun(_reload_head) * _reload_head_transform.affine_inverse()
			for part in _reload_head_attachments:
				if is_instance_valid(part.node):
					part.node.transform = head_delta * part.transform
		else:
			# The simple starter head is the held model; Mappo additionally has
			# an articulated jaw, driven by his original mouth-open animation.
			body_rotation += motion.head_rotation * envelope
	transform = _reload_base_transform * Transform3D(Basis.from_euler(body_rotation), Vector3(0, -0.09 * envelope, 0.06 * envelope))
	if progress >= 0.55 and not _reload_barked:
		_reload_barked = true
		if is_instance_valid(mascot_model):
			mascot_model.bark()
	if is_instance_valid(_reload_treat):
		var mouth := get_breed_anchor("MouthAnchor") if is_instance_valid(breed_model) else Vector3(0, -0.06, -0.2)
		_reload_treat.position = mouth + Vector3(0.13 * (1.0 - progress), 0.09 * envelope, -0.18 * (1.0 - progress))
		_reload_treat.rotation.z = progress * TAU
		_reload_treat.visible = progress < 0.85 and _reload_delay <= 0.0

func _finish_reload() -> void:
	transform = _reload_base_transform
	if is_instance_valid(_reload_head):
		_reload_head.basis = _reload_head_base_basis
	_reload_head = null
	_restore_reload_attachments()
	is_reloading = false
	reload_remaining = 0.0
	_reload_delay = 0.0
	can_fire = fire_timer <= 0.0
	if is_instance_valid(_reload_treat):
		_reload_treat.queue_free()
	_reload_treat = null
	current_ammo = get_magazine_size()
	ammo_changed.emit(current_ammo, get_magazine_size())
	gun_reloaded.emit()

func refill_magazine() -> void:
	# Floor transitions grant fresh magazines without playing a combat reload.
	if is_reloading:
		transform = _reload_base_transform
		if is_instance_valid(_reload_head):
			_reload_head.basis = _reload_head_base_basis
	_reload_head = null
	_restore_reload_attachments()
	is_reloading = false
	reload_remaining = 0.0
	_reload_delay = 0.0
	fire_timer = 0.0
	can_fire = true
	if is_instance_valid(_reload_treat):
		_reload_treat.queue_free()
	_reload_treat = null
	current_ammo = get_magazine_size()
	ammo_changed.emit(current_ammo, current_ammo)

func rebase_reload_animation(new_base: Transform3D) -> void:
	transform = new_base
	if is_reloading:
		_reload_base_transform = new_base
		_animate_reload()

func _relative_to_gun(node: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var cursor: Node = node
	while cursor and cursor != self:
		if cursor is Node3D:
			result = cursor.transform * result
		cursor = cursor.get_parent()
	return result

func _restore_reload_attachments() -> void:
	for part in _reload_head_attachments:
		if is_instance_valid(part.node):
			part.node.transform = part.transform
	_reload_head_attachments.clear()

func _capture_reload_head_attachments() -> void:
	_reload_head_attachments.clear()
	if not is_instance_valid(_reload_head):
		return
	_reload_head_transform = _relative_to_gun(_reload_head)
	var attachments := get_node_or_null("ItemAttachments")
	if attachments:
		for part in attachments.get_children():
			if part is Node3D and (str(part.name).begins_with("MouthBall_") or str(part.name).begins_with("Glasses_")):
				_reload_head_attachments.append({"node":part, "transform":part.transform})

func get_reload_seconds() -> float:
	return stats.get_reload_seconds() / _all_stats_factor() if stats else 0.0

func get_shot_interval() -> float:
	return stats.fire_rate * _multiplier("fire_rate") if stats else 0.0

func _all_stats_factor() -> float:
	var run = get_tree().get_first_node_in_group("run_manager") if is_inside_tree() else null
	return run.get_all_stats_factor(get_instance_id()) if run else 1.0

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

func _multiplier(stat: String) -> float:
	var run = get_tree().get_first_node_in_group("run_manager") if is_inside_tree() else null
	return run.get_stat_multiplier(stat, stats.gun_type, get_instance_id()) if run and stats else 1.0

func _bonus(stat: String) -> float:
	var run = get_tree().get_first_node_in_group("run_manager") if is_inside_tree() else null
	return run.get_stat_bonus(stat, stats.gun_type, get_instance_id()) if run and stats else 0.0

func get_magazine_size() -> int:
	return roundi((stats.max_ammo + _bonus("ammo")) * _all_stats_factor()) if stats else 0

func get_crit_chance() -> float:
	return maxf(0.0, (stats.get_scaled_crit_chance() + _bonus("crit_chance")) * _all_stats_factor()) if stats else 0.0

func roll_crit_tiers(random_value: float = -1.0) -> int:
	var chance := get_crit_chance()
	var guaranteed := int(floor(chance))
	var roll := randf() if random_value < 0.0 else random_value
	return guaranteed + (1 if roll < chance - guaranteed else 0)

func _bonus_count(id: String) -> int:
	var run = get_tree().get_first_node_in_group("run_manager") if is_inside_tree() else null
	return run.get_item_count(id, get_instance_id()) if run else 0

func refresh_item_visuals() -> void:
	# Items acquired or dogs transferred mid-reload must rebuild from neutral
	# anchors; otherwise the current bow becomes their permanent base pose.
	if is_reloading:
		if is_instance_valid(_reload_head):
			_reload_head.basis = _reload_head_base_basis
		_restore_reload_attachments()
	load("res://scripts/items/item_attachments.gd").refresh_gun(self)
	if is_reloading:
		_capture_reload_head_attachments()
		_animate_reload()
