extends SceneTree

class TestPlayer extends CharacterBody3D:
	var position_4d := Vector4D.zero()
	var camera: Camera3D
	func _ready() -> void:
		camera = Camera3D.new()
		add_child(camera)
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.35
		capsule.height = 1.5
		shape.shape = capsule
		add_child(shape)
		collision_layer = 2
		collision_mask = 1

class TestRun extends Node:
	var player: TestPlayer
	var keys: int = 0
	var loading: bool = false
	var current_room_id: int = 0
	var charges: int = 0
	func spend_key() -> bool:
		if keys < 1:
			return false
		keys -= 1
		charges += 1
		return true

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var source := _room(stage, 0, 0, Vector3.ZERO, 0.0)
	var purchase := _room(stage, 1, RoomTypes.Type.ITEM, Vector3(40, 0, 0), 30.0)
	var other := _room(stage, 2, 0, Vector3(80, 0, 0), 60.0)
	purchase.set_key_locked(true)
	var front := _pair(source, purchase, Vector3.RIGHT)
	var back := _pair(other, purchase, Vector3.LEFT)
	var player := TestPlayer.new()
	stage.add_child(player)
	player.add_to_group("player")
	player.global_position = front.to_global(Vector3(0, 0, 2.0))
	var run := TestRun.new()
	run.player = player
	stage.add_child(run)
	var interaction: Node3D = front.get_node("KeyRoomInteraction")
	check(front.key_locked and front.target_portal.key_locked and back.key_locked and back.target_portal.key_locked, "Every paired entrance starts locked for the shared special room")
	check(not front.contains_aperture(front.global_position) and not front.contains_player_aperture(front.global_position, player), "A key lock closes both projectile and player apertures")
	check(interaction.is_in_group("item_interactables") and interaction.get_meta("room_id") == source.room_id, "The source room receives an F interaction compatible with RunUI")
	check(interaction.get_interaction_text(run).contains("no keys") and not interaction.interact(run), "No-key interaction shows the requirement and cannot unlock")
	check(run.charges == 0 and purchase.key_locked, "Failed unlock does not charge or mutate the room")
	front._on_transition_body_entered(player)
	player.global_position = front.to_global(Vector3(0, 0, -0.2))
	front._update_w_transitions(0.016)
	check(is_zero_approx(player.position_4d.w), "A locked doorway cannot commit a player's W transition")
	front._on_transition_body_exited(player)
	await physics_frame
	await physics_frame
	# This isolated fixture has no generator W synchronization; expose every
	# adjacent endpoint explicitly as the production generator does.
	for room in [source, purchase, other]:
		room.update_slice(room.position_4d.w)
	check(front._seal_enabled and not front._combat_seal_shape.disabled, "A key lock creates a real enabled collision seal")
	var shot := Projectile.new()
	shot.damage_type = GunTypes.Type.ACCELERATING
	shot.damage = 1.0
	shot.speed = 100.0
	shot.direction = -front.global_basis.z
	shot._set_spawn_origin(front.to_global(Vector3(0, 0, 0.8)))
	shot.position_4d.w = source.position_4d.w
	stage.add_child(shot)
	shot.set_physics_process(false)
	shot._physics_process(0.02)
	check(shot._impact_handled and front.to_local(shot.global_position).z >= -0.05, "A fast projectile physically hits the locked seal before entering the special room")
	player.global_position = front.to_global(Vector3(0, 0, 0.65))
	player.velocity = -front.global_basis.z * 8.0
	player.move_and_slide()
	check(front.to_local(player.global_position).z > 0.30, "Character movement cannot pass the key seal")
	player.global_position = front.to_global(Vector3(0, 0, 2.0))
	run.keys = 2
	check(interaction.interact(run), "F interaction spends a key and opens the special room")
	check(run.keys == 1 and run.charges == 1 and not purchase.key_locked, "The purchase costs exactly one key")
	check(not front.key_locked and not front.target_portal.key_locked and not back.key_locked and not back.target_portal.key_locked, "One purchase permanently unlocks every paired entrance")
	check(not interaction.interact(run) and not back.get_node("KeyRoomInteraction").interact(run) and run.charges == 1, "Repeated and paired door interactions cannot charge again")
	check(front.contains_aperture(front.global_position) and back.contains_aperture(back.global_position), "Both entrances reopen after purchase")
	front._forget_player(player)
	front._on_transition_body_entered(player)
	player.global_position = front.to_global(Vector3(0, 0, -0.2))
	player.velocity = Vector3(2, 3, 4)
	var xyz := player.global_position
	var momentum := player.velocity
	front._update_w_transitions(0.016)
	check(is_equal_approx(player.position_4d.w, 30.0) and player.global_position.is_equal_approx(xyz) and player.velocity.is_equal_approx(momentum), "An unlocked entrance changes W while preserving all XYZ coordinates and momentum")
	var receiver := front.target_portal
	purchase.update_slice(purchase.position_4d.w)
	receiver._on_transition_body_entered(player)
	player.global_position = receiver.to_global(Vector3(0, 0, -0.2))
	receiver._update_w_transitions(0.016)
	check(is_zero_approx(player.position_4d.w), "The unlocked exit supports an immediate deliberate return")
	purchase.set_key_locked(true)
	source.set_combat_locked(true)
	check(purchase.unlock_with_key(run) and not purchase.key_locked and front.combat_locked and not front.contains_aperture(front.global_position), "Spending a key never releases a separate combat lock")
	source.set_combat_locked(false)
	check(front.contains_aperture(front.global_position), "The purchased doorway opens after its combat owner clears")
	purchase.set_key_locked(true)
	source.set_combat_locked(true)
	source.set_combat_locked(false)
	check(front.key_locked and not front.contains_aperture(front.global_position), "Clearing combat never removes an unpaid key lock")
	purchase.set_key_locked(false)
	for direction in [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD, Vector3(1, 0.4, 1).normalized()]:
		purchase.position_4d = Vector4(direction.x * 40.0, direction.y * 40.0, direction.z * 40.0, 30.0)
		front.position_on_sphere(source, direction)
		receiver.position_on_sphere(purchase, -direction)
		check(front.global_position.distance_to(receiver.global_position) < 0.001, "The same circular opening is preserved on every XYZ axis")
		check(front.contains_aperture(front.global_position), "An unlocked circular aperture remains valid at an arbitrary room orientation")
	stage.free()
	# Generated key rooms cannot block the only route to the boss, including the
	# contiguous fallback layout used when random sphere placement exhausts retries.
	var generator := LevelGenerator.new()
	root.add_child(generator)
	current_scene = generator
	generator.enable_decorations = false
	for seed_number in [71, 73921, 120003]:
		generator._rng.seed = seed_number
		generator._generate_branching_graph()
		generator._assign_room_types()
		_check_optional_purchases(generator)
		generator._fallback_positions()
		_check_optional_purchases(generator)
	await generator.generate_level(73921)
	for room in generator.rooms:
		check(room.key_locked == (room.room_type in [RoomTypes.Type.ITEM, RoomTypes.Type.SHOP]), "Only generated item and shop rooms start key locked")
		if room.key_locked:
			for door in room.portals:
				check(door.key_locked and door.target_portal.key_locked, "The generator applies key locks to both entrance sides")
	generator.queue_free()
	await process_frame
	if failures.is_empty():
		print("KEY ROOM LOCK CHECK PASSED: initial seals, F prompt, shared purchase, combat independence, optional routes, XYZ invariants")
	else:
		print("KEY ROOM LOCK CHECK FAILED: ", failures)
	quit(0 if failures.is_empty() else 1)

