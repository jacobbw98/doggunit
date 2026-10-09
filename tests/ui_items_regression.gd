extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
		push_error(description)

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var game: Node = root.get_node("GameManager")
	game.run_seed = 20260929
	var packed: PackedScene = load("res://scenes/levels/procedural_level.tscn")
	var level := packed.instantiate()
	level.get_node("LevelGenerator").enable_decorations = false
	root.add_child(level)
	current_scene = level
	var run: Node = level.get_node("RunManager")
	for frame in range(100):
		await process_frame
		if not run.loading:
			break
	run.player.set_physics_process(false)
	run.player.set_meta("god_mode", true)
	run.generator.set_process(false)
	run.set_process(false)
	var ui: Node = level.get_node("RunUI")
	var map: Control
	for child in ui.root.get_children():
		if child.get_script() and child.get_script().resource_path == "res://scripts/player/room_minimap.gd":
			map = child
	check(map != null, "Gameplay contains minimap")
	map._process(0.0)
	check(map.get_map_positions().keys() == [0], "Start map reveals only the entered starting room")
	var secret_id := -1
	for id in run.generator.room_graph:
		if run.generator.room_graph[id].type == 6:
			secret_id = id
			run.generator.room_graph[id].discovered = true
	map._process(0.0)
	check(not map.get_map_positions().has(secret_id), "Sniffing a secret doorway does not reveal its unentered room on map")
	var neighbor: int = run.generator.room_graph[0].connections[0]
	run.current_room_id = neighbor
	map._process(0.0)
	check(map.get_map_positions().size() == 2 and map.get_map_positions().has(neighbor), "Entering another room reveals that room only")
	run.current_room_id = 0
	map._process(0.0)
	check(map.get_map_positions().size() == 2, "Returning preserves explored rooms")
	check(map.get_global_rect().end.x <= root.size.x and map.get_global_rect().position.x >= 0, "Minimap stays inside the right viewport edge")
	run.generator.seed_value += 1
	map._process(0.0)
	check(map.get_map_positions().size() == 1, "New floor clears the old explored map")

	game.pause_game()
	ui._show_pause()
	check(paused and ui.overlay.visible and ui.modal == "pause", "Pause menu suspends gameplay")
	ui._resume()
	check(not paused and not ui.overlay.visible, "Resume restores gameplay")
	var item_room: Node3D
	for room in run.generator.rooms:
		if room.room_type == LevelGenerator.ROOM_ITEM:
			item_room = room
			break
	check(item_room != null, "Generated floor contains an item room")
	# This fixture tests a fresh choice; active swaps leaving a returned pedestal
	# are covered separately by economy_regression.
	run.active_item.clear()
	run.player.global_position = item_room.get_spawn_position()
	run.generator.set_active_room(item_room.room_id)
	var choices := _room_pedestals(item_room.room_id)
	check(choices.size() == 2 and not paused and ui.modal.is_empty(), "Item room presents two world pedestals without a reward modal")
	var pickup: Node3D = choices[0]
	run.player.global_position = pickup.global_position
	check(pickup.interact(run), "An item can be collected from its pedestal")
	await process_frame
	check(_room_pedestals(item_room.room_id).is_empty(), "Choosing one item removes the unchosen pedestal")
	run._on_room_entered(item_room)
	check(_room_pedestals(item_room.room_id).is_empty(), "A visited item room cannot regenerate its choices")
	run.run_modifiers.clear()
	run.active_item.clear()
	run._apply_player_modifiers()
	var gun: Node = run.player.weapon_manager.get_current_gun()
	var base_speed: float = run._base_player_stats.walk
	var family_counts := {PetItems.Category.GLOBAL_PASSIVE: 0, PetItems.Category.DOG_INCLUSIVE: 0, PetItems.Category.ACTIVE: 0}
	for item in PetItems.CATALOG:
		check(family_counts.has(item.category), "Every catalog item belongs to one of three families")
		family_counts[item.category] += 1
		# This fixture verifies the original passive interactions in isolation;
		# legendary all-stat and new modifier combinations have focused tests.
		if item.kind == "passive" and item.id not in ["boneswarm", "bounce", "homing", "flesh", "tofu", "aminita", "cubensis", "lazer"]:
			run.add_modifier(item)
	check(family_counts[PetItems.Category.GLOBAL_PASSIVE] == 10 and family_counts[PetItems.Category.DOG_INCLUSIVE] == 9 and family_counts[PetItems.Category.ACTIVE] == 3, "Nineteen passives and three actives have explicit families")
	check(run.player.max_health == 125, "Cone increases maximum health")
	check(run.player.walk_speed > base_speed and run.player.jump_velocity > 9.0, "Zoomies and collar affect movement")
	check(is_equal_approx(gun._multiplier("damage"), 1.5), "Damage upgrade reaches equipped gun")
	check(is_equal_approx(gun._multiplier("fire_rate"), 0.82), "Squeaker affects fire cooldown")
	check(is_equal_approx(gun._multiplier("projectile_speed"), 1.3), "Flagella affects projectile speed")
	check(gun.get_magazine_size() == 42, "Water bowl adds magazine capacity")
	check(gun._bonus("extra_shots") == 1 and is_equal_approx(gun._bonus("crit_chance"), 0.1), "Tennis ball and dog tag reach gun modifiers")
	check(run.get_stat_bonus("heal_on_kill") == 3, "Vampire kibble grants kill healing")
	var other: Gun = run.player.weapon_manager.guns[1]
	check(is_equal_approx(other._multiplier("damage"), 1.5), "Global damage applies to every pup")
	check(is_equal_approx(other._multiplier("fire_rate"), 1.0) and other._bonus("extra_shots") == 0 and other.get_magazine_size() == 30, "Dog inclusive passives do not affect other inventory pups")
	run.player.weapon_manager.switch_to_weapon(1)
	check(run.acquire_item(PetItems.find_item("tag")) and is_equal_approx(other._bonus("crit_chance"), 0.1), "Picking up a dog item binds the pup selected at pickup")
	run.player.weapon_manager.switch_to_weapon(0)
	var replacement := Gun.new()
	replacement.stats = gun.stats.duplicate()
	var original: Gun = run.player.weapon_manager.swap_current_gun(replacement)
	check(is_equal_approx(replacement._multiplier("fire_rate"), 1.0) and replacement._bonus("extra_shots") == 0, "Same type in the same slot does not inherit a different pup's items")
	var swapped_out: Gun = run.player.weapon_manager.swap_current_gun(original)
	check(is_equal_approx(original._multiplier("fire_rate"), 0.82) and original._bonus("extra_shots") == 1, "Dropping and repicking the same pup preserves its upgrades")
	swapped_out.free()
	gun.reload()
	gun.can_fire = true
	gun.fire(run.player.global_position, Vector3.UP, run.player.position_4d.w)
	check(get_nodes_in_group("projectiles").size() == 2, "Quantum tennis ball spawns an actual extra shot")
	for shot in get_nodes_in_group("projectiles"):
		check(shot.shooter == run.player, "Player shots identify their shooter for friendly-fire exclusion")
		check(is_equal_approx(shot.speed, 41.6), "Projectile speed is modified in the spawned projectile")
		shot.queue_free()
	check(gun.current_ammo == 41, "Multishot costs one ammo per trigger")
	run.add_bones(25)
	check(run.bones == 25 and run.spend_bones(15) and run.bones == 10, "Bones are accumulated and spent exactly once")
	check(not run.spend_bones(11) and not run.spend_bones(-1) and run.bones == 10, "Insufficient and negative purchases cannot change currency")
	check(run.acquire_item(PetItems.find_item("med_bowl")), "An active item fills the single slot")
	var modifier_count: int = run.run_modifiers.size()
	run.player.current_health = run.player.max_health - 40
	check(run.activate_item() and run.player.current_health == run.player.max_health - 10 and run.active_cooldown_rooms == 1, "First Aid heals and starts room recovery")
	check(not run.activate_item(), "An active cannot be repeated while recovering")
	check(run.acquire_item(PetItems.find_item("leash")) and run.active_item.id == "leash" and run.run_modifiers.size() == modifier_count, "A new active swaps the one slot")
	check(not run.activate_item() and run.active_cooldown_rooms == 1, "Active swapping cannot bypass room recovery")
	run.recharge_active_from_room()
	check(run.activate_item() and is_instance_valid(run.walkies_companion), "Ready leash deploys a real walking dog")
	game.pause_game()
	var cooldown: int = run.active_cooldown_rooms
	var duration: float = run.walkies_companion.remaining
	run.walkies_companion._process(100.0)
	check(run.active_cooldown_rooms == cooldown and run.walkies_companion.remaining == duration, "Pause freezes companion duration and cooldown")
	game.resume_game()
	run.walkies_companion._process(12.1)
	check(not is_instance_valid(run.walkies_companion) and run.active_cooldown_rooms == 4, "Companion returns independently of room recovery")
	var keys_before_consumable: int = run.keys
	check(run.acquire_item(PetItems.find_item("bomb")) and run.acquire_item(PetItems.find_item("key")) and run.bombs == 1 and run.keys == keys_before_consumable + 1 and run.active_item.id == "leash", "Bombs and keys preserve the active slot")
	game.pause_game()
	ui._show_floor_complete()
	check(ui.modal == "floor", "Floor completion screen renders")
	ui._show_end(false)
	check(ui.modal == "end", "Defeat screen renders without modifying persistent records")
	ui._show_end(true)
	check(ui.content.get_child(1).text.contains("GOODEST"), "Victory screen renders")
	paused = false
	if failures.is_empty():
		print("UI / ITEMS PASSED: minimap, pause, pedestal choices, item families, exact pup scope, multishot, currency, active slot and cooldown, consumables, result screens")
	quit(0 if failures.is_empty() else 1)

func _room_pedestals(room_id: int) -> Array:
	var result: Array = []
	for pedestal in get_nodes_in_group("item_pedestals"):
		if not pedestal.is_queued_for_deletion() and pedestal.room_id == room_id:
			result.append(pedestal)
	return result
