# LevelGenerator - Procedural level generator for connected sphere rooms
# Generates a BRANCHING graph of rooms with portals connecting them (maze-like)
class_name LevelGenerator
extends Node

## Base radius for rooms
@export var base_room_radius: float = 20.0

## W-axis spacing between rooms (each room at different W)
const W_SPACING: float = 30.0

## Number of normal rooms to generate
@export var num_normal_rooms: int = 5

## Random seed (0 = random)
@export var seed_value: int = 0

## Auto-generate level on scene load
@export var auto_generate: bool = false

## Generated rooms
var rooms: Array = []

## Room graph (adjacency list)
var room_graph: Dictionary = {}  # room_id -> { connections: [], type: int, position: Vector3 }

## Reference to player for spawning
var player: Node = null

## Current level depth/difficulty
var level_depth: int = 1

## Room type constants (to avoid class_name issues)
const ROOM_NORMAL := 0
const ROOM_BOSS := 1
const ROOM_ITEM := 2
const ROOM_SHOP := 3
const ROOM_GAMBLING := 4
const ROOM_SPECIAL := 5

## Room colors
const ROOM_COLORS := {
	0: Color(0.2, 0.8, 1.0),   # Normal - Cyan
	1: Color(1.0, 0.2, 0.2),   # Boss - Red
	2: Color(1.0, 0.85, 0.2),  # Item - Gold
	3: Color(1.0, 0.6, 0.2),   # Shop - Orange
	4: Color(0.6, 0.2, 1.0),   # Gambling - Purple
	5: Color(0.2, 0.4, 1.0)    # Special - Blue
}

## Room size multipliers
const ROOM_SIZES := {
	0: 1.0,   # Normal
	1: 2.0,   # Boss (2x size)
	2: 1.0,   # Item
	3: 1.0,   # Shop
	4: 1.0,   # Gambling
	5: 1.0    # Special
}

signal level_generated(rooms: Array)
signal player_spawned(spawn_room: Node)

## Currently lit room ID (-1 = none)
var current_lit_room_id: int = -1

## Original W values for each room (for restoration when not adjacent to host)
var _original_room_w: Dictionary = {}  # room_id -> original W value

func _ready() -> void:
	add_to_group("level_generator")
	
	# Auto-generate level if enabled
	if auto_generate:
		call_deferred("_auto_generate_level")

## Called when auto_generate is enabled - generates level and spawns player
func _auto_generate_level() -> void:
	print("[LevelGenerator] Auto-generating level...")
	generate_level(seed_value)
	await get_tree().process_frame
	spawn_player_in_start_room()
	print("[LevelGenerator] Auto-generation complete!")

func _process(_delta: float) -> void:
	# Track player and update room lighting based on proximity
	if rooms.is_empty():
		return
	
	var p = get_tree().get_first_node_in_group("player")
	if not p:
		return
	
	# Find which room the player is in
	var player_room_id: int = _get_player_room_id(p.global_position)
	
	# Only update lights if player changed rooms
	if player_room_id != current_lit_room_id:
		_update_room_lights(player_room_id)
		_update_room_w_sync(player_room_id)  # Sync W for host + adjacent rooms
		current_lit_room_id = player_room_id

## Get the room ID the player is currently in
func _get_player_room_id(player_pos: Vector3) -> int:
	for i in range(rooms.size()):
		var room = rooms[i]
		if not is_instance_valid(room):
			continue
		var room_center: Vector3 = room.global_position
		var room_radius: float = room.radius if room.get("radius") else 20.0
		var dist: float = player_pos.distance_to(room_center)
		if dist < room_radius + 5.0:  # Inside with margin
			return i
	return -1

## Update room lights: enable current room and adjacent rooms, disable others
func _update_room_lights(player_room_id: int) -> void:
	if player_room_id < 0:
		return
	
	# Get adjacent room IDs from graph
	var adjacent_ids: Array = []
	if room_graph.has(player_room_id):
		adjacent_ids = room_graph[player_room_id]["connections"]
	
	# Update all room lights
	for i in range(rooms.size()):
		var room = rooms[i]
		if not is_instance_valid(room):
			continue
		
		# Enable if this is current room or adjacent
		var should_enable: bool = (i == player_room_id) or (i in adjacent_ids)
		if room.has_method("set_light_enabled"):
			room.set_light_enabled(should_enable)

