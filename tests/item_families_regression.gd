extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
		push_error(description)

func _run() -> void:
	var game: Node = root.get_node("GameManager")
	game.run_seed = 73921
	var level: Node = load("res://scenes/levels/procedural_level.tscn").instantiate()
	level.get_node("RunUI").free()
	level.get_node("LevelGenerator").enable_decorations = false
	root.add_child(level)
	current_scene = level
	var run: Node = level.get_node("RunManager")
	for frame in range(180):
		await process_frame
		if not run.loading:
			break
	check(not run.loading, "Run becomes ready for family tests")
	if run.loading:
		quit(1)
		return
	run.player.set_physics_process(false)
	run.player.set_meta("god_mode", true)
	run.generator.set_process(false)
	run.set_process(false)
	var inventory: WeaponManager = run.player.weapon_manager
	var selected: Gun = inventory.get_current_gun()
	var other: Gun = inventory.guns[1]
	var counts := {PetItems.Category.GLOBAL_PASSIVE: 0, PetItems.Category.DOG_INCLUSIVE: 0, PetItems.Category.ACTIVE: 0}
	for item in PetItems.CATALOG:
		check(counts.has(item.category), "%s has one of three categories" % item.id)
		counts[item.category] += 1
	check(counts.values() == [10, 9, 3], "Expanded catalog has ten global, nine pup-specific and three active items")
	check(run.acquire_item(PetItems.find_item("biscuit")), "Global passive is collected")
	check(is_equal_approx(selected._multiplier("damage"), 1.5) and is_equal_approx(other._multiplier("damage"), 1.5), "Global damage applies to all dogs")
	run.acquire_item(PetItems.find_item("squeaker"))
	run.acquire_item(PetItems.find_item("tennis"))
	run.acquire_item(PetItems.find_item("bowl"))
	check(is_equal_approx(selected._multiplier("fire_rate"), 0.82) and selected._bonus("extra_shots") == 1 and selected.get_magazine_size() == 42, "Selected dog receives its passives")
	check(is_equal_approx(other._multiplier("fire_rate"), 1.0) and other._bonus("extra_shots") == 0 and other.get_magazine_size() == 30, "Unselected dogs receive no pup-specific benefits")
	check(run.get_stat_bonus("ammo") == 0 and run.get_stat_multiplier("fire_rate") == 1.0, "Player-wide queries exclude pup-specific modifiers")
	var replacement := Gun.new()
	replacement.stats = selected.stats.duplicate()
	var original: Gun = inventory.swap_current_gun(replacement)
	check(is_equal_approx(replacement._multiplier("damage"), 1.5) and is_equal_approx(replacement._multiplier("fire_rate"), 1.0) and replacement.get_magazine_size() == 30, "Same type and slot do not inherit another dog's passives")
	var detached: Gun = inventory.swap_current_gun(original)
	check(is_equal_approx(original._multiplier("fire_rate"), 0.82) and original.get_magazine_size() == 42, "Repicking the identical dog retains its passives")
	detached.free()
	inventory.current_gun_index = -1
	var prior_count: int = run.run_modifiers.size()
	check(not run.acquire_item(PetItems.find_item("tag")) and run.run_modifiers.size() == prior_count, "A pup-specific item refuses acquisition without an equipped dog")
	inventory.switch_to_weapon(0)
	run.add_bones(30)
	check(run.spend_bones(15) and run.bones == 15 and not run.spend_bones(16) and not run.spend_bones(-1), "Currency has exact successful spending and rejects invalid purchases")
	run.add_bones(-50)
	check(run.bones == 15, "Negative currency addition cannot remove bones")
	run.acquire_item(PetItems.find_item("med_bowl"))
	check(not run.activate_item() and run.active_cooldown == 0.0, "Healing at full health does not consume cooldown")
	run.player.current_health = 50
	check(run.activate_item() and run.player.current_health == 80 and run.active_cooldown_rooms == 1, "First Aid heals and requires one room clear")
	check(not run.activate_item(), "Room cooldown prevents consecutive activations")
	run.acquire_item(PetItems.find_item("leash"))
	check(run.active_item.id == "leash" and run.run_modifiers.size() == prior_count and not run.activate_item(), "An active swap preserves the shared room cooldown")
	game.pause_game()
	run._tick_inventory(25.0)
	check(run.active_cooldown_rooms == 1, "Pause preserves room cooldown")
	game.resume_game()
	run._tick_inventory(100.0)
	check(run.active_cooldown_rooms == 1, "Time cannot recharge a room-based active")
	run.recharge_active_from_room()
	check(run.activate_item() and is_instance_valid(run.walkies_companion) and run.active_cooldown_rooms == 4, "Walkies sends the selected gun out and starts four-room recovery")
	run.walkies_companion._process(12.1)
	check(not is_instance_valid(run.walkies_companion) and not selected.get_meta("on_walkies", false), "Walkies returns the original dog after twelve seconds")
	var keys_before_consumable: int = run.keys
	run.acquire_item(PetItems.find_item("bomb"))
	run.acquire_item(PetItems.find_item("key"))
	check(run.bombs == 1 and run.keys == keys_before_consumable + 1 and run.active_item.id == "leash", "Consumables increment counters and preserve the active slot")
	for i in range(4):
		run.recharge_active_from_room()
	run.acquire_item(PetItems.find_item("howl_horn"))
	var host: Node3D = run.generator.get_start_room()
	var local_enemy := Enemy4D.new()
	local_enemy.max_health = 1000
	local_enemy.initial_w = host.position_4d.w
	local_enemy.set_meta("encounter_room", host.room_id)
	host.add_child(local_enemy)
	local_enemy.global_position = run.player.global_position
	local_enemy.set_physics_process(false)
	var remote_enemy := Enemy4D.new()
	remote_enemy.max_health = 1000
	remote_enemy.initial_w = host.position_4d.w + 100.0
	remote_enemy.set_meta("encounter_room", 1)
	host.add_child(remote_enemy)
	remote_enemy.global_position = run.player.global_position
	remote_enemy.set_physics_process(false)
	check(run.activate_item() and local_enemy.current_health < 1000 and remote_enemy.current_health == 1000, "Howl affects nearby enemies without crossing rooms or W slices")
	check(host.get_node_or_null("HowlPulse") != null, "Howl creates visible activation feedback")
	local_enemy.queue_free()
	remote_enemy.queue_free()
	await process_frame
	await _test_real_enemy_bones(run)
	await run.start_new_run()
	run.player.set_physics_process(false)
	check(run.bones == 0 and run.bombs == 0 and run.keys == 1 and run.active_item.is_empty() and run.run_modifiers.is_empty() and run.active_cooldown == 0.0, "A new run resets inventory and gives one starting key")
	if failures.is_empty():
		print("ITEM FAMILIES PASSED: catalog, exact dog identity, currency, cooldown, active swapping, heal, magnet, howl, consumables, real enemy bone drops and collection, reset")
	quit(0 if failures.is_empty() else 1)

