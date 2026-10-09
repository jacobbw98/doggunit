extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
		push_error(description)

func _run() -> void:
	var packed: PackedScene = load("res://scenes/levels/procedural_level.tscn")
	var level: Node = packed.instantiate()
	level.get_node("RunUI").free()
	var generator: Node = level.get_node("LevelGenerator")
	generator.enable_decorations = false
	root.get_node("GameManager").run_seed = 73921
	root.add_child(level)
	current_scene = level
	var run: Node = level.get_node("RunManager")
	for frame in range(180):
		await process_frame
		if not run.loading:
			break
	check(not run.loading, "Generated run becomes ready")
	if run.loading:
		quit(1)
		return
	var player: Node = run.player
	player.set_physics_process(false)
	player.set_meta("god_mode", true)
	generator.set_process(false)
	run.set_process(false)
	var start: Node = generator.get_start_room()
	for portal in start.portals:
		check(not portal.combat_locked, "Safe start has no combat locks")

	var combat: Node
	var secret: Node
	for room in generator.rooms:
		if room.room_type == 0 and room.room_id != 0 and combat == null:
			combat = room
		if room.room_type == 6:
			secret = room
	_enter_room(player, generator, combat)
	var native_enemies: Array = _room_enemies(combat.room_id)
	check(native_enemies.size() == 3, "Combat entry spawns the expected first-floor encounter")
	_check_room_locked(combat, true, "Combat entry")
	for portal in combat.portals:
		check(not portal.contains_aperture(portal.global_position), "Combat seal closes the projectile aperture")
	await physics_frame
	await physics_frame
	var sealed_door: Node3D = combat.portals[0]
	var shot := Projectile.new()
	shot.damage_type = GunTypes.Type.ACCELERATING
	shot.damage = 1.0
	shot.speed = 100.0
	shot.direction = -sealed_door.global_basis.z
	shot._set_spawn_origin(sealed_door.to_global(Vector3(0, 0, 0.8)))
	shot.position_4d.w = combat.position_4d.w
	level.add_child(shot)
	shot.set_physics_process(false)
	shot._physics_process(0.02)
	check(shot._impact_handled, "A travelling projectile collides with the real locked doorway seal")
	check(sealed_door.to_local(shot.global_position).z >= -0.05, "Combat seal catches the projectile before it enters the neighbor")
	var extra: Node3D = _spawn_debug_enemy(level, combat)
	run._sync_combat_locks()
	check(run._get_enemy_room_id(extra) == combat.room_id, "An untagged debug enemy resolves to its containing room")
	check(run.room_enemy_counts.get(combat.room_id, 0) == 4, "Encounter count includes an extra live debug enemy")
	var previous_rewards: int = _room_pedestals(combat.room_id).size()
	var previous_clears: int = root.get_node("GameManager").rooms_cleared
	for enemy in native_enemies:
		enemy.take_damage(10000, 0)
	_check_room_locked(combat, true, "Extra enemy still alive after original encounter dies")
	check(not run.room_states[combat.room_id].cleared and run.room_enemy_counts.get(combat.room_id, 0) == 1, "Original last kill cannot clear a room with a surviving extra enemy")
	check(_room_pedestals(combat.room_id).size() == previous_rewards, "Reward waits for every live enemy")
	extra.take_damage(10000, 0)
	run._process(0.0)
	_check_room_locked(combat, false, "Final enemy defeated")
	check(run.room_states[combat.room_id].cleared and _room_pedestals(combat.room_id).size() == previous_rewards + 1 and root.get_node("GameManager").rooms_cleared == previous_clears + 1, "The final death clears and spawns one reward pedestal exactly once")
	check(not paused, "A physical reward leaves gameplay running")
	for portal in combat.portals:
		if portal.available and not portal.key_locked:
			check(portal.contains_aperture(portal.global_position), "Available doors reopen their projectile aperture immediately after combat")
	run._on_room_entered(combat)
	_check_room_locked(combat, false, "Cleared-room revisit")
	check(_room_pedestals(combat.room_id).size() == previous_rewards + 1 and root.get_node("GameManager").rooms_cleared == previous_clears + 1, "Revisiting the cleared room does not issue another reward")

	var late_extra: Node3D = _spawn_debug_enemy(level, combat)
	run._sync_combat_locks()
	_check_room_locked(combat, true, "New debug enemy in a cleared room")
	late_extra.take_damage(10000, 0)
	run._sync_combat_locks()
	_check_room_locked(combat, false, "Debug extra removed from cleared room")
	check(_room_pedestals(combat.room_id).size() == previous_rewards + 1 and root.get_node("GameManager").rooms_cleared == previous_clears + 1, "Late debug enemies cannot farm duplicate room rewards")
	# Either room can own the pair's lock. Clearing one owner cannot release the other.
	var paired_room: Node = sealed_door.target_room
	combat.set_combat_locked(true)
	paired_room.set_combat_locked(true)
	combat.set_combat_locked(false)
	check(sealed_door.combat_locked and sealed_door.target_portal.combat_locked, "A surviving neighbor lock keeps both sides closed when one owner clears")
	paired_room.set_combat_locked(false)
	check(not sealed_door.combat_locked and not sealed_door.target_portal.combat_locked, "Both sides reopen after the final lock owner clears")

	check(secret != null, "Fixture includes a hidden secret room")
	var secret_host: Node = generator.get_room(generator.room_graph[secret.room_id].connections[0])
	_enter_room(player, generator, secret_host)
	var hidden_door: Node
	for portal in secret_host.portals:
		if portal.target_room == secret:
			hidden_door = portal
	check(hidden_door != null and not hidden_door.available, "Undiscovered secret availability starts disabled")
	var guard: Node3D = _spawn_debug_enemy(level, secret_host)
	run._sync_combat_locks()
	check(hidden_door.combat_locked and hidden_door.target_portal.combat_locked, "Hidden doors share combat locks on both sides")
	check(not hidden_door.available and not hidden_door.target_portal.available, "Combat locking does not reveal a secret")
	player.global_position = hidden_door.global_position + (secret_host.global_position - hidden_door.global_position).normalized() * 3.0
	generator.set_secret_scan_enabled(true)
	check(hidden_door.available and hidden_door.target_portal.available, "Sniffing can discover the secret during combat")
	check(hidden_door.combat_locked and not hidden_door.contains_aperture(hidden_door.global_position), "Discovery never bypasses an active combat lock")
	guard.take_damage(10000, 0)
	for enemy in _room_enemies(secret_host.room_id):
		enemy.take_damage(10000, 0)
	run._sync_combat_locks()
	check(hidden_door.available and not hidden_door.combat_locked and hidden_door.contains_aperture(hidden_door.global_position), "Defeating all hostiles opens the discovered secret without losing its availability")
	var removal_room: Node
	for room in generator.rooms:
		if room.room_type == 0 and room.room_id != 0 and not run.room_states.has(room.room_id):
			removal_room = room
			break
	check(removal_room != null, "Fixture has an unvisited room for removal recovery")
	_enter_room(player, generator, removal_room)
	_check_room_locked(removal_room, true, "Encounter before external enemy removal")
	for enemy in _room_enemies(removal_room.room_id):
		enemy.queue_free()
	run._process(0.0)
	_check_room_locked(removal_room, false, "Enemy removal without a death signal")
	check(run.room_states[removal_room.room_id].cleared, "Removing all live enemy nodes cannot leave the encounter permanently blocked")
	check(run.get_status_text().contains("0 hostiles"), "Cleared-room HUD does not retain a stale hostile count after node removal")

	if failures.is_empty():
		print("PORTAL LOCK INTEGRATION PASSED: encounter entry, paired seals, live extras, last kill, revisits, secret independence")
	else:
		print("PORTAL LOCK INTEGRATION FAILED: ", failures)
	quit(0 if failures.is_empty() else 1)