## Update room W coordinates: sync host room + adjacent rooms to player's W
## This makes portals see-through regardless of distance (graph-based visibility)
func _update_room_w_sync(player_room_id: int) -> void:
	if player_room_id < 0:
		return
	
	# Get current slicer W (player's current slice)
	var slicer = get_tree().get_first_node_in_group("slicer_4d")
	var current_w: float = 0.0
	if slicer and slicer.get("slice_w") != null:
		current_w = slicer.slice_w
	
	# Get adjacent room IDs from graph
	var adjacent_ids: Array = []
	if room_graph.has(player_room_id):
		adjacent_ids = room_graph[player_room_id]["connections"]
	
	# Rooms that should be synced to current W (host + adjacent)
	var synced_ids: Array = [player_room_id] + adjacent_ids
	
	print("[LevelGen] W-SYNC: Host room %d, syncing %d rooms to W=%.1f" % [player_room_id, synced_ids.size(), current_w])
	
	# Update all room W coordinates
	for i in range(rooms.size()):
		var room = rooms[i]
		if not is_instance_valid(room):
			continue
		
		if i in synced_ids:
			# Sync to player's current W (make visible)
			if room.get("position_4d") != null:
				var old_w: float = room.position_4d.w
				room.position_4d = Vector4(room.position_4d.x, room.position_4d.y, room.position_4d.z, current_w)
				if room.get("_position_4d") != null:
					room._position_4d.w = current_w
				if room.has_method("update_slice"):
					room.update_slice(current_w)
				if old_w != current_w:
					print("[LevelGen] Room %d synced W: %.1f -> %.1f" % [i, old_w, current_w])
		else:
			# Restore to original W (make invisible through portals)
			if _original_room_w.has(i) and room.get("position_4d") != null:
				var original_w: float = _original_room_w[i]
				var current_room_w: float = room.position_4d.w
				if current_room_w != original_w:
					room.position_4d = Vector4(room.position_4d.x, room.position_4d.y, room.position_4d.z, original_w)
					if room.get("_position_4d") != null:
						room._position_4d.w = original_w
					if room.has_method("update_slice"):
						room.update_slice(current_w)  # Use current slice W for visibility calc
	
	# Update slicer to refresh all objects
	if slicer and slicer.has_method("update_all_objects"):
		slicer.update_all_objects()

## Disable the global directional light
func _disable_global_light() -> void:
	var dir_light = get_tree().root.find_child("DirectionalLight3D", true, false)
	if dir_light:
		dir_light.visible = false
		print("[LevelGenerator] Disabled global directional light")

## Generate a new procedural level
func generate_level(custom_seed: int = 0) -> void:
	# Clear existing level
	_clear_level()
	
	# Disable global directional light for per-room lighting
	_disable_global_light()
	
	# Set random seed
	if custom_seed > 0:
		seed(custom_seed)
		seed_value = custom_seed
	elif seed_value > 0:
		seed(seed_value)
	else:
		randomize()
		seed_value = randi()
		seed(seed_value)
	
	print("[LevelGenerator] Generating level with seed: %d" % seed_value)
	
	# Generate BRANCHING room graph (maze-like)
	_generate_branching_graph()
	
	# Assign room types
	_assign_room_types()
	
	# Spawn room spheres with proper positioning
	_spawn_rooms_grid()
	
	# Connect rooms with portals
	_create_portals()
	
	# Notify surfaces of new geometry
	await get_tree().process_frame
	_notify_surface_walkers()
	
	# Wait another frame to ensure all room _ready() and call_deferred have completed
	# This is critical for portal visibility at spawn
	await get_tree().process_frame
	
	# Enable light in start room and sync W for adjacent rooms
	if rooms.size() > 0 and rooms[0].has_method("set_light_enabled"):
		rooms[0].set_light_enabled(true)
		# DON'T set current_lit_room_id yet - let _process do it so it triggers a fresh sync
		# after the player is spawned and positioned
	
	level_generated.emit(rooms)
	
	print("[LevelGenerator] Level generated with %d rooms" % rooms.size())

