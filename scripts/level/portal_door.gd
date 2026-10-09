# PortalDoor - 4D W-axis portal that transitions player between W coordinates
# Shows destination W-slice through portal surface, smoothly transitions W on pass-through
class_name PortalDoor
extends Node3D

## The room this portal belongs to
var source_room: Node = null

## The room this portal connects to
var target_room: Node = null

## The matching portal door on the other side
var target_portal: PortalDoor = null

## W coordinates for transition
var source_w: float = 0.0  # W of the room this portal is in
var target_w: float = 0.0  # W of the room this portal leads to

## Interaction range
@export var interact_distance: float = 5.0

## Visual components
var portal_frame: MeshInstance3D  # The ring/frame
var portal_surface: MeshInstance3D  # The see-through surface
var transition_area: Area3D  # Trigger for W-transition
var door_color: Color = Color(0.4, 0.8, 1.0, 1.0)

## SubViewport for rendering destination view
var viewport: SubViewport
var portal_camera: Camera3D

## Label showing room destination
var label: Label3D

## Direction this portal faces (toward target room)
var portal_direction: Vector3 = Vector3.FORWARD

## Portal size
var portal_radius: float = 2.0

## Room type colors
const ROOM_COLORS := {
	0: Color(0.2, 0.8, 1.0),   # Normal - Cyan
	1: Color(1.0, 0.2, 0.2),   # Boss - Red
	2: Color(1.0, 0.85, 0.2),  # Item - Gold
	3: Color(1.0, 0.6, 0.2),   # Shop - Orange
	4: Color(0.6, 0.2, 1.0),   # Gambling - Purple
	5: Color(0.2, 0.4, 1.0),   # Special - Blue
	6: Color(0.85, 0.45, 1.0)  # Secret - Violet
}

## Players currently in transition zone
var _players_in_zone: Array = []

## Store original W of target room (for restoration when player exits)
var _target_original_w: float = 0.0
var _is_w_synced: bool = false

## Spawn protection - don't trigger portals immediately after creation
var _spawn_protection_timer: float = 1.0  # Seconds to wait before allowing transitions
var _is_ready_for_transitions: bool = false

## Track entry SIDE relative to portal surface (fixes oscillation bug)
## Dictionary mapping player node -> entry side (true = in front of portal surface, false = behind)
var _player_entry_side: Dictionary = {}
var _previous_player_positions: Dictionary = {}
var _assisting_players: Dictionary = {}
var _projectile_positions: Dictionary = {}
var available: bool = true
var combat_locked: bool = false
var _combat_lock_owners: Dictionary = {}
var key_locked: bool = false
var _key_lock_owners: Dictionary = {}
var _key_interaction: Node3D
var _key_icon: Node3D
var _destination_label: String = ""
var _entrant_grace: Dictionary = {}
var _combat_seal: StaticBody3D
var _combat_seal_shape: CollisionShape3D
var _seal_enabled: bool = false
const ENTRANT_CLEARANCE: float = 2.25

signal player_transitioned(from_w: float, to_w: float)

func _ready() -> void:
	add_to_group("portal_doors")
	_create_portal_frame()
	_create_portal_surface()
	_create_transition_area()
	_create_label()
	_create_combat_seal()
	_refresh_lock_state()
	# Rooms are rendered directly through the opening; no extra camera is needed.

func _physics_process(delta: float) -> void:
	_update_entrant_grace()
	_refresh_lock_state()
	if not available:
		return
	# Spawn protection countdown
	if not _is_ready_for_transitions:
		_spawn_protection_timer -= delta
		if _spawn_protection_timer <= 0.0:
			_is_ready_for_transitions = true
			for body in transition_area.get_overlapping_bodies():
				_on_transition_body_entered(body)
	
	# Only track crossings here. The player owns its one physics movement step.
	_update_w_transitions(delta)
	_update_projectile_transitions()

func _process(_delta: float) -> void:
	# Animate portal surface - pulsing glow effect (only if not using viewport texture)
	if not viewport or not viewport.get_texture():
		if portal_surface and portal_surface.material_override:
			var mat = portal_surface.material_override as StandardMaterial3D
			if mat and mat.albedo_texture == null:
				var pulse := 1.5 + sin(Time.get_ticks_msec() * 0.003) * 0.5
				mat.emission_energy_multiplier = pulse * 0.04 if key_locked else pulse