func _test_real_enemy_bones(run: Node) -> void:
	var room: Node3D
	for candidate in run.generator.rooms:
		if candidate.room_id != 0 and candidate.room_type == LevelGenerator.ROOM_NORMAL:
			room = candidate
			break
	check(room != null, "Live bone test has an unvisited native encounter room")
	if room == null:
		return
	# The actual controller, generator, run, enemies and pickups keep processing.
	# Place the fixture near the room's bottom, then let normal gravity settle it.
	run.player.global_position = room.global_position + Vector3.DOWN * (room.radius - 2.0)
	run.player.velocity = Vector3.ZERO
	run.player.current_gravity_up = Vector3.UP
	run.player.sphere_facing = Vector3.FORWARD
	run.player.global_basis = Basis.IDENTITY
	run.player.set_physics_process(true)
	run.generator.set_process(true)
	run.set_process(true)
	run.generator.set_active_room(room.room_id)
	await physics_frame
	await physics_frame
	var victim: Enemy4D
	for enemy in get_nodes_in_group("enemies"):
		if enemy.get_meta("encounter_room", -1) == room.room_id:
			victim = enemy
			break
	check(victim != null and run.player.is_physics_processing() and run.is_processing(), "Bone test exercises a native enemy with live player/run physics")
	if victim == null:
		return
	victim.set_position_4d(Vector4D.from_vector3(run.player.global_position + run.player.global_basis.x * 2.5, room.position_4d.w))
	var wallet: int = run.bones
	victim.take_damage(10000, GunTypes.Type.EXPLOSIVE)
	var native_drops := _room_bones(room.room_id)
	check(not native_drops.is_empty() and victim.has_meta("bones_dropped"), "A real native enemy kill creates physical bone nodes synchronously")
	var native_value := 0
	for bone in native_drops:
		native_value += bone.amount
		check(bone.get_parent() == room and bone.room_id == run.current_room_id and is_equal_approx(room.position_4d.w, run.player.position_4d.w), "Native drops belong to the current room and W layer")
	victim.take_damage(10000, GunTypes.Type.EXPLOSIVE)
	check(_room_bones(room.room_id).size() == native_drops.size(), "Repeated damage on a dead enemy cannot duplicate bone drops")
	await physics_frame
	for bone in native_drops:
		if is_instance_valid(bone):
			check(bone.visible and RoomEconomy.room_active(run, room), "Native bone nodes remain visible and active during real physics")
	for frame in range(400):
		await physics_frame
		if run.bones >= wallet + native_value:
			break
	check(native_value > 0 and run.bones == wallet + native_value, "Live bone attraction eventually credits the native kill's currency")
	# An external enemy can be killed immediately by a projectile or debug kill,
	# before RunManager gets another process tick. It must already have a hook.
	var immediate := Enemy4D.new()
	immediate.configure_archetype(Enemy4D.Archetype.GRUNT)
	immediate.initial_w = room.position_4d.w
	immediate.set_meta("encounter_room", room.room_id)
	room.add_child(immediate)
	immediate.set_position_4d(Vector4D.from_vector3(run.player.global_position + run.player.global_basis.x * 2.5, room.position_4d.w))
	var before_immediate: int = _room_bones(room.room_id).size()
	immediate.take_damage(10000, GunTypes.Type.EXPLOSIVE)
	var immediate_drops := _room_bones(room.room_id)
	check(immediate_drops.size() > before_immediate and immediate.has_meta("bones_dropped"), "An enemy killed before the next run tick still drops bones")
	var immediate_value := 0
	for bone in immediate_drops:
		immediate_value += bone.amount
		check(bone.get_parent() == room and bone.room_id == room.room_id, "Immediate external drops use their actual owning room")
	for frame in range(400):
		await physics_frame
		if run.bones >= wallet + native_value + immediate_value:
			break
	check(immediate_value > 0 and run.bones == wallet + native_value + immediate_value, "Immediate external kill currency is collected by live physics")

func _room_bones(room_id: int) -> Array:
	var result: Array = []
	for bone in get_nodes_in_group("bone_pickups"):
		if not bone.is_queued_for_deletion() and bone.room_id == room_id:
			result.append(bone)
	return result