## Clear all existing rooms
func _clear_level() -> void:
	for room in rooms:
		if is_instance_valid(room):
			room.queue_free()
	rooms.clear()
	room_graph.clear()
	_original_room_w.clear()
	current_lit_room_id = -1

## Generate a BRANCHING room graph (maze-like structure)
func _generate_branching_graph() -> void:
	# Create a tree with branches, not a linear path
	# Start room (0) -> branches out to multiple paths -> Boss at one end
	
	var total_rooms := 1 + num_normal_rooms + 4 + 1  # start + normal + 4 special + boss
	
	# Initialize empty graph
	for i in range(total_rooms):
		room_graph[i] = {
			"connections": [],
			"type": ROOM_NORMAL,
			"position": Vector3.ZERO,
			"depth": 0  # Distance from start
		}
	
	# Build a branching tree structure
	# Start room is root at depth 0
	room_graph[0]["depth"] = 0
	
	# Create branches from start
	var rooms_to_assign: Array = []
	for i in range(1, total_rooms):
		rooms_to_assign.append(i)
	rooms_to_assign.shuffle()
	
	# Assign rooms to different depths/branches
	var current_depth := 1
	var rooms_at_depth: Dictionary = {0: [0]}  # depth -> [room_ids]
	var max_depth := 4  # How deep the maze goes
	
	var idx := 0
	while idx < rooms_to_assign.size():
		var room_id: int = rooms_to_assign[idx]
		
		# Determine depth for this room (more rooms at earlier depths)
		var depth := mini(current_depth, max_depth)
		if randf() < 0.4:
			depth = maxi(1, depth - 1)  # Sometimes go shallower for branches
		
		room_graph[room_id]["depth"] = depth
		
		if not rooms_at_depth.has(depth):
			rooms_at_depth[depth] = []
		rooms_at_depth[depth].append(room_id)
		
		# Connect to a random room at the previous depth
		var parent_depth := depth - 1
		if rooms_at_depth.has(parent_depth) and rooms_at_depth[parent_depth].size() > 0:
			var parent_id: int = rooms_at_depth[parent_depth].pick_random()
			_connect_rooms(parent_id, room_id)
		
		idx += 1
		if idx % 2 == 0:  # Advance depth every 2-3 rooms
			current_depth += 1

	# Add some extra connections to make it more maze-like (optional loops)
	for i in range(min(3, total_rooms / 3)):
		var room_a: int = randi() % total_rooms
		var room_b: int = randi() % total_rooms
		if room_a != room_b and abs(room_graph[room_a]["depth"] - room_graph[room_b]["depth"]) <= 1:
			# Don't duplicate connections
			if room_b not in room_graph[room_a]["connections"]:
				_connect_rooms(room_a, room_b)

## Connect two rooms bidirectionally
func _connect_rooms(a: int, b: int) -> void:
	if b not in room_graph[a]["connections"]:
		room_graph[a]["connections"].append(b)
	if a not in room_graph[b]["connections"]:
		room_graph[b]["connections"].append(a)

## Assign room types to each room in the graph
func _assign_room_types() -> void:
	var total_rooms := room_graph.size()
	
	# Find room with highest depth for boss
	var max_depth := 0
	var boss_room_id := total_rooms - 1
	for room_id in room_graph:
		var depth: int = room_graph[room_id]["depth"]
		if depth > max_depth:
			max_depth = depth
			boss_room_id = room_id
	
	# Start room
	room_graph[0]["type"] = ROOM_NORMAL
	
	# Boss room
	room_graph[boss_room_id]["type"] = ROOM_BOSS
	
	# Collect other rooms for special assignment
	var available: Array = []
	for i in range(total_rooms):
		if i != 0 and i != boss_room_id:
			available.append(i)
	available.shuffle()
	
	# Assign special rooms
	if available.size() > 0:
		room_graph[available.pop_front()]["type"] = ROOM_ITEM
	if available.size() > 0:
		room_graph[available.pop_front()]["type"] = ROOM_SHOP
	if available.size() > 0:
		room_graph[available.pop_front()]["type"] = ROOM_GAMBLING
	if available.size() > 0:
		room_graph[available.pop_front()]["type"] = ROOM_SPECIAL
	
	# Pre-calculate size multipliers for each room (including random enlargement)
	# This MUST happen before positioning so touch distances are correct
	for room_id in room_graph:
		var room_type: int = room_graph[room_id]["type"]
		var size_mult: float = ROOM_SIZES.get(room_type, 1.0)
		if room_type == ROOM_NORMAL:
			size_mult = randf_range(1.0, 2.0)  # Normal rooms vary from 1x to 2x
		room_graph[room_id]["size_mult"] = size_mult