## Change W only when the body actually crosses the circular opening.
func _update_w_transitions(_delta: float) -> void:
	for body in _players_in_zone.duplicate():
		if not is_instance_valid(body):
			_forget_player(body)
			continue
		_check_player_crossing(body)

func _check_player_crossing(body: Node3D) -> void:
	var current := to_local(body.global_position)
	var previous: Vector3 = _previous_player_positions.get(body, current)
	_previous_player_positions[body] = current
	# A receiver can be used again as soon as the player turns around inside it.
	if current.z > 0.1:
		_player_entry_side[body] = true
	if not available or combat_locked or key_locked or not is_visible_in_tree() or not _player_entry_side.get(body, false):
		return
	if previous.z <= 0.0 or current.z > 0.0:
		return
	var fraction := previous.z / (previous.z - current.z)
	var crossing := previous.lerp(current, fraction)
	if Vector2(crossing.x, crossing.y).length() > portal_radius:
		return
	if is_instance_valid(target_portal):
		_player_entry_side[body] = false
		_perform_portal_transition(body, target_portal.source_room)

func _forget_player(body) -> void:
	_players_in_zone.erase(body)
	_player_entry_side.erase(body)
	_previous_player_positions.erase(body)
	_assisting_players.erase(body)

## Exact cylindrical opening, shared with room boundary and projectile checks.
func contains_aperture(world_position: Vector3, depth: float = 4.0) -> bool:
	return not combat_locked and not key_locked and _contains_opening(world_position, depth)

## A newly entered room may seal behind this one capsule as it clears the door.
## Projectile queries never receive this exception.
func contains_player_aperture(world_position: Vector3, body: Node3D, depth: float = 4.0) -> bool:
	return not key_locked and (not combat_locked or _entrant_grace.has(body)) and _contains_opening(world_position, depth)

func _contains_opening(world_position: Vector3, depth: float = 4.0) -> bool:
	if not available or not is_visible_in_tree():
		return false
	var local := to_local(world_position)
	return absf(local.z) <= depth and Vector2(local.x, local.y).length() < portal_radius

## Preserve the walk-through guidance without a center-seeking force that reverses
## after crossing. Called by the player, once per physics tick, before it moves.
func get_traversal_assist(body: CharacterBody3D, delta: float, speed: float, movement: Vector3) -> Vector3:
	if key_locked:
		_assisting_players.erase(body)
		return Vector3.ZERO
	if combat_locked:
		if _entrant_grace.has(body):
			var inward: Vector3 = _entrant_grace[body]
			# Finish this crossing at walking speed, including against attempted
			# retreat. No position is reassigned and no reverse W crossing is armed.
			var inward_speed := body.velocity.dot(inward)
			return inward * maxf(0.0, speed * 1.25 - inward_speed)
		return Vector3.ZERO
	if not _is_ready_for_transitions or not is_instance_valid(target_portal) or not contains_aperture(body.global_position):
		_assisting_players.erase(body)
		return Vector3.ZERO
	var local := to_local(body.global_position)
	var outward := -global_transform.basis.z.normalized()
	if not _assisting_players.has(body):
		# Only the approached side assists. The receiving door must never pull back.
		if local.z <= 0.0 or body.velocity.dot(outward) < -0.1:
			return Vector3.ZERO
		var toward_opening := global_position - body.global_position
		if movement.dot(toward_opening) <= 0.1:
			return Vector3.ZERO
		_assisting_players[body] = movement.normalized()
	var entry_movement: Vector3 = _assisting_players[body]
	# Backing away cancels guidance while the player is still inside the source.
	if local.z > 0.0 and movement.dot(entry_movement) < -0.1:
		_assisting_players.erase(body)
		return Vector3.ZERO
	var forward_speed := body.velocity.dot(outward)
	var desired_speed := maxf(speed * 1.25, forward_speed)
	return outward * (move_toward(forward_speed, desired_speed, 72.0 * delta) - forward_speed)

func set_available(enabled: bool) -> void:
	available = enabled
	visible = enabled
	if transition_area:
		transition_area.set_deferred("monitoring", enabled)
	if not enabled:
		_players_in_zone.clear()
		_player_entry_side.clear()
		_previous_player_positions.clear()
		_assisting_players.clear()
		_projectile_positions.clear()
	_refresh_lock_state()

