# Connected, physically adjoining sphere rooms. Portal traversal never moves XYZ.
class_name LevelGenerator
extends Node

@export var base_room_radius: float = 20.0
@export_range(1, 30) var num_normal_rooms: int = 5
@export_range(0, 3) var num_secret_rooms: int = 1
@export var seed_value: int = 0
@export var auto_generate: bool = false
@export var enable_decorations: bool = true

const W_SPACING: float = 100.0
const ROOM_NORMAL := 0
const ROOM_BOSS := 1
const ROOM_ITEM := 2
const ROOM_SHOP := 3
const ROOM_GAMBLING := 4
const ROOM_SPECIAL := 5
const ROOM_SECRET := 6
const ROOM_COLORS := RoomTypes.ROOM_COLORS
const ROOM_SIZES := RoomTypes.ROOM_SIZES
const LAYOUT_NAMES := ["Branching trails", "Long expedition", "Broad woodland"]

var rooms: Array = []
var room_graph: Dictionary = {}
var player: Node = null
var level_depth: int = 1
var layout_style: int = 0
var current_lit_room_id: int = -1
var secret_scan_enabled: bool = false
var _original_room_w: Dictionary = {}
var _decorator: RoomDecorator = null
var _rng := RandomNumberGenerator.new()
var _last_synced_w: float = INF
var _key_room_ids: Array[int] = []

signal level_generated(rooms: Array)
signal player_spawned(spawn_room: Node)
signal room_entered(room: Node)
signal secret_discovered(room: Node)

func _ready() -> void:
	add_to_group("level_generator")
	if auto_generate:
		call_deferred("_auto_generate_level")

func _auto_generate_level() -> void:
	await generate_level(seed_value)
	spawn_player_in_start_room()

func _process(_delta: float) -> void:
	if rooms.is_empty():
		return
	player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		return
	var player_w: float = player.position_4d.w if player.get("position_4d") != null else 0.0
	var room_id := _get_player_room_id(player.global_position, player_w)
	if room_id >= 0 and room_id != current_lit_room_id:
		set_active_room(room_id)
	elif not is_equal_approx(_last_synced_w, player_w):
		_update_room_w_sync(current_lit_room_id)
	if secret_scan_enabled:
		_scan_secret_rooms()

func _get_player_room_id(player_pos: Vector3, _player_w: float) -> int:
	# Only physically connected rooms can become the host. Distant W layers may
	# share XYZ, so scanning every sphere can select an unrelated room.
	var candidates: Array = [0] if current_lit_room_id < 0 else [current_lit_room_id]
	if current_lit_room_id >= 0:
		candidates.append_array(get_visible_connections(current_lit_room_id))
	var best_id := -1
	var best_penetration: float = -INF
	for room_id in candidates:
		var room = rooms[room_id]
		if not is_instance_valid(room):
			continue
		var penetration: float = room.radius - player_pos.distance_to(room.global_position)
		if penetration > best_penetration and penetration > -0.25:
			best_id = room_id
			best_penetration = penetration
	return best_id

func set_active_room(room_id: int) -> void:
	if room_id < 0 or room_id >= rooms.size():
		return
	var changed := current_lit_room_id != room_id
	current_lit_room_id = room_id
	_update_room_w_sync(room_id)
	_update_room_lights(room_id)
	if changed:
		room_entered.emit(rooms[room_id])

func get_visible_connections(room_id: int) -> Array:
	var result: Array = []
	if not room_graph.has(room_id):
		return result
	for neighbor in room_graph[room_id]["connections"]:
		if room_graph[neighbor].get("discovered", true):
			result.append(neighbor)
	return result

func _update_room_lights(player_room_id: int) -> void:
	var active: Array = [player_room_id] + get_visible_connections(player_room_id)
	for room in rooms:
		if is_instance_valid(room):
			room.set_light_enabled(room.room_id in active)