## Check if a proposed room position overlaps with any already-placed rooms
## Returns true if there is NO overlap (position is valid)
## Allows overlap for rooms 2+ graph edges apart (they'll be in different W slices)
func _is_position_valid(proposed_pos: Vector3, proposed_radius: float, room_positions: Dictionary, new_room_id: int, parent_room_id: int = -1) -> bool:
	for existing_room_id in room_positions:
		if existing_room_id == parent_room_id:
			continue
		
		# Allow overlap for rooms 3+ graph distance apart (BFS distance check)
		# Distance 1-2 can be visible together (via W-sync when in shared neighbor)
		var graph_dist: int = _get_graph_distance(new_room_id, existing_room_id)
		if graph_dist >= 3:
			continue  # These rooms can never be visible together, overlap is OK
		
		var existing_pos: Vector4D = room_positions[existing_room_id]
		var existing_radius: float = base_room_radius * room_graph[existing_room_id].get("size_mult", 1.0)
		
		# Calculate distance between room centers
		var dist: float = proposed_pos.distance_to(existing_pos.to_vector3())
		
		# Minimum allowed distance: sum of radii (touching is OK, overlapping is not)
		# Use a small buffer (0.5) to prevent tangent issues
		var min_dist: float = proposed_radius + existing_radius - 0.5
		
		if dist < min_dist:
			return false  # Overlap detected
	return true

## Get the shortest graph distance between two rooms using BFS
func _get_graph_distance(room_a: int, room_b: int) -> int:
	if room_a == room_b:
		return 0
	if not room_graph.has(room_a) or not room_graph.has(room_b):
		return 999  # Unknown rooms treated as far apart
	
	# BFS from room_a to room_b
	var visited: Dictionary = {room_a: 0}
	var queue: Array = [room_a]
	
	while queue.size() > 0:
		var current: int = queue.pop_front()
		var current_dist: int = visited[current]
		
		for neighbor in room_graph[current]["connections"]:
			if neighbor == room_b:
				return current_dist + 1
			if not visited.has(neighbor):
				visited[neighbor] = current_dist + 1
				queue.append(neighbor)
	
	return 999  # Not connected

