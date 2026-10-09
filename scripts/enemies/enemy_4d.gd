# Enemy4D - Base class for enemies that can navigate 4D surfaces
# Uses SurfaceWalker4D for movement with sticky gravity on hyperspheres etc.
class_name Enemy4D
extends CharacterBody3D

signal died(enemy: Enemy4D)
signal damaged(current_health: int, max_health: int)
signal boss_phase_changed(phase: int)

enum Archetype { GRUNT, RUSHER, SNIPER, BRUTE, BOSS }
@export var archetype: Archetype = Archetype.GRUNT
@export var difficulty: float = 1.0
@export var dolphin_id: String = ""
var display_name: String = "Kennel Guard"
var boss_phase: int = 1
var _configured: bool = false
var _dead: bool = false
var _body_radius: float = 0.4
var _body_height: float = 1.5
var _attack_windup: float = 0.0
var _aim_direction: Vector3 = Vector3.FORWARD
var _attack_number: int = 0
var _ice_shell: MeshInstance3D
var _warning_ring: MeshInstance3D
var _attack_stats: GunStats
var _dolphin_model: Node3D
var _visual_clock: float = 0.0
var _animated_fins: Array[Node3D] = []

## Call before adding to the scene. All archetypes retain the same surface physics.
func configure_archetype(kind: int, difficulty_scale: float = 1.0) -> void:
	archetype = clampi(kind, Archetype.GRUNT, Archetype.BOSS) as Archetype
	difficulty = maxf(difficulty_scale, 0.5)
	_configured = true
	_body_radius = 0.4
	_body_height = 1.5
	view_range = 55.0
	view_angle = 180.0
	match archetype:
		Archetype.GRUNT:
			display_name = "Kennel Guard"
			max_health = 45
			move_speed = 3.5
			fire_rate = 1.5
			attack_range = 28.0
		Archetype.RUSHER:
			display_name = "Zoomie"
			max_health = 30
			move_speed = 8.0
			fire_rate = 1.15
			attack_range = 2.7
			enemy_type = GunTypes.Type.ACCELERATING
			_body_radius = 0.32
			_body_height = 1.1
		Archetype.SNIPER:
			display_name = "Watchdog"
			max_health = 40
			move_speed = 2.7
			fire_rate = 2.7
			attack_range = 48.0
			enemy_type = GunTypes.Type.FREEZING
			_body_radius = 0.3
			_body_height = 1.9
		Archetype.BRUTE:
			display_name = "Bark Tank"
			max_health = 110
			move_speed = 2.2
			fire_rate = 2.25
			attack_range = 21.0
			enemy_type = GunTypes.Type.IMPLOSIVE
			_body_radius = 0.65
			_body_height = 1.8
		Archetype.BOSS:
			display_name = "THE BIG BAD GOOD BOY"
			max_health = 420
			move_speed = 2.5
			fire_rate = 2.4
			attack_range = 60.0
			view_range = 90.0
			enemy_type = GunTypes.Type.EXPLOSIVE
			_body_radius = 1.1
			_body_height = 3.1
	max_health = maxi(1, roundi(max_health * difficulty))
	var defaults := DolphinCatalog.for_archetype(archetype)
	if not defaults.is_empty():
		dolphin_id = str(defaults[0].id)
		display_name = str(defaults[0].name)

## A seeded room spawn chooses its silhouette and carried dog once, before _ready.
func configure_dolphin(id: String, difficulty_scale: float = 1.0, rng: RandomNumberGenerator = null) -> void:
	var definition := DolphinCatalog.get_definition(id)
	if definition.is_empty():
		definition = DolphinCatalog.CATALOG[0]
	configure_archetype(int(definition.archetype), difficulty_scale)
	dolphin_id = str(definition.id)
	display_name = str(definition.name)
	max_health = maxi(1, roundi(max_health * float(definition.health)))
	move_speed *= float(definition.speed)
	fire_rate *= float(definition.interval)
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	gun_stats = DogBreeds.create_stats(rng, "", GunTypes.Rarity.OK)
	enemy_type = gun_stats.gun_type