func _update_room_w_sync(player_room_id: int) -> void:
	if player_room_id < 0 or player_room_id >= rooms.size():
		return
	var slicer = get_tree().get_first_node_in_group("slicer_4d")
	var current_w: float = 0.0
	if is_instance_valid(player) and player.get("position_4d") != null:
		current_w = player.position_4d.w
	elif slicer:
		current_w = slicer.slice_w
	var active: Array = [player_room_id] + get_visible_connections(player_room_id)
	for room in rooms:
		var id: int = room.room_id
		var room_w: float = current_w if id in active else _original_room_w[id]
		room.graph_visible = id in active
		room.position_4d = Vector4(room.position_4d.x, room.position_4d.y, room.position_4d.z, room_w)
		room.update_slice(current_w)
	_last_synced_w = current_w
	if slicer:
		slicer.slice_w = current_w
		slicer.target_w = current_w

func set_secret_scan_enabled(enabled: bool) -> void:
	secret_scan_enabled = enabled
	if enabled:
		_scan_secret_rooms()

func get_secret_hint() -> String:
	if current_lit_room_id < 0:
		return ""
	for id in room_graph[current_lit_room_id]["connections"]:
		if not room_graph[id].get("discovered", true):
			return "A hidden scent crosses this room. Q: sniff near the walls."
	return ""

func _scan_secret_rooms() -> void:
	if current_lit_room_id < 0 or not is_instance_valid(player):
		return
	var host = rooms[current_lit_room_id]
	for portal in host.portals:
		var target = portal.target_room
		if not is_instance_valid(target):
			continue
		if room_graph[target.room_id].get("discovered", true):
			continue
		if player.global_position.distance_to(portal.global_position) > 12.0:
			continue
		room_graph[target.room_id]["discovered"] = true
		portal.set_available(true)
		portal.target_portal.set_available(true)
		host._update_shader_portal_holes()
		target._update_shader_portal_holes()
		_update_room_w_sync(current_lit_room_id)
		_update_room_lights(current_lit_room_id)
		secret_discovered.emit(target)

func generate_level(custom_seed: int = 0) -> void:
	_clear_level()
	var directional = get_tree().root.find_child("DirectionalLight3D", true, false)
	if directional:
		directional.visible = false
	if custom_seed != 0:
		seed_value = custom_seed
	elif seed_value == 0:
		_rng.randomize()
		seed_value = int(_rng.randi())
	_rng.seed = seed_value
	layout_style = _rng.randi_range(0, LAYOUT_NAMES.size() - 1)
	_generate_branching_graph()
	_assign_room_types()
	_spawn_rooms_grid()
	_create_portals()
	if enable_decorations:
		_decorate_rooms()
	await get_tree().process_frame
	_notify_surface_walkers()
	await get_tree().process_frame
	level_generated.emit(rooms)
	print("[LevelGenerator] Seed %d: %s, %d connected rooms" % [seed_value, LAYOUT_NAMES[layout_style], rooms.size()])

func _clear_level() -> void:
	for room in rooms:
		if is_instance_valid(room):
			# Remove immediately from queries; deletion completes at end of frame.
			remove_child(room)
			room.queue_free()
	rooms.clear()
	room_graph.clear()
	_original_room_w.clear()
	_key_room_ids.clear()
	current_lit_room_id = -1
	_last_synced_w = INF
	secret_scan_enabled = false

func _new_room_data() -> Dictionary:
	return {"connections": [], "type": ROOM_NORMAL, "position": Vector3.ZERO,
		"depth": 0, "parent": -1, "portal_dirs": {}, "discovered": true}