func _room(stage: Node, id: int, type: int, position: Vector3, w: float) -> RoomSphere4D:
	var room := RoomSphere4D.new()
	room.room_id = id
	room.room_type = type
	room.position_4d = Vector4(position.x, position.y, position.z, w)
	stage.add_child(room)
	return room

func _pair(source: RoomSphere4D, target: RoomSphere4D, direction: Vector3) -> PortalDoor:
	var first := PortalDoor.new()
	var second := PortalDoor.new()
	source.add_child(first)
	first.position_on_sphere(source, direction)
	first.target_room = target
	source.add_portal(first)
	target.add_child(second)
	second.position_on_sphere(target, -direction)
	second.target_room = source
	target.add_portal(second)
	first.link_to_portal(second)
	first._is_ready_for_transitions = true
	second._is_ready_for_transitions = true
	first.set_physics_process(false)
	second.set_physics_process(false)
	return first

func _check_optional_purchases(generator: LevelGenerator) -> void:
	var pending: Array = [0]
	var seen: Dictionary = {0: true}
	var boss := -1
	for id in generator.room_graph:
		if generator.room_graph[id].type == LevelGenerator.ROOM_BOSS:
			boss = id
	while not pending.is_empty():
		var id: int = pending.pop_front()
		for neighbor in generator.room_graph[id].connections:
			if not seen.has(neighbor) and generator.room_graph[neighbor].type not in [LevelGenerator.ROOM_ITEM, LevelGenerator.ROOM_SHOP]:
				seen[neighbor] = true
				pending.append(neighbor)
	check(boss >= 0 and seen.has(boss), "The boss remains reachable without buying either optional special room")