func is_boss() -> bool:
	return archetype == Archetype.BOSS

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
var stunned_timer: float = 0.0
## Consecutive direct ice hits build 1%, 2%, ... 100% within a half-second chain.
var freezing_hit_count: int = 0
var freezing_hit_window: float = 0.0
const FREEZING_HIT_WINDOW: float = 0.5
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
	if not _configured and archetype != Archetype.GRUNT:
		configure_archetype(archetype, difficulty)
	if dolphin_id.is_empty():
		var defaults := DolphinCatalog.for_archetype(archetype)
		dolphin_id = str(defaults[0].id)
		display_name = str(defaults[0].name)
	# The carried weapon remains player-strength loot. Enemy attack tuning lives
	# in a separate resource, so phases and difficulty never corrupt the drop.
	if gun_stats == null:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		gun_stats = DogBreeds.create_stats(rng, "", GunTypes.Rarity.OK)
	enemy_type = gun_stats.gun_type
	_attack_stats = gun_stats.duplicate(true) as GunStats
	_attack_stats.rarity = GunTypes.Rarity.POOR
	_attack_stats.base_damage = (14.0 if is_boss() else 10.0) * sqrt(difficulty)
	_attack_stats.projectile_speed = 35.0 if archetype == Archetype.SNIPER else 22.0
	_attack_stats.projectile_count = 1
	_attack_stats.crit_chance = 0.0
	_attack_stats.accuracy = 0.97 if archetype == Archetype.SNIPER else 0.85
	current_health = max_health
	add_to_group("enemies")
	if is_boss():
		add_to_group("bosses")
	position_4d = Vector4D.from_vector3(global_position, initial_w)

	# Create visual mesh if not already present
	if get_node_or_null("MeshInstance3D") == null:
		_create_visual()

	# Create collision shape if not already present
	if get_node_or_null("CollisionShape3D") == null:
		_create_collision()

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
	# Keep the legacy root name so W-slice scaling affects the full dolphin.
	var body := Node3D.new()
	body.name = "MeshInstance3D"
	add_child(body)
	var path := DolphinCatalog.model_path(dolphin_id)
	if ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed:
			_dolphin_model = packed.instantiate() as Node3D
			_dolphin_model.name = "DolphinModel"
			_dolphin_model.scale = Vector3.ONE * (_body_height / 1.5)
			body.add_child(_dolphin_model)
			for part in _dolphin_model.find_children("*", "Node3D", true, false):
				if str(part.name).begins_with("TailFluke") or str(part.name).begins_with("Flipper"):
					part.set_meta("rest_rotation", part.rotation)
					_animated_fins.append(part)
	if _dolphin_model == null:
		# Minimal dolphin-shaped fallback while Godot is importing new GLBs.
		_create_fallback_dolphin(body)
	_create_status_visuals(body)
	_create_carried_dog()
	_create_health_bar()
	var label := Label3D.new()
	label.name = "DolphinName"
	label.text = display_name
	label.font_size = 32 if is_boss() else 22
	label.pixel_size = 0.007
	label.position.y = _body_height + 0.95
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1.0, 0.75, 0.3) if is_boss() else Color(0.8, 0.9, 1.0)
	add_child(label)

func _create_fallback_dolphin(body: Node3D) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.32, 0.64, 0.73)
	for info in [
		[Vector3(0, _body_height * 0.46, 0), Vector3(0.7, 0.5, 1.45)],
		[Vector3(0, _body_height * 0.49, -0.82), Vector3(0.28, 0.18, 0.70)],
		[Vector3(-0.42, _body_height * 0.39, 0.64), Vector3(0.64, 0.07, 0.25)],
		[Vector3(0.42, _body_height * 0.39, 0.64), Vector3(0.64, 0.07, 0.25)]]:
		var part := MeshInstance3D.new()
		var shape := SphereMesh.new()
		shape.radial_segments = 8
		shape.rings = 4
		part.mesh = shape
		part.scale = info[1]
		part.position = info[0]
		part.material_override = material
		body.add_child(part)
	var dorsal := MeshInstance3D.new()
	var fin := PrismMesh.new()
	fin.size = Vector3(0.10, 0.45, 0.45)
	dorsal.mesh = fin
	dorsal.position = Vector3(0, _body_height * 0.7, 0.10)
	dorsal.material_override = material
	body.add_child(dorsal)