func _generate_branching_graph() -> void:
	room_graph.clear()
	var normal_count := maxi(num_normal_rooms, 1)
	var total := 1 + normal_count + 4 + 1
	var main_total := total - 2
	for id in range(total):
		room_graph[id] = _new_room_data()
	# Each new room attaches to an existing connected parent: no skipped depth
	# can leave an orphan. A degree cap also keeps the shader's eight-hole limit safe.
	for id in range(1, main_total):
		var candidates: Array = []
		for previous in range(id):
			if room_graph[previous]["connections"].size() < 3:
				candidates.append(previous)
		var parent_id: int = candidates[_rng.randi_range(0, candidates.size() - 1)]
		if layout_style == 1 and _rng.randf() < 0.8:
			parent_id = candidates.back()
		elif layout_style == 2:
			parent_id = candidates.front()
		_connect_rooms(parent_id, id)
		room_graph[id]["parent"] = parent_id
		room_graph[id]["depth"] = room_graph[parent_id]["depth"] + 1
	# Key purchases are optional side trips. The boss route remains reachable
	# even after the player spends their last key on the other special room.
	var boss_candidate := 1
	for id in range(main_total):
		if room_graph[id]["depth"] > room_graph[boss_candidate]["depth"]:
			boss_candidate = id
	_key_room_ids.clear()
	for offset in range(2):
		var id := main_total + offset
		var candidates: Array[int] = []
		for previous in range(main_total):
			if previous != boss_candidate and room_graph[previous]["connections"].size() < 3:
				candidates.append(previous)
		var parent_id: int = candidates[_rng.randi_range(0, candidates.size() - 1)]
		_connect_rooms(parent_id, id)
		room_graph[id]["parent"] = parent_id
		room_graph[id]["depth"] = room_graph[parent_id]["depth"] + 1
		room_graph[id]["type"] = ROOM_ITEM if offset == 0 else ROOM_SHOP
		_key_room_ids.append(id)

func _connect_rooms(a: int, b: int) -> void:
	if b not in room_graph[a]["connections"]:
		room_graph[a]["connections"].append(b)
	if a not in room_graph[b]["connections"]:
		room_graph[b]["connections"].append(a)

func _assign_room_types() -> void:
	var boss_id := 1
	for id in room_graph:
		if id not in _key_room_ids and room_graph[id]["depth"] > room_graph[boss_id]["depth"]:
			boss_id = id
	room_graph[boss_id]["type"] = ROOM_BOSS
	var available: Array = []
	for id in room_graph:
		if id != 0 and id != boss_id and id not in _key_room_ids:
			available.append(id)
	_shuffle(available)
	for type in [ROOM_GAMBLING, ROOM_SPECIAL]:
		room_graph[available.pop_back()]["type"] = type
	for id in room_graph:
		var type: int = room_graph[id]["type"]
		room_graph[id]["size_mult"] = _rng.randf_range(1.0, 1.8) if type == ROOM_NORMAL else ROOM_SIZES[type]
		room_graph[id]["biome"] = _rng.randi_range(0, 2)
	# Secrets are optional leaves; the route to the boss never requires discovery.
	for secret_index in range(num_secret_rooms):
		var candidates: Array = []
		for id in room_graph:
			if id != boss_id and room_graph[id]["type"] != ROOM_SECRET and room_graph[id]["connections"].size() < 3:
				candidates.append(id)
		var parent_id: int = candidates[_rng.randi_range(0, candidates.size() - 1)]
		var id := room_graph.size()
		room_graph[id] = _new_room_data()
		room_graph[id].merge({"type": ROOM_SECRET, "parent": parent_id, "discovered": false,
			"depth": room_graph[parent_id]["depth"] + 1, "size_mult": 0.8, "biome": 2,
			"home_w": -(secret_index + 1) * W_SPACING}, true)
		_connect_rooms(parent_id, id)

func _shuffle(values: Array) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var old = values[i]
		values[i] = values[j]
		values[j] = old

func _get_graph_distance(a: int, b: int) -> int:
	if a == b:
		return 0
	var visited: Dictionary = {a: 0}
	var pending: Array = [a]
	while not pending.is_empty():
		var id: int = pending.pop_front()
		for neighbor in room_graph[id]["connections"]:
			if neighbor == b:
				return visited[id] + 1
			if not visited.has(neighbor):
				visited[neighbor] = visited[id] + 1
				pending.append(neighbor)
	return 999

func _is_position_valid(pos: Vector3, radius: float, positions: Dictionary, id: int, parent_id: int = -1) -> bool:
	for other in positions:
		if other == parent_id or _get_graph_distance(id, other) >= 3:
			continue
		var other_radius: float = base_room_radius * room_graph[other]["size_mult"]
		if pos.distance_to(positions[other]) < radius + other_radius + 0.25:
			return false
	return true