## Spawn room spheres with W-axis positioning
## Rooms touch at portal points, each at different W coordinate
func _spawn_rooms_grid() -> void:
	# Start room at origin with W=0
	# Other rooms positioned so spheres touch at portal connection points
	
	# First pass: create all rooms with initial positions
	# Room 0 is at origin
	var room_positions: Dictionary = {}  # room_id -> Vector4D (x, y, z, w)
	var placed_rooms: Array = [0]  # IDs of rooms already positioned
	room_positions[0] = Vector4D.zero()
	
	# BFS to position rooms based on connections to already-placed rooms
	var to_process: Array = [0]
	while to_process.size() > 0:
		var current_id: int = to_process.pop_front()
		var connections: Array = room_graph[current_id]["connections"]
		
		for target_id in connections:
			if target_id in placed_rooms:
				continue
			
			# Position target room so it touches current room at portal
			var current_pos: Vector4D = room_positions[current_id]
			# Use pre-calculated size multipliers (includes random enlargement)
			var current_radius: float = base_room_radius * room_graph[current_id].get("size_mult", 1.0)
			var target_radius: float = base_room_radius * room_graph[target_id].get("size_mult", 1.0)
			
			# Distance between centers so spheres just touch
			var touch_distance: float = current_radius + target_radius
			
			# Try multiple directions to find a non-overlapping position
			var max_attempts: int = 50
			var portal_dir: Vector3 = Vector3.ZERO
			var target_xyz: Vector3 = Vector3.ZERO
			var found_valid_position: bool = false
			
			for attempt in range(max_attempts):
				# Random direction for portal placement (on sphere surface)
				portal_dir = Vector3(
					randf_range(-1, 1),
					randf_range(-0.5, 0.5),  # Prefer more horizontal
					randf_range(-1, 1)
				).normalized()
				
				# Position target room center at touch distance from current room
				target_xyz = current_pos.to_vector3() + portal_dir * touch_distance
				
				# Check for overlaps with all already-placed rooms (except current)
				if _is_position_valid(target_xyz, target_radius, room_positions, target_id, current_id):
					found_valid_position = true
					break
				elif attempt == max_attempts - 1:
					# Last attempt: push the room further out to avoid overlap
					var push_distance: float = touch_distance * 1.5
					target_xyz = current_pos.to_vector3() + portal_dir * push_distance
					print("[LevelGen] Room %d pushed further to avoid overlap" % target_id)
			
			# Each room gets unique W coordinate for 4D slice separation
			var target_w: float = target_id * W_SPACING
			
			room_positions[target_id] = Vector4D.new(target_xyz.x, target_xyz.y, target_xyz.z, target_w)
			
			# Store portal direction for later
			if not room_graph[current_id].has("portal_dirs"):
				room_graph[current_id]["portal_dirs"] = {}
			room_graph[current_id]["portal_dirs"][target_id] = portal_dir
			
			if not room_graph[target_id].has("portal_dirs"):
				room_graph[target_id]["portal_dirs"] = {}
			room_graph[target_id]["portal_dirs"][current_id] = -portal_dir
			
			placed_rooms.append(target_id)
			to_process.append(target_id)
	# FALLBACK: Position any rooms not placed by BFS
	# This handles disconnected graphs or rooms not reachable from room 0
	for room_id in range(room_graph.size()):
		if not room_positions.has(room_id):
			# Place radially from origin to avoid overlap
			var angle: float = (room_id * 2.0 * PI) / room_graph.size()
			var radius_offset: float = 100.0 + room_id * 50.0  # Spread out
			var fallback_pos := Vector3(
				cos(angle) * radius_offset,
				randf_range(-20, 20),
				sin(angle) * radius_offset
			)
			var fallback_w: float = room_id * W_SPACING
			room_positions[room_id] = Vector4D.new(fallback_pos.x, fallback_pos.y, fallback_pos.z, fallback_w)
			print("[LevelGen] WARNING: Room %d not in BFS, placed at fallback position %s" % [room_id, fallback_pos])
	
	# Second pass: Create room nodes
	for room_id in range(room_graph.size()):
		var room_type: int = room_graph[room_id]["type"]
		var pos_4d: Vector4D = room_positions.get(room_id, Vector4D.zero())
		
		# Final safety check - don't allow (0,0,0) for non-origin rooms
		if room_id > 0 and pos_4d.to_vector3().length() < 1.0:
			push_error("[LevelGen] BUG: Room %d has invalid position near origin!" % room_id)
		
		room_graph[room_id]["position"] = pos_4d.to_vector3()
		room_graph[room_id]["w"] = pos_4d.w
		
		# Create room sphere
		var room = _create_room(room_id, room_type, pos_4d)
		rooms.append(room)
		
		# Add to scene
		add_child(room)

## Create a single room sphere using script loading
func _create_room(room_id: int, room_type: int, pos_4d: Vector4D) -> Node:
	var RoomSphereScript = load("res://scripts/geometry4d/room_sphere4d.gd")
	var room = RoomSphereScript.new()
	room.room_id = room_id
	room.room_type = room_type
	room.radius = base_room_radius
	
	# Use pre-calculated size multiplier from graph (already includes random enlargement)
	var size_mult: float = room_graph[room_id].get("size_mult", ROOM_SIZES.get(room_type, 1.0))
	room.size_multiplier = size_mult
	
	# Set color
	var color: Color = ROOM_COLORS.get(room_type, Color(0.2, 0.8, 1.0))
	room.room_color = color
	room.glow_color = color
	
	# Set 4D position with W coordinate (convert Vector4D to Vector4 for export setter)
	room.position_4d = pos_4d.to_vector4()
	room.position = pos_4d.to_vector3() # Use local position as it's not in tree yet
	room.name = "Room_%d" % room_id
	
	# Slice threshold based on room radius
	room.slice_threshold = room.radius * size_mult
	
	# Store original W for host-room sync system
	_original_room_w[room_id] = pos_4d.w
	
	# DEBUG: Log room creation
	print("[LevelGen] Created %s: 3D pos=%s, W=%.1f, radius=%.1f" % [room.name, pos_4d.to_vector3(), pos_4d.w, room.radius * size_mult])
	
	return room