func _create_carried_dog() -> void:
	var gun_root := Node3D.new()
	gun_root.name = "GunMesh"
	gun_root.position = Vector3(_body_radius * 1.7, _body_height * 0.56, -_body_radius * 0.65)
	add_child(gun_root)
	var path := DogBreeds.model_path(gun_stats.breed_id)
	if ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed:
			var dog := packed.instantiate() as Node3D
			dog.name = "CarriedDog"
			dog.scale = Vector3.ONE * (0.36 if not is_boss() else 0.60)
			gun_root.add_child(dog)
	# A glowing type tag links the visible dog to its eventual fixed-type drop.
	var tag := MeshInstance3D.new()
	tag.name = "DogTypeTag"
	var badge := SphereMesh.new()
	badge.radius = 0.075
	badge.height = 0.15
	badge.radial_segments = 8
	badge.rings = 4
	tag.mesh = badge
	tag.position = Vector3(0.16, 0.16, -0.16)
	var type_color: Color = [Color("ef713e"), Color("ba73df"), Color("75d9fa"), Color("75df86")][gun_stats.gun_type]
	var tag_material := StandardMaterial3D.new()
	tag_material.albedo_color = type_color
	tag_material.emission_enabled = true
	tag_material.emission = type_color
	tag_material.emission_energy_multiplier = 0.65
	tag.material_override = tag_material
	gun_root.add_child(tag)
	var muzzle := MeshInstance3D.new()
	muzzle.name = "MuzzleFlash"
	var flash := SphereMesh.new()
	flash.radius = 0.15
	flash.height = 0.3
	muzzle.mesh = flash
	muzzle.position = Vector3(_body_radius * 1.7, _body_height * 0.6, -_body_radius - 0.30)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = type_color
	glow.emission_enabled = true
	glow.emission = type_color
	glow.emission_energy_multiplier = 3.0
	muzzle.material_override = glow
	muzzle.visible = false
	add_child(muzzle)

func _create_status_visuals(body: Node3D) -> void:
	_ice_shell = MeshInstance3D.new()
	var crystal := PrismMesh.new()
	crystal.size = Vector3(_body_radius * 2.8, _body_height * 1.3, _body_radius * 3.8)
	_ice_shell.mesh = crystal
	_ice_shell.position.y = _body_height * 0.5
	var ice := StandardMaterial3D.new()
	ice.albedo_color = Color(0.3, 0.85, 1.0, 0.3)
	ice.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ice.emission_enabled = true
	ice.emission = Color(0.2, 0.7, 1.0)
	ice.emission_energy_multiplier = 0.7
	_ice_shell.material_override = ice
	_ice_shell.visible = false
	body.add_child(_ice_shell)
	_warning_ring = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = _body_radius * 1.2
	ring.outer_radius = _body_radius * 1.4
	ring.rings = 20
	ring.ring_segments = 6
	_warning_ring.mesh = ring
	var warning := StandardMaterial3D.new()
	warning.albedo_color = Color(1.0, 0.35, 0.15)
	warning.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	warning.emission_enabled = true
	warning.emission = warning.albedo_color
	warning.emission_energy_multiplier = 2.0
	_warning_ring.material_override = warning
	_warning_ring.visible = false
	_warning_ring.position.y = _body_height * 0.8
	body.add_child(_warning_ring)