func _layout_positions() -> Dictionary:
	var positions: Dictionary = {0: Vector3.ZERO}
	for id in room_graph:
		room_graph[id]["portal_dirs"] = {}
	for id in range(1, room_graph.size()):
		var parent_id: int = room_graph[id]["parent"]
		var parent_pos: Vector3 = positions[parent_id]
		var radius: float = base_room_radius * room_graph[id]["size_mult"]
		var distance: float = radius + base_room_radius * room_graph[parent_id]["size_mult"]
		var found := false
		for attempt in range(256):
			var direction := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.8, 0.8), _rng.randf_range(-1, 1)).normalized()
			if direction.length_squared() < 0.5:
				continue
			var candidate := parent_pos + direction * distance
			if not _is_position_valid(candidate, radius, positions, id, parent_id):
				continue
			positions[id] = candidate
			room_graph[parent_id]["portal_dirs"][id] = direction
			room_graph[id]["portal_dirs"][parent_id] = -direction
			found = true
			break
		if not found:
			return {}
	return positions

func _spawn_rooms_grid() -> void:
	var positions: Dictionary = {}
	for attempt in range(16):
		positions = _layout_positions()
		if not positions.is_empty():
			break
	if positions.is_empty():
		positions = _fallback_positions()
	for id in range(room_graph.size()):
		var pos: Vector3 = positions[id]
		var home_w: float = room_graph[id].get("home_w", id * maxf(W_SPACING, base_room_radius * 5.0))
		room_graph[id]["position"] = pos
		room_graph[id]["w"] = home_w
		room_graph[id]["depth"] = _get_graph_distance(0, id)
		for neighbor in room_graph[id]["connections"]:
			room_graph[id]["portal_dirs"][neighbor] = (positions[neighbor] - pos).normalized()
		var room := _create_room(id, room_graph[id]["type"], Vector4D.from_vector3(pos, home_w))
		rooms.append(room)
		add_child(room)

func _fallback_positions() -> Dictionary:
	# Guaranteed contiguous fallback, never a detached room or stretched doorway.
	# Preserve room roles; the boss remains the end of the main path.
	var main_ids: Array = []
	var boss_id := -1
	for id in room_graph:
		room_graph[id]["connections"] = []
		room_graph[id]["portal_dirs"] = {}
		if room_graph[id]["type"] == ROOM_BOSS:
			boss_id = id
		elif room_graph[id]["type"] not in [ROOM_SECRET, ROOM_ITEM, ROOM_SHOP]:
			main_ids.append(id)
	main_ids.append(boss_id)
	var positions: Dictionary = {0: Vector3.ZERO}
	for i in range(1, main_ids.size()):
		var id: int = main_ids[i]
		var previous: int = main_ids[i - 1]
		_connect_rooms(previous, id)
		room_graph[id]["parent"] = previous
		positions[id] = positions[previous] + Vector3.RIGHT * base_room_radius * (room_graph[previous]["size_mult"] + room_graph[id]["size_mult"])
	var purchase_index := 0
	for id in room_graph:
		if room_graph[id]["type"] in [ROOM_ITEM, ROOM_SHOP]:
			var previous: int = main_ids[purchase_index]
			var direction := Vector3.DOWN if purchase_index == 0 else Vector3.BACK
			purchase_index += 1
			_connect_rooms(previous, id)
			room_graph[id]["parent"] = previous
			positions[id] = positions[previous] + direction * base_room_radius * (room_graph[previous]["size_mult"] + room_graph[id]["size_mult"])
	var secret_count := 0
	for id in room_graph:
		if room_graph[id]["type"] == ROOM_SECRET:
			var previous: int = main_ids[secret_count]
			secret_count += 1
			_connect_rooms(previous, id)
			room_graph[id]["parent"] = previous
			positions[id] = positions[previous] + Vector3.UP * base_room_radius * (room_graph[previous]["size_mult"] + room_graph[id]["size_mult"])
	return positions

