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
	5: Color(0.2, 0.4, 1.0)    # Special - Blue
}

## Players currently in transition zone
var _players_in_zone: Array = []

## Store original W of target room (for restoration when player exits)
var _target_original_w: float = 0.0
var _is_w_synced: bool = false

## Spawn protection - don't trigger portals immediately after creation
var _spawn_protection_timer: float = 1.0  # Seconds to wait before allowing transitions
var _is_ready_for_transitions: bool = false

## Portal cooldown - don't re-trigger immediately after traversal
## Dictionary mapping player node -> cooldown timer remaining
var _player_cooldowns: Dictionary = {}
const PORTAL_COOLDOWN: float = 2.0  # Seconds before player can use ANY portal again

## Track entry SIDE relative to portal surface (fixes oscillation bug)
## Dictionary mapping player node -> entry side (true = in front of portal surface, false = behind)
var _player_entry_side: Dictionary = {}

signal player_transitioned(from_w: float, to_w: float)

func _ready() -> void:
	add_to_group("portal_doors")
	_create_portal_frame()
	_create_portal_surface()
	_create_transition_area()
	_create_label()
	_create_viewport()  # Enable see-through rendering

func _process(delta: float) -> void:
	# Spawn protection countdown
	if not _is_ready_for_transitions:
		_spawn_protection_timer -= delta
		if _spawn_protection_timer <= 0.0:
			_is_ready_for_transitions = true
	
	# Update player cooldowns
	var players_to_remove: Array = []
	for player in _player_cooldowns:
		_player_cooldowns[player] -= delta
		if _player_cooldowns[player] <= 0.0:
			players_to_remove.append(player)
	for player in players_to_remove:
		_player_cooldowns.erase(player)
	
	# Update portal camera to track target room
	_update_portal_camera()
	
	# Handle W-transition for players in zone
	_update_w_transitions(delta)
	
	# Animate portal surface - pulsing glow effect (only if not using viewport texture)
	if not viewport or not viewport.get_texture():
		if portal_surface and portal_surface.material_override:
			var mat = portal_surface.material_override as StandardMaterial3D
			if mat and mat.albedo_texture == null:
				var pulse := 1.5 + sin(Time.get_ticks_msec() * 0.003) * 0.5
				mat.emission_energy_multiplier = pulse

## Update W coordinate for players transitioning through portal
## DISABLED: We now teleport properly on exit instead of interpolating W
func _update_w_transitions(_delta: float) -> void:
	# W stays at source until player fully passes through the portal
	# The teleport happens in _on_transition_body_exited
	pass

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
	
	# Set collision layer/mask to detect player (layer 1 is default for CharacterBody3D)
	transition_area.collision_layer = 0  # Don't participate as collidable
	transition_area.collision_mask = 1   # Detect layer 1 (player)
	
	# Transition zone - box extending INTO the sphere (where player walks)
	var col_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Wider and deeper to catch players approaching from inside the hollow sphere
	box.size = Vector3(portal_radius * 2.5, portal_radius * 2.5, 4.0)
	col_shape.shape = box
	
	# CRITICAL: Offset the collision box TOWARD the center of the sphere
	# After look_at + rotate_object_local(Y, PI), local +Z points toward center
	# This makes the box extend into the room where the player actually walks
	col_shape.position = Vector3(0, 0, 2.0)  # Shift 2 units into the room
	
	transition_area.add_child(col_shape)
	add_child(transition_area)
	
	# Connect transition triggers
	transition_area.body_entered.connect(_on_transition_body_entered)
	transition_area.body_exited.connect(_on_transition_body_exited)

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
	
	# Spawn protection - don't trigger during first second after level load
	if not _is_ready_for_transitions:
		return
	
	# Check if player has cooldown on ANY portal (prevents bouncing)
	var all_portals = get_tree().get_nodes_in_group("portal_doors")
	for portal in all_portals:
		if portal.get("_player_cooldowns") != null:
			if body in portal._player_cooldowns:
				# Player is on cooldown, don't trigger
				return
	
	if body not in _players_in_zone:
		_players_in_zone.append(body)
		
		# NOTE: W-sync is now handled centrally by LevelGenerator (host room + adjacent rooms)
		# The portal no longer needs to sync destination room W on proximity
		
		# Record entry SIDE for crossing detection
		# Portal local Z after positioning: +Z points toward sphere center (inside room)
		# -Z points toward destination (outside room / through portal)
		var rel_pos: Vector3 = body.global_position - global_position
		var local_z_pos: float = rel_pos.dot(global_transform.basis.z)  # Positive = front/inside, Negative = behind/outside
		_player_entry_side[body] = local_z_pos > 0.0  # true = entered from inside room (front)
		
		print("[PortalDoor] Player entered portal zone: %s (entry_side=%s, local_z=%.2f)" % [name, "INSIDE" if local_z_pos > 0 else "OUTSIDE", local_z_pos])