func _process(delta: float) -> void:
	if _dead or frozen_timer > 0.0 or stunned_timer > 0.0:
		return
	_visual_clock += delta
	if _dolphin_model:
		_dolphin_model.position.y = sin(_visual_clock * 2.6) * 0.035
	for fin in _animated_fins:
		if is_instance_valid(fin):
			var rest: Vector3 = fin.get_meta("rest_rotation", Vector3.ZERO)
			fin.rotation = rest + Vector3(sin(_visual_clock * 5.0) * 0.06, 0, 0)
func _create_collision() -> void:
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"

	var shape := CapsuleShape3D.new()
	shape.radius = _body_radius
	shape.height = _body_height
	collision.shape = shape
	collision.position.y = _body_height * 0.5

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
	health_bar_container.position = Vector3(0, _body_height + 0.65, 0)
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
		collision_layer = 0
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
	collision_layer = 4

## Check if enemy can attack (must be in similar W position as target)
func _can_attack_target() -> bool:
	return _can_attack_same_slice() and global_position.distance_to(target.global_position) <= attack_range

## Legacy function name for compatibility
func _update_visibility(slice_w: float) -> void:
	_update_slice_visibility(slice_w)

func _find_target() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		target = players[0]

func _physics_process(delta: float) -> void:
	if _dead or get_tree().paused:
		return
	_tick_freezing_hit_window(delta)
	var interior_room := _get_interior_room()
	if not is_instance_valid(target):
		_find_target()
	if fire_cooldown > 0:
		fire_cooldown -= delta

	# Handle frozen state
	if frozen_timer > 0 or stunned_timer > 0:
		stunned_timer = maxf(0.0, stunned_timer - delta)
		var stars := get_node_or_null("StunStars")
		if stars:
			stars.visible = stunned_timer > 0.0
			stars.rotation.y += delta * 4.0
		frozen_timer = maxf(0.0, frozen_timer - delta)
		if _ice_shell:
			_ice_shell.visible = frozen_timer > 0.0
		# Still apply external velocity even when frozen
		if external_velocity.length_squared() > 0.01:
			velocity = external_velocity
			external_velocity = external_velocity.lerp(Vector3.ZERO, minf(1.0, EXTERNAL_VELOCITY_DECAY * delta))
			move_and_slide()
		_contain_in_room(interior_room)
		_sync_position_4d()
		return  # Skip all AI logic when frozen
	_update_attack_windup(delta)

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
	if not visible:
		return

	# Check if we should use 4D physics (only if surfaces exist)
	var use_4d_physics: bool = enable_4d_mode and surface_walker and surface_walker.physics.surfaces.size() > 0

	if use_4d_physics:
		_physics_process_4d(delta)
	else:
		_physics_process_3d(delta)
	# Apply crowd-control after AI so chase velocity cannot overwrite it.
	if external_velocity.length_squared() > 0.01:
		var locomotion := velocity
		velocity = external_velocity
		move_and_slide()
		velocity = locomotion
		external_velocity = external_velocity.lerp(Vector3.ZERO, minf(1.0, EXTERNAL_VELOCITY_DECAY * delta))
	_contain_in_room(interior_room)
	_sync_position_4d()

func _sync_position_4d() -> void:
	position_4d = Vector4D.from_vector3(global_position, position_4d.w)
	if surface_walker:
		surface_walker.set_position(position_4d)

func _reset_to_full_visibility() -> void:
	visible = true
	collision_layer = 4
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

	if current_state == State.CHASING and distance_moved < minf(STUCK_THRESHOLD, move_speed * delta * 0.15) and not _floor_only_mode:
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

## Adjoining rooms share a visible W slice near a portal. Scene-tree order
## must never choose a neighbor's gravity for a room-owned encounter enemy.
func _get_interior_room() -> Node3D:
	var owner_id := int(get_meta("encounter_room", -1))
	var nearest: Node3D = null
	var nearest_ratio := INF
	for room in get_tree().get_nodes_in_group("room_spheres_4d"):
		if not is_instance_valid(room):
			continue
		if owner_id >= 0:
			if room.get("room_id") == owner_id:
				return room
			continue
		if room.get("_position_4d") != null and absf(room._position_4d.w - position_4d.w) > 0.5:
			continue
		var radius: float = room.radius
		var distance := global_position.distance_to(room.global_position)
		if distance < radius + 2.0 and distance / radius < nearest_ratio:
			nearest = room
			nearest_ratio = distance / radius
	return nearest