func _create_room(id: int, type: int, pos: Vector4D) -> Node:
	var room := RoomSphere4D.new()
	room.room_id = id
	room.room_type = type
	room.key_locked = type in [ROOM_ITEM, ROOM_SHOP]
	room.radius = base_room_radius
	room.size_multiplier = room_graph[id]["size_mult"]
	room.room_color = ROOM_COLORS[type]
	room.glow_color = ROOM_COLORS[type]
	room.biome = room_graph[id]["biome"]
	room.graph_visible = id == 0
	room.position_4d = pos.to_vector4()
	room.name = "Room_%d" % id
	room.slice_threshold = room.radius * room.size_multiplier
	_original_room_w[id] = pos.w
	return room

func _create_portals() -> void:
	var portal_script = load("res://scripts/level/portal_door.gd")
	for id in room_graph:
		for target_id in room_graph[id]["connections"]:
			if target_id > id:
				_create_portal_pair(portal_script, rooms[id], rooms[target_id], room_graph[id]["portal_dirs"][target_id])

func _create_portal_pair(portal_script: Script, source: Node, target: Node, direction: Vector3) -> void:
	var first = portal_script.new()
	first.name = "Portal_%d_to_%d" % [source.room_id, target.room_id]
	source.add_child(first)
	first.position_on_sphere(source, direction)
	first.set_color_from_room_type(target.room_type)
	first.target_room = target
	source.add_portal(first)
	var second = portal_script.new()
	second.name = "Portal_%d_to_%d" % [target.room_id, source.room_id]
	target.add_child(second)
	second.position_on_sphere(target, -direction)
	second.set_color_from_room_type(source.room_type)
	second.target_room = source
	target.add_portal(second)
	first.link_to_portal(second)
	var available: bool = room_graph[source.room_id]["discovered"] and room_graph[target.room_id]["discovered"]
	first.set_available(available)
	second.set_available(available)

func _decorate_rooms() -> void:
	if not _decorator:
		_decorator = RoomDecorator.new()
	_decorator.set_seed(seed_value)
	for room in rooms:
		_decorator.decorate_room(room, room.room_type, room.get_portal_positions())

func _notify_surface_walkers() -> void:
	for walker in get_tree().get_nodes_in_group("surface_walkers_4d"):
		if walker.has_method("refresh_surfaces"):
			walker.refresh_surfaces()

func spawn_player_in_start_room() -> void:
	player = get_tree().get_first_node_in_group("player")
	if not player or rooms.is_empty():
		return
	var start = rooms[0]
	player.global_position = start.get_spawn_position()
	if player.has_method("set_position_4d"):
		player.set_position_4d(Vector4D.from_vector3(player.global_position, 0.0))
	elif player.get("position_4d") != null:
		player.position_4d = Vector4D.from_vector3(player.global_position, 0.0)
	player.basis = Basis.IDENTITY
	if player.get("velocity") != null:
		player.velocity = Vector3.ZERO
	if player.get("external_velocity") != null:
		player.external_velocity = Vector3.ZERO
	if player.get("current_gravity_up") != null:
		player.current_gravity_up = Vector3.UP
	if player.get("sphere_facing") != null:
		player.sphere_facing = Vector3.FORWARD
	for field in ["current_momentum", "bhop_window_timer", "frozen_timer"]:
		if player.get(field) != null:
			player.set(field, 0.0)
	for field in ["is_sliding", "was_grounded_last_frame"]:
		if player.get(field) != null:
			player.set(field, false)
	if player.has_meta("active_room_id"):
		player.set_meta("active_room_id", 0)
	set_active_room(0)
	player_spawned.emit(start)

func get_room(id: int) -> Node:
	return rooms[id] if id >= 0 and id < rooms.size() else null

func get_start_room() -> Node:
	return get_room(0)

func get_boss_room() -> Node:
	for room in rooms:
		if room.room_type == ROOM_BOSS:
			return room
	return null