## A doorway is sealed while either connected room owns a combat lock.
func set_combat_lock(owner_room: Node, enabled: bool, entering_player: Node3D = null) -> void:
	_apply_combat_lock(owner_room, enabled, entering_player)
	if is_instance_valid(target_portal):
		target_portal._apply_combat_lock(owner_room, enabled, entering_player)

func _apply_combat_lock(owner_room: Node, enabled: bool, entering_player: Node3D) -> void:
	if not is_instance_valid(owner_room):
		return
	if enabled:
		_combat_lock_owners[owner_room.get_instance_id()] = true
	else:
		_combat_lock_owners.erase(owner_room.get_instance_id())
	var was_locked := combat_locked
	combat_locked = not _combat_lock_owners.is_empty()
	if combat_locked and not was_locked and is_instance_valid(entering_player):
		var room_door: PortalDoor = self if source_room == owner_room else target_portal
		if is_instance_valid(room_door) and room_door.source_room == owner_room:
			var local := room_door.to_local(entering_player.global_position)
			# Only the capsule currently straddling this doorway receives grace.
			if local.z >= -0.1 and local.z < ENTRANT_CLEARANCE and Vector2(local.x, local.y).length() < portal_radius:
				_entrant_grace[entering_player] = room_door.global_transform.basis.z.normalized()
				if _combat_seal:
					_combat_seal.add_collision_exception_with(entering_player)
	if not combat_locked:
		for body in _entrant_grace.keys():
			_remove_entrant_grace(body)
	_refresh_lock_state()

## Either endpoint may be a locked special room; room ownership is independent
## from combat and from secret-door discovery.
func set_key_lock(owner_room: Node, enabled: bool) -> void:
	_apply_key_lock(owner_room, enabled)
	if is_instance_valid(target_portal):
		target_portal._apply_key_lock(owner_room, enabled)

func _apply_key_lock(owner_room: Node, enabled: bool) -> void:
	if not is_instance_valid(owner_room):
		return
	if enabled:
		_key_lock_owners[owner_room.get_instance_id()] = owner_room
	else:
		_key_lock_owners.erase(owner_room.get_instance_id())
	key_locked = not _key_lock_owners.is_empty()
	if key_locked and _key_interaction == null and is_inside_tree():
		_create_key_interaction()
	_refresh_lock_state()

func get_key_locked_room() -> Node:
	# The destination is the room the approaching player intends to purchase.
	for candidate in [target_room, source_room]:
		if is_instance_valid(candidate) and _key_lock_owners.has(candidate.get_instance_id()):
			return candidate
	for candidate in _key_lock_owners.values():
		if is_instance_valid(candidate):
			return candidate
	return null

func _create_key_interaction() -> void:
	_key_interaction = load("res://scripts/level/key_room_lock.gd").new()
	_key_interaction.configure(self)
	add_child(_key_interaction)
	_key_icon = Node3D.new()
	_key_icon.name = "KeyLockIcon"
	_key_icon.position.z = 0.16
	add_child(_key_icon)
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color("e4bb4e")
	brass.metallic = 0.65
	brass.emission_enabled = true
	brass.emission = Color("a27a26")
	brass.emission_energy_multiplier = 0.02
	var body := MeshInstance3D.new()
	var block := BoxMesh.new()
	block.size = Vector3(0.65, 0.48, 0.12)
	body.mesh = block
	body.position.y = -0.10
	body.material_override = brass
	_key_icon.add_child(body)
	var shackle := MeshInstance3D.new()
	var hoop := TorusMesh.new()
	hoop.inner_radius = 0.16
	hoop.outer_radius = 0.22
	hoop.rings = 12
	hoop.ring_segments = 6
	shackle.mesh = hoop
	shackle.rotation.x = PI * 0.5
	shackle.position.y = 0.17
	shackle.material_override = brass
	_key_icon.add_child(shackle)
	var keyhole := MeshInstance3D.new()
	var slot := BoxMesh.new()
	slot.size = Vector3(0.06, 0.13, 0.02)
	keyhole.mesh = slot
	keyhole.position = Vector3(0, -0.10, 0.071)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("302611")
	keyhole.material_override = dark
	_key_icon.add_child(keyhole)