## Encounter enemies stay in their room, including when frozen or knocked back.
## Apply after movement as well as the interior solver's pre-movement clamp.
func _contain_in_room(room: Node3D) -> void:
	if not is_instance_valid(room):
		return
	var offset := global_position - room.global_position
	var limit: float = maxf(0.1, room.radius - 0.8)
	if offset.length_squared() <= limit * limit:
		return
	var outward := offset.normalized()
	global_position = room.global_position + outward * limit
	velocity -= outward * maxf(0.0, velocity.dot(outward))
	external_velocity -= outward * maxf(0.0, external_velocity.dot(outward))

## Handle physics for being inside a RoomSphere4D (hollow sphere)
## Returns true if enemy is inside a room sphere and physics were applied
func _handle_room_sphere_interior(delta: float) -> bool:
	# Resolve ownership before considering the nearby sphere geometry.
	var room := _get_interior_room()
	if not room or not is_instance_valid(room):
		return false

	var room_radius: float = room.radius if room.get("radius") else 20.0

	# Check W-coordinate match - skip rooms on different W slices
	if room.get("_position_4d") != null:
		var room_w: float = room._position_4d.w
		if abs(room_w - position_4d.w) > 0.5:
			return false  # Wrong W slice

	var room_center: Vector3 = room.global_position
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
	rotate_object_local(Vector3.UP, spin_speed * delta)
	velocity = up_direction * velocity.dot(up_direction)
	if surface_walker:
		surface_walker.set_input(Vector3.ZERO)
	if aggro_enabled and is_instance_valid(target) and _can_see_target():
		current_state = State.CHASING

func set_aggro_enabled(enabled: bool) -> void:
	aggro_enabled = enabled
	if not enabled:
		current_state = State.SEARCHING
		_attack_windup = 0.0
		if _warning_ring:
			_warning_ring.visible = false

func _desired_chase_direction(surface_up: Vector3) -> Vector3:
	if not is_instance_valid(target) or not aggro_enabled or not _can_attack_same_slice():
		current_state = State.SEARCHING
		return Vector3.ZERO
	var offset: Vector3 = target.global_position - global_position
	var direction: Vector3 = offset.slide(surface_up).normalized()
	if direction.length_squared() > 0.01:
		look_at(global_position + direction, surface_up)
	if fire_cooldown <= 0.0 and _attack_windup <= 0.0 and _can_attack_target() and _has_clear_shot():
		_fire_at_target()
		fire_cooldown = fire_rate
	if _attack_windup > 0.0:
		return Vector3.ZERO
	# Watchdogs retreat to a shooting lane; tanks and bosses keep room to dodge.
	var distance: float = offset.length()
	if archetype == Archetype.SNIPER:
		if distance < 10.0:
			return -direction
		if distance < 23.0:
			return Vector3.ZERO
	elif is_boss() and distance < 10.0:
		return direction.cross(surface_up).normalized() * 0.6
	elif archetype == Archetype.BRUTE and distance < 5.0:
		return Vector3.ZERO
	return direction

func _state_chasing_3d(_delta: float) -> void:
	var surface_up: Vector3 = up_direction.normalized()
	var direction := _desired_chase_direction(surface_up)
	velocity = direction * move_speed + surface_up * velocity.dot(surface_up)
	if surface_walker:
		surface_walker.set_input(Vector3.ZERO)