func _on_transition_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	
	if body in _players_in_zone:
		_players_in_zone.erase(body)
		
		# Get entry SIDE (which side of portal surface player entered from)
		var entered_from_inside: bool = _player_entry_side.get(body, true)
		_player_entry_side.erase(body)
		
		# Get exit SIDE (which side player is on now)
		var rel_pos: Vector3 = body.global_position - global_position
		var local_z_pos: float = rel_pos.dot(global_transform.basis.z)  # Positive = front/inside, Negative = behind/outside
		var exited_to_inside: bool = local_z_pos > 0.0
		
		# Player CROSSED THROUGH if entry side != exit side
		# e.g., entered from inside room (front) but exited toward destination (behind)
		var passed_through: bool = entered_from_inside != exited_to_inside
		
		print("[PortalDoor] Player exited zone: %s (entry=%s, exit=%s, local_z=%.2f, crossed=%s)" % [
			name, 
			"INSIDE" if entered_from_inside else "OUTSIDE",
			"INSIDE" if exited_to_inside else "OUTSIDE",
			local_z_pos,
			passed_through
		])
		
		if passed_through and target_portal and is_instance_valid(target_portal):
			# Player walked INTO destination room!
			var dest_room = target_portal.source_room
			print("[PortalDoor] Player walked through portal to %s" % (dest_room.name if dest_room else "unknown"))
			
			if dest_room and dest_room.get("position_4d") != null:
				# 1. Update lighting immediately (fix dark room delay)
				if dest_room.has_method("set_light_enabled"):
					dest_room.set_light_enabled(true)
				
				# NOTE: W-sync is now handled by LevelGenerator when player changes rooms
				# The portal only needs to shift the player's W coordinate
				
				# 2. Shift PLAYER to the destination room's original W coordinate
				# Get original W from LevelGenerator's stored values
				var dest_original_w: float = 0.0
				var level_gen = get_tree().get_first_node_in_group("level_generator")
				if level_gen and level_gen.get("_original_room_w") != null:
					var dest_room_id: int = dest_room.room_id if dest_room.get("room_id") != null else -1
					if level_gen._original_room_w.has(dest_room_id):
						dest_original_w = level_gen._original_room_w[dest_room_id]
						print("[PortalDoor] Got original W=%.1f for room %d from LevelGenerator" % [dest_original_w, dest_room_id])
				
				if body.get("position_4d") != null:
					body.position_4d.w = dest_original_w
					print("[PortalDoor] Shifted Player W to %.1f" % dest_original_w)

				# Force slicer update to new W
				var slicer = get_tree().get_first_node_in_group("slicer_4d")
				if slicer:
					slicer.slice_w = dest_original_w
					if slicer.has_method("update_all_objects"):
						slicer.update_all_objects()
				
				# 3. VELOCITY BOOST: Propel player toward destination room's center
				var dest_center: Vector3 = dest_room.global_position
				var player_pos: Vector3 = body.global_position
				var dir_to_dest: Vector3 = (dest_center - player_pos).normalized()
				
				if body.get("velocity") != null:
					body.velocity = dir_to_dest * 25.0
					print("[PortalDoor] Applied velocity boost toward %s" % dest_room.name)
				
				# 4. SET COOLDOWN: Prevent immediate re-triggering on BOTH portals
				_player_cooldowns[body] = PORTAL_COOLDOWN
				if target_portal:
					target_portal._player_cooldowns[body] = PORTAL_COOLDOWN
				print("[PortalDoor] Portal cooldown started on both portals for %.1f seconds" % PORTAL_COOLDOWN)
		else:
			# Player backed out - no W-restore needed (LevelGenerator handles visibility)
			print("[PortalDoor] Player backed out of portal: %s" % name)
		
		player_transitioned.emit(source_w, target_w)

## Set the door color based on target room type
func set_color_from_room_type(room_type: int) -> void:
	door_color = ROOM_COLORS.get(room_type, Color(0.4, 0.8, 1.0))
	if portal_frame and portal_frame.material_override is StandardMaterial3D:
		var mat := portal_frame.material_override as StandardMaterial3D
		mat.albedo_color = door_color
		mat.emission = door_color
	
	# Update label
	var type_names := {0: "", 1: "BOSS", 2: "ITEM", 3: "SHOP", 4: "GAMBLE", 5: "SPECIAL"}
	label.text = type_names.get(room_type, "")

## Position this door on a room sphere's interior surface, facing TOWARD target
func position_on_sphere(room: Node, direction: Vector3) -> void:
	source_room = room
	portal_direction = direction.normalized()
	
	var sphere_center: Vector3 = room.global_position
	var sphere_radius: float = room.radius if room.get("radius") else 20.0
	
	# Position on interior surface
	global_position = sphere_center + portal_direction * (sphere_radius - 0.5)
	
	# Face INWARD (toward center) so player can walk into the portal
	# The portal surface should face the player inside the sphere
	look_at(sphere_center)
	# Rotate 180 so the teleport trigger is on the front side
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