## Create portal doors between connected rooms
func _create_portals() -> void:
	var PortalDoorScript = load("res://scripts/level/portal_door.gd")
	var created_pairs: Dictionary = {}
	
	for room_id in room_graph:
		var connections: Array = room_graph[room_id]["connections"]
		var portal_dirs: Dictionary = room_graph[room_id].get("portal_dirs", {})
		
		for target_id in connections:
			# Skip if pair already created
			var pair_key := "%d_%d" % [mini(room_id, target_id), maxi(room_id, target_id)]
			if created_pairs.has(pair_key):
				continue
			created_pairs[pair_key] = true
			
			# Get rooms
			if room_id >= rooms.size() or target_id >= rooms.size():
				continue
			
			var source_room = rooms[room_id]
			var target_room = rooms[target_id]
			
			# Get stored portal direction, or calculate if missing
			var direction: Vector3 = portal_dirs.get(target_id, Vector3.ZERO)
			if direction.length_squared() < 0.01:
				direction = (target_room.global_position - source_room.global_position).normalized()
			
			# Create portal pair with W coordinates
			_create_portal_pair(PortalDoorScript, source_room, target_room, direction)

## Create a pair of connected portal doors
func _create_portal_pair(PortalDoorScript: Script, source_room: Node, target_room: Node, direction: Vector3) -> void:
	# Create source portal
	var source_portal = PortalDoorScript.new()
	source_portal.name = "Portal_%d_to_%d" % [source_room.room_id, target_room.room_id]
	source_room.add_child(source_portal)
	source_portal.position_on_sphere(source_room, direction)
	source_portal.set_color_from_room_type(target_room.room_type)
	source_portal.target_room = target_room
	source_room.add_portal(source_portal)
	
	# Create target portal
	var target_portal = PortalDoorScript.new()
	target_portal.name = "Portal_%d_to_%d" % [target_room.room_id, source_room.room_id]
	target_room.add_child(target_portal)
	target_portal.position_on_sphere(target_room, -direction)
	target_portal.set_color_from_room_type(source_room.room_type)
	target_portal.target_room = source_room
	target_room.add_portal(target_portal)
	
	# Link portals together and activate see-through rendering
	source_portal.link_to_portal(target_portal)

## Notify all surface walkers to refresh their surface list
func _notify_surface_walkers() -> void:
	for walker in get_tree().get_nodes_in_group("surface_walkers_4d"):
		if walker.has_method("refresh_surfaces"):
			walker.refresh_surfaces()

## Spawn player in start room (at CENTER so they fall to surface)
func spawn_player_in_start_room() -> void:
	player = get_tree().get_first_node_in_group("player")
	if not player:
		print("[LevelGenerator] No player found!")
		return
	
	if rooms.is_empty():
		print("[LevelGenerator] No rooms to spawn player in!")
		return
	
	# Spawn in first room (start room)
	var start_room = rooms[0]
	var spawn_pos: Vector3 = start_room.get_spawn_position()
	
	# Just teleport the player - NO 4D mode, just simple 3D
	player.global_position = spawn_pos
	
	print("[LevelGenerator] Player spawned at: %s" % str(spawn_pos))
	player_spawned.emit(start_room)

## Get room by ID
func get_room(room_id: int) -> Node:
	if room_id >= 0 and room_id < rooms.size():
		return rooms[room_id]
	return null

## Get start room
func get_start_room() -> Node:
	return get_room(0)

## Get boss room
func get_boss_room() -> Node:
	# Find room with BOSS type
	for room in rooms:
		if room.room_type == ROOM_BOSS:
			return room
	return null