func _state_chasing_4d(delta: float) -> void:
	if not surface_walker or not _is_near_4d_surface():
		_state_chasing_3d(delta)
		return
	var surface_up: Vector3 = surface_walker.get_gravity_direction().negate().to_vector3().normalized()
	if surface_up.length_squared() < 0.01:
		surface_up = up_direction
	var direction := _desired_chase_direction(surface_up)
	# SurfaceWalker uses a world tangent basis, not the character's facing basis.
	var tangent_right: Vector3 = surface_walker._get_surface_relative_movement(Vector3.RIGHT).to_vector3()
	var tangent_forward: Vector3 = surface_walker._get_surface_relative_movement(Vector3.FORWARD).to_vector3()
	surface_walker.set_input(Vector3(direction.dot(tangent_right), 0.0, -direction.dot(tangent_forward)))

func _state_attacking(delta: float) -> void:
	_state_chasing_3d(delta)

func _can_attack_same_slice() -> bool:
	if not is_instance_valid(target):
		return false
	var target_w: float = 0.0
	if target.has_method("get_position_4d"):
		target_w = target.get_position_4d().w
	return absf(position_4d.w - target_w) < ENEMY_W_RADIUS

func _has_clear_shot() -> bool:
	if not is_instance_valid(target):
		return false
	var query := PhysicsRayQueryParameters3D.create(
		global_position + global_basis.y * _body_height * 0.6,
		target.global_position + target.global_basis.y * 0.8,
		1 | 4)
	query.exclude = [get_rid()]
	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return result.is_empty() or result.collider == target

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
	if not is_instance_valid(target) or not _can_attack_target():
		return
	_aim_direction = (target.global_position + target.global_basis.y * 0.8 - _muzzle_position()).normalized()
	match archetype:
		Archetype.RUSHER:
			_attack_windup = 0.32
		Archetype.SNIPER:
			_attack_windup = 0.8
		Archetype.BOSS:
			_attack_windup = 0.85 if boss_phase == 1 else 0.6
		_:
			_release_attack()
	if _attack_windup > 0.0 and _warning_ring:
		_warning_ring.visible = true
		_warning_ring.scale = Vector3.ONE * 0.5

func _muzzle_position() -> Vector3:
	var flash := get_node_or_null("MuzzleFlash") as Node3D
	if flash:
		return flash.global_position
	return global_position + global_basis.y * _body_height * 0.6 - global_basis.z * (_body_radius + 0.25)

func _update_attack_windup(delta: float) -> void:
	if _attack_windup <= 0.0:
		return
	if not aggro_enabled or not _can_attack_same_slice():
		_attack_windup = 0.0
		if _warning_ring:
			_warning_ring.visible = false
		return
	_attack_windup -= delta
	if _warning_ring:
		_warning_ring.scale += Vector3.ONE * delta
		_warning_ring.rotate_y(delta * 6.0)
	if _attack_windup <= 0.0:
		if _warning_ring:
			_warning_ring.visible = false
		if _can_attack_target() and _has_clear_shot():
			_release_attack()

func _release_attack() -> void:
	if not is_instance_valid(target):
		return
	if archetype == Archetype.RUSHER:
		if global_position.distance_to(target.global_position) <= attack_range and target.has_method("take_damage"):
			target.take_damage(roundi(9.0 * sqrt(difficulty)), enemy_type)
		return
	var muzzle := get_node_or_null("MuzzleFlash") as MeshInstance3D
	if muzzle:
		muzzle.visible = true
		get_tree().create_timer(0.1).timeout.connect(_hide_muzzle_flash)
	var shot_count: int = 1
	var spacing: float = 0.12
	if archetype == Archetype.BRUTE:
		shot_count = 3
		spacing = 0.16
	elif is_boss():
		shot_count = 7 if boss_phase == 2 else 5
		spacing = 0.14
		# Alternating elements make the second phase demand a different dodge rhythm.
		_attack_stats.gun_type = GunTypes.Type.FREEZING if boss_phase == 2 and _attack_number % 2 == 1 else gun_stats.gun_type
	for shot in range(shot_count):
		var angle: float = (shot - (shot_count - 1) * 0.5) * spacing
		var shot_direction: Vector3 = _aim_direction.rotated(global_basis.y, angle).normalized()
		var projectile := Projectile.create_from_stats(_attack_stats, _muzzle_position(), shot_direction, self, position_4d.w)
		get_tree().current_scene.add_child(projectile)
	_attack_number += 1