func _enter_room(player: Node3D, generator: Node, room: Node) -> void:
	player.global_position = room.get_spawn_position()
	generator.set_active_room(room.room_id)

func _room_enemies(room_id: int) -> Array:
	var enemies: Array = []
	for enemy in get_nodes_in_group("enemies"):
		if enemy.get_meta("encounter_room", -1) == room_id and not enemy.is_queued_for_deletion() and enemy.get("current_health") > 0:
			enemies.append(enemy)
	return enemies

func _room_pedestals(room_id: int) -> Array:
	var pedestals: Array = []
	for pedestal in get_nodes_in_group("item_pedestals"):
		if pedestal.room_id == room_id and not pedestal.is_queued_for_deletion():
			pedestals.append(pedestal)
	return pedestals

func _spawn_debug_enemy(level: Node, room: Node) -> Node3D:
	var enemy := Enemy4D.new()
	enemy.enable_4d_mode = false
	enemy.initial_w = room.position_4d.w
	enemy.position = room.get_spawn_position()
	level.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy

func _check_room_locked(room: Node, expected: bool, context: String) -> void:
	for portal in room.portals:
		check(portal.combat_locked == expected, "%s: local door lock matches remaining enemies" % context)
		check(portal.target_portal.combat_locked == expected, "%s: paired door has the same lock" % context)
