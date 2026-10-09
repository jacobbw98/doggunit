extends SceneTree

var failures: Array[String] = []

class PlayerStub:
	extends Node3D
	var position_4d := Vector4D.zero()
	var velocity := Vector3.ZERO
	var external_velocity := Vector3.ZERO
	var current_gravity_up := Vector3.UP
	var sphere_facing := Vector3.FORWARD

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var slicer := Slicer4D.new()
	root.add_child(slicer)
	var generator := LevelGenerator.new()
	root.add_child(generator)
	generator.set_process(false)
	for test_seed in range(1, 121):
		generator.num_normal_rooms = [1, 5, 15][test_seed % 3]
		generator.num_secret_rooms = test_seed % 4
		generator._rng.seed = test_seed
		generator.layout_style = test_seed % 3
		generator._generate_branching_graph()
		generator._assign_room_types()
		var positions: Dictionary = {}
		for attempt in range(16):
			positions = generator._layout_positions()
			if not positions.is_empty():
				break
		_check(not positions.is_empty(), "No physical layout for seed %d" % test_seed)
		if positions.is_empty():
			continue
		var graph := generator.room_graph
		for id in graph:
			_check(generator._get_graph_distance(0, id) < 999, "Disconnected room %d, seed %d" % [id, test_seed])
			_check(graph[id]["connections"].size() <= 3, "Too many apertures")
			if graph[id]["type"] == generator.ROOM_SECRET:
				_check(graph[id]["connections"].size() == 1, "Secret lies on required route")
				_check(not graph[id]["discovered"] and graph[id]["home_w"] < 0, "Secret is exposed at spawn")
			for other in graph:
				if id >= other:
					continue
				var expected_distance: float = generator.base_room_radius * (graph[id]["size_mult"] + graph[other]["size_mult"])
				var distance: float = positions[id].distance_to(positions[other])
				if other in graph[id]["connections"]:
					_check(absf(distance - expected_distance) < 0.001, "Portal rooms do not physically meet")
				elif generator._get_graph_distance(id, other) < 3:
					_check(distance >= expected_distance, "Co-visible rooms overlap")
		# Global gameplay randomness must not alter a seeded level.
		var first_graph: String = var_to_str(graph)
		generator._rng.seed = test_seed
		for ignored in range(13):
			randf()
		generator._generate_branching_graph()
		generator._assign_room_types()
		for attempt in range(16):
			if not generator._layout_positions().is_empty():
				break
		_check(var_to_str(generator.room_graph) == first_graph, "Seed is not reproducible")
		# Even exhausted placement attempts must preserve reachable touching rooms.
		positions = generator._fallback_positions()
		for id in generator.room_graph:
			var data: Dictionary = generator.room_graph[id]
			_check(generator._get_graph_distance(0, id) < 999, "Fallback disconnected a room")
			for neighbor in data["connections"]:
				var distance: float = generator.base_room_radius * (data["size_mult"] + generator.room_graph[neighbor]["size_mult"])
				_check(absf(positions[id].distance_to(positions[neighbor]) - distance) < 0.001, "Fallback stretched a doorway")
	_test_models()
	# Exercise real scene instantiation, door availability and W-layer syncing.
	generator.num_normal_rooms = 5
	generator.num_secret_rooms = 1
	generator.enable_decorations = false
	await generator.generate_level(711)
	generator.set_active_room(0)
	var stub := PlayerStub.new()
	stub.add_to_group("player")
	root.add_child(stub)
	generator.player = stub
	var secret: Node = null
	for room in generator.rooms:
		for portal in room.portals:
			_check(portal.global_position.distance_to(portal.target_portal.global_position) < 0.001, "Paired apertures do not share their physical location")
		if room.room_type == generator.ROOM_SECRET:
			secret = room
			_check(not room.visible and not room.portals[0].available, "Undiscovered secret visible/traversable")
	var host_portal: Node3D = secret.portals[0].target_portal
	generator.set_active_room(host_portal.source_room.room_id)
	stub.global_position = host_portal.source_room.global_position
	generator.set_secret_scan_enabled(true)
	_check(not generator.room_graph[secret.room_id]["discovered"], "Scan reveals a distant doorway")
	stub.global_position = host_portal.global_position - host_portal.portal_direction * 3.0
	generator._scan_secret_rooms()
	_check(generator.room_graph[secret.room_id]["discovered"] and host_portal.available and secret.portals[0].available, "Nearby scan did not reveal doorway pair")
	_check(secret.visible, "Revealed adjacent secret did not sync into visible slice")
	var original_position: Vector3 = stub.global_position
	stub.velocity = Vector3(1, 2, 3)
	host_portal._perform_portal_transition(stub, secret)
	_check(stub.global_position == original_position and stub.velocity == Vector3(1, 2, 3), "Secret crossing changed XYZ or momentum")
	_check(stub.position_4d.w == generator._original_room_w[secret.room_id] and stub.position_4d.w < 0, "Secret does not occupy its distinct W layer")
	stub.external_velocity = Vector3.ONE
	generator.spawn_player_in_start_room()
	_check(stub.position_4d.w == 0 and slicer.slice_w == 0 and slicer.target_w == 0, "New floor spawn did not reset W")
	_check(stub.velocity == Vector3.ZERO and stub.external_velocity == Vector3.ZERO, "New floor spawn kept old momentum")
	_check(generator.current_lit_room_id == 0, "New floor spawn kept old host")
	var previous_room: WeakRef = weakref(generator.rooms[0])
	generator.rooms[0].set_ghost_mode(true)
	generator.rooms[0].update_slice(1000.0)
	var previous_ghost: WeakRef = weakref(generator.rooms[0].ghost_mesh)
	await generator.generate_level(712)
	generator.spawn_player_in_start_room()
	_check(previous_room.get_ref() == null and previous_ghost.get_ref() == null, "Old floor room or debug ghost leaked into next floor")
	_check(slicer.objects_4d.size() == generator.rooms.size(), "Slicer retained stale rooms after regeneration")
	print("WORLD TESTS: %d failures (120 seeds, three layouts, nine models on six axes, physical doors, secret discovery and spawn reset)" % failures.size())
	stub.queue_free()
	generator.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _test_models() -> void:
	var decorator := RoomDecorator.new()
	decorator.set_seed(451)
	var room := RoomSphere4D.new()
	root.add_child(room)
	room.radius = 20.0
	for entry in decorator.model_catalog:
		for radial in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
			decorator._place_model(room, entry, radial * 19.85, Vector3.ZERO, 20.0)
			var wrapper: Node3D = room.get_child(room.get_child_count() - 1)
			_check(wrapper.basis.y.normalized().dot(-radial) > 0.9999, "Model up points away from room center")
			var bounds := decorator._calculate_local_aabb(wrapper)
			_check(absf(bounds.position.y) < 0.0001, "Imported model not grounded: %s" % entry.path)
			_check(absf(bounds.get_center().x) < 0.0001 and absf(bounds.get_center().z) < 0.0001, "Imported root offsets not centered")
			wrapper.free()
	room.free()