func _hide_muzzle_flash() -> void:
	var muzzle := get_node_or_null("MuzzleFlash") as MeshInstance3D
	if muzzle:
		muzzle.visible = false

func _on_4d_position_changed(new_pos: Vector4D) -> void:
	position_4d = new_pos
	global_position = new_pos.to_vector3()

func take_damage(amount: int, damage_type: GunTypes.Type) -> void:
	if _dead:
		return
	var effectiveness: float = GunTypes.get_effectiveness(damage_type, enemy_type)
	var final_damage: int = int(amount * effectiveness)

	current_health -= final_damage
	current_health = max(current_health, 0)

	damaged.emit(current_health, max_health)
	_update_health_bar()  # Update visual health bar
	if is_boss() and boss_phase == 1 and current_health > 0 and current_health <= max_health / 2:
		boss_phase = 2
		fire_rate *= 0.7
		move_speed *= 1.25
		if surface_walker:
			surface_walker.move_speed = move_speed
		boss_phase_changed.emit(boss_phase)

	# Wake up if hit while searching
	if current_state == State.SEARCHING and target:
		current_state = State.CHASING

	print("[Enemy4D] %d damage (%d%%), HP: %d/%d" % [
		final_damage, int(effectiveness * 100), current_health, max_health
	])

	if current_health <= 0:
		_die()

func _die() -> void:
	if _dead:
		return
	_dead = true
	collision_layer = 0
	print("[Enemy4D] Defeated %s; carried %s" % [display_name, gun_stats.get_display_name()])
	died.emit(self)
	var game_manager := get_node_or_null("/root/GameManager")
	if game_manager:
		game_manager.enemy_killed()
	queue_free()

## Freeze the enemy for the given duration (status effect)
func register_freezing_hit(random_roll: float = -1.0) -> bool:
	if _dead:
		return false
	if freezing_hit_window < -0.000001:
		freezing_hit_count = 0
	freezing_hit_count += 1
	freezing_hit_window = FREEZING_HIT_WINDOW
	var roll := randf() if random_roll < 0.0 else random_roll
	var triggered := freezing_hit_count >= 100 or roll < float(freezing_hit_count) * 0.01
	if triggered:
		freeze(2.0)
	return triggered

func _tick_freezing_hit_window(delta: float) -> void:
	if get_tree().paused:
		return
	if freezing_hit_count <= 0:
		return
	freezing_hit_window -= delta
	if freezing_hit_window < -0.000001:
		freezing_hit_count = 0
		freezing_hit_window = 0.0

func freeze(duration: float) -> void:
	frozen_timer = maxf(frozen_timer, duration * (0.35 if is_boss() else 1.0))
	if _ice_shell:
		_ice_shell.visible = frozen_timer > 0.0
	print("[Enemy4D] FROZEN for %.1f seconds!" % duration)

func stun(duration: float) -> void:
	stunned_timer = maxf(stunned_timer, duration * (0.35 if is_boss() else 1.0))
	var stars := get_node_or_null("StunStars")
	if stars == null:
		stars = Node3D.new()
		stars.name = "StunStars"
		stars.position.y = _body_height + 0.25
		add_child(stars)
		for i in range(3):
			var mesh := MeshInstance3D.new()
			var shape := CylinderMesh.new()
			shape.top_radius = 0.0
			shape.bottom_radius = 0.10
			shape.height = 0.18
			shape.radial_segments = 5
			mesh.mesh = shape
			mesh.position = Vector3(cos(i * TAU / 3.0) * 0.35, 0, sin(i * TAU / 3.0) * 0.35)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color("ffdf55")
			mat.emission_enabled = true
			mat.emission = mat.albedo_color
			mesh.material_override = mat
			stars.add_child(mesh)
	stars.visible = true

## Apply an external force (implosion/knockback)
func apply_external_force(force: Vector3) -> void:
	external_velocity += force * (0.25 if is_boss() else 1.0)
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