func _update_entrant_grace() -> void:
	for body in _entrant_grace.keys():
		if not is_instance_valid(body):
			_entrant_grace.erase(body)
			continue
		var inward: Vector3 = _entrant_grace[body]
		if (body.global_position - global_position).dot(inward) >= ENTRANT_CLEARANCE:
			_remove_entrant_grace(body)

func _remove_entrant_grace(body) -> void:
	if is_instance_valid(body) and _combat_seal:
		_combat_seal.remove_collision_exception_with(body)
	_entrant_grace.erase(body)

func _create_combat_seal() -> void:
	_combat_seal = StaticBody3D.new()
	_combat_seal.name = "CombatSeal"
	_combat_seal.collision_layer = 1
	_combat_seal.collision_mask = 1 | 2 | 4
	_combat_seal_shape = CollisionShape3D.new()
	var disc := CylinderShape3D.new()
	disc.radius = portal_radius
	disc.height = 0.06
	_combat_seal_shape.shape = disc
	_combat_seal_shape.rotation.x = PI * 0.5
	_combat_seal_shape.disabled = true
	_combat_seal.add_child(_combat_seal_shape)
	add_child(_combat_seal)

func _refresh_lock_state() -> void:
	# A completely empty opening has no translucent tint or emissive surface.
	if portal_surface:
		portal_surface.visible = available and (combat_locked or key_locked)
		var surface_mat := portal_surface.material_override as StandardMaterial3D
		if surface_mat:
			surface_mat.albedo_color = Color(0.34, 0.25, 0.08, 0.22) if key_locked else Color(door_color.r, door_color.g, door_color.b, 0.1)
			surface_mat.emission = Color("e5ba48") if key_locked else door_color
			surface_mat.emission_energy_multiplier = 0.1 if key_locked else 1.0
	if _key_icon:
		_key_icon.visible = available and key_locked
	if _key_interaction:
		_key_interaction.visible = available and key_locked
	if label:
		label.text = _destination_label + ("\nLOCKED · 1 KEY" if key_locked else "")
	var enabled := available and (combat_locked or key_locked) and is_visible_in_tree()
	if _combat_seal_shape and enabled != _seal_enabled:
		_seal_enabled = enabled
		_combat_seal_shape.set_deferred("disabled", not enabled)

func _create_portal_frame() -> void:
	portal_frame = MeshInstance3D.new()
	
	# Torus ring for the portal frame - thin ring for seamless edge
	var torus := TorusMesh.new()
	torus.inner_radius = portal_radius
	torus.outer_radius = portal_radius + 0.15  # Thinner frame for cleaner edge
	torus.rings = 24
	torus.ring_segments = 12
	portal_frame.mesh = torus
	
	# Rotate so torus hole faces forward (Z-axis) instead of up (Y-axis)
	portal_frame.rotation_degrees.x = 90
	
	# Subtle glowing frame material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = door_color
	mat.emission_enabled = true
	mat.emission = door_color
	mat.emission_energy_multiplier = 1.5  # Reduced from 3.0 for subtler glow
	portal_frame.material_override = mat
	portal_frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	add_child(portal_frame)

func _create_portal_surface() -> void:
	portal_surface = MeshInstance3D.new()
	
	# Use a circular disc mesh for the portal surface - matches frame inner radius exactly
	var disc := CylinderMesh.new()
	disc.top_radius = portal_radius  # Match frame inner radius for seamless edge
	disc.bottom_radius = portal_radius
	disc.height = 0.02  # Very thin disc
	portal_surface.mesh = disc
	
	# Rotate to face forward
	portal_surface.rotation_degrees.x = 90
	
	# Almost fully transparent so you can see through to the destination room
	# The destination room is made visible via force_visible flag
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(door_color.r, door_color.g, door_color.b, 0.1)  # Mostly transparent
	mat.emission_enabled = true
	mat.emission = door_color
	mat.emission_energy_multiplier = 0.5  # Subtle glow
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	portal_surface.material_override = mat
	portal_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	add_child(portal_surface)

func _create_transition_area() -> void:
	transition_area = Area3D.new()
	transition_area.name = "TransitionArea"
	
	# Enable monitoring for body detection
	transition_area.monitoring = true
	transition_area.monitorable = false
	
	# Set collision layer/mask to detect player and projectiles
	transition_area.collision_layer = 0  # Don't participate as collidable
	transition_area.collision_mask = 1 | 2  # Detect layer 1 (player) and layer 2 (projectiles)
	
	# Transition zone - box extending INTO the sphere (where player walks)
	var col_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Wider and deeper to catch players approaching from inside the hollow sphere
	box.size = Vector3(portal_radius * 2.5, portal_radius * 2.5, 9.0)
	col_shape.shape = box
	
	# Local +Z points inside the source; include both sides so the physics
	# tracker observes the plane crossing before the body leaves the area.
	col_shape.position = Vector3(0, 0, -0.5)  # Approach +4 to receiving side -5
	
	transition_area.add_child(col_shape)
	add_child(transition_area)
	
	# Connect transition triggers
	transition_area.body_entered.connect(_on_transition_body_entered)
	transition_area.body_exited.connect(_on_transition_body_exited)
	transition_area.area_entered.connect(_on_transition_area_entered)
	transition_area.area_exited.connect(_on_transition_area_exited)

func _create_label() -> void:
	label = Label3D.new()
	label.text = ""
	label.font_size = 32
	label.position = Vector3(0, portal_radius + 0.5, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

func _create_viewport() -> void:
	# Create SubViewport for rendering destination view
	viewport = SubViewport.new()
	viewport.size = Vector2i(512, 512)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	viewport.handle_input_locally = false
	
	# Create camera for viewport (world assignment deferred to activate_see_through)
	portal_camera = Camera3D.new()
	portal_camera.fov = 75
	portal_camera.current = false  # Don't make this the main camera
	viewport.add_child(portal_camera)
	
	add_child(viewport)

func _update_portal_camera() -> void:
	# W-sync approach: target room's W is already synced when player is in zone
	# No force_visible needed - room is naturally visible at same W
	pass

func _on_transition_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	if not available or not _is_ready_for_transitions:
		return
	# Entry only arms a crossing; walking away leaves W and momentum unchanged.
	if body not in _players_in_zone:
		_players_in_zone.append(body)
		var local := to_local(body.global_position)
		_player_entry_side[body] = local.z > 0.0
		_previous_player_positions[body] = local

func _on_transition_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	if is_instance_valid(body) and _previous_player_positions.has(body):
		_check_player_crossing(body)
	_forget_player(body)

## Handle projectiles entering the transition area
func _on_transition_area_entered(area: Area3D) -> void:
	# Only handle projectiles
	if not area.is_in_group("projectiles"):
		return
	
	# Spawn protection - don't trigger during first second after level load
	if not available or not _is_ready_for_transitions:
		return
	
	# Skip if no valid target portal
	if not target_portal or not is_instance_valid(target_portal):
		return
	
	_projectile_positions[area] = to_local(area.global_position)

func _on_transition_area_exited(area: Area3D) -> void:
	if is_instance_valid(area) and _projectile_positions.has(area):
		_check_projectile_crossing(area)
	_projectile_positions.erase(area)

func _update_projectile_transitions() -> void:
	for area in _projectile_positions.keys():
		if not is_instance_valid(area):
			_projectile_positions.erase(area)
			continue
		_check_projectile_crossing(area)

func _check_projectile_crossing(area: Area3D) -> void:
	var previous: Vector3 = _projectile_positions[area]
	var current := to_local(area.global_position)
	_projectile_positions[area] = current
	if not available or combat_locked or key_locked or previous.z <= 0.0 or current.z > 0.0:
		return
	var crossing := previous.lerp(current, previous.z / (previous.z - current.z))
	if Vector2(crossing.x, crossing.y).length() <= portal_radius and area.get("position_4d") != null:
		# Adjacent rooms already share the visible slice; don't hide the bullet.
		if area.has_method("notify_portal_crossing"):
			area.notify_portal_crossing(self)
			return
		if is_instance_valid(target_portal) and is_instance_valid(target_portal.source_room):
			area.position_4d.w = target_portal.source_room.position_4d.w

## Commit the destination slice without changing XYZ position or velocity.
func _perform_portal_transition(body: Node3D, dest_room: Node) -> void:
	if not dest_room or dest_room.get("position_4d") == null:
		return
	
	# 1. Update lighting immediately (fix dark room delay)
	if dest_room.has_method("set_light_enabled"):
		dest_room.set_light_enabled(true)
	
	# 2. Shift PLAYER to the destination room's original W coordinate
	var dest_original_w: float = target_w
	var level_gen = get_tree().get_first_node_in_group("level_generator")
	var dest_room_id: int = dest_room.room_id if dest_room.get("room_id") != null else -1
	if level_gen and level_gen.get("_original_room_w") != null:
		if level_gen._original_room_w.has(dest_room_id):
			dest_original_w = level_gen._original_room_w[dest_room_id]
	
	if body.get("position_4d") != null:
		body.position_4d.w = dest_original_w

	# Force slicer update to new W
	var slicer = get_tree().get_first_node_in_group("slicer_4d")
	if slicer:
		slicer.slice_w = dest_original_w
		if slicer.get("target_w") != null:
			slicer.target_w = dest_original_w
	
	# CRITICAL: Immediately sync room W coordinates so player doesn't end up in space
	if level_gen and dest_room_id >= 0:
		if level_gen.has_method("set_active_room"):
			level_gen.set_active_room(dest_room_id)
		elif level_gen.has_method("_update_room_w_sync"):
			level_gen._update_room_w_sync(dest_room_id)
			level_gen.current_lit_room_id = dest_room_id
	if slicer and slicer.has_method("update_all_objects"):
		slicer.update_all_objects()
	
	player_transitioned.emit(source_w, dest_original_w)

## Set the door color based on target room type
func set_color_from_room_type(room_type: int) -> void:
	door_color = ROOM_COLORS.get(room_type, Color(0.4, 0.8, 1.0))
	if portal_frame and portal_frame.material_override is StandardMaterial3D:
		var mat := portal_frame.material_override as StandardMaterial3D
		mat.albedo_color = door_color
		mat.emission = door_color
	
	# Update label
	var type_names := {0: "", 1: "BOSS", 2: "ITEM", 3: "SHOP", 4: "GAMBLE", 5: "SPECIAL", 6: "SECRET"}
	_destination_label = type_names.get(room_type, "")
	_refresh_lock_state()

## Position this door on a room sphere's interior surface, facing TOWARD target
func position_on_sphere(room: Node, direction: Vector3) -> void:
	source_room = room
	portal_direction = direction.normalized()
	
	var sphere_center: Vector3 = room.global_position
	var sphere_radius: float = room.radius if room.get("radius") else 20.0
	
	# Position on interior surface
	global_position = sphere_center + portal_direction * sphere_radius
	
	# Face INWARD (toward center) so player can walk into the portal
	# The portal surface should face the player inside the sphere
	var reference_up := Vector3.FORWARD if absf(portal_direction.dot(Vector3.UP)) > 0.99 else Vector3.UP
	look_at(sphere_center, reference_up)
	# Keep local +Z on the source room's inside, -Z toward the destination.
	rotate_object_local(Vector3.UP, PI)

## Apply viewport texture to portal surface (DISABLED - using force_visible approach instead)
func activate_see_through() -> void:
	# With the force_visible approach, destination rooms are rendered directly
	# and the portal surface is transparent - no viewport texture needed
	print("[PortalDoor] Activated see-through for %s (using transparent surface)" % name)

## Link this portal to a target portal and enable see-through on both
func link_to_portal(target: PortalDoor) -> void:
	target_portal = target
	target.target_portal = self
	# Locks set when each source room added its door must reach the paired side.
	for owner in _key_lock_owners.values().duplicate():
		target._apply_key_lock(owner, true)
	for owner in target._key_lock_owners.values().duplicate():
		_apply_key_lock(owner, true)
	
	# Set W coordinates for W-transition
	if source_room and source_room.get("position_4d") != null:
		source_w = source_room.position_4d.w
	if target.source_room and target.source_room.get("position_4d") != null:
		target_w = target.source_room.position_4d.w
	
	# Set reverse W coordinates for target portal
	target.source_w = target_w
	target.target_w = source_w
	
	print("[PortalDoor] W-transition: %s (W=%.1f) <-> %s (W=%.1f)" % [name, source_w, target.name, target_w])
	
	# Set colors based on connected rooms
	if target.source_room and target.source_room.get("room_type") != null:
		set_color_from_room_type(target.source_room.room_type)
	if source_room and source_room.get("room_type") != null:
		target.set_color_from_room_type(source_room.room_type)
	
	# Activate see-through rendering on both portals (deferred to ensure scene is ready)
	call_deferred("activate_see_through")
	target.call_deferred("activate_see_through")
	
	print("[PortalDoor] Linked %s <-> %s" % [name, target.name])
