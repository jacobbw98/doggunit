extends SceneTree

var failures: Array[String] = []
var completion_events: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
		push_error(description)

func _run() -> void:
	# Load after autoload initialization; no end_run calls, so user records stay intact.
	var packed: PackedScene = load("res://scenes/levels/procedural_level.tscn")
	var level: Node = packed.instantiate()
	level.get_node("RunUI").free()
	var generator: Node = level.get_node("LevelGenerator")
	generator.enable_decorations = false
	var game: Node = root.get_node("GameManager")
	game.run_seed = 73921
	root.add_child(level)
	current_scene = level
	var run: Node = level.get_node("RunManager")
	for frame in range(180):
		await process_frame
		if not run.loading:
			break
	check(not run.loading and generator.rooms.size() > 5, "New run generates a complete floor")
	if run.loading:
		quit(1)
		return
	var player: Node = run.player
	player.set_physics_process(false)
	player.set_meta("god_mode", true)
	generator.set_process(false)
	run.set_process(false)
	check(player.weapon_manager.get_gun_count() == 3, "Run starts with exactly three pups")
	var starter: Gun = player.weapon_manager.get_current_gun()
	check(starter.stats.gun_name == "Mappo" and starter.stats.mascot_visual, "Mappo is the equipped default starter")
	check(is_equal_approx(starter.stats.base_damage, 45.0) and is_equal_approx(starter.stats.fire_rate, 0.9), "Mappo starts with heavy, slow shots")
	var heavy_shot := Projectile.create_from_stats(starter.stats, Vector3.ZERO, Vector3.FORWARD, player, 0.0, false)
	check(is_equal_approx(heavy_shot.damage, 45.0), "Mappo's base damage reaches the actual projectile")
	heavy_shot.free()
	var other_starter: Gun = player.weapon_manager.guns[1]
	check(is_equal_approx(other_starter.stats.base_damage, 10.0) and is_equal_approx(other_starter.stats.fire_rate, 0.2), "Other starter pups retain their original balance")
	check(is_instance_valid(starter.mascot_model) and starter.mascot_model.get_child_count() > 0, "Mappo loads the actual reusable 3D model")
	player.weapon_manager.switch_to_weapon(1)
	check(not starter.visible and not player.weapon_manager.get_current_gun().stats.mascot_visual, "Swapping hides Mappo and preserves the other pup's visual")
	player.weapon_manager.switch_to_weapon(0)
	check(starter.visible, "Swapping back restores Mappo")
	check(run.room_states[0].cleared and _room_pedestals(0).is_empty(), "Start room is safe and does not award repeated treats")
	check(run.get_status_text().contains("FLOOR 1"), "Status text can resolve room names at runtime")
	run._give_starting_pups()
	await process_frame
	check(player.weapon_manager.get_gun_count() == 3, "Giving starter pups twice still leaves exactly three inventory slots")
	check(player.weapon_manager.get_current_gun().stats.gun_name == "Mappo", "Restarting restores Mappo as the selected starter")

	var combat_room: Node
	var boss_room: Node
	for room in generator.rooms:
		if room.room_type == 0 and room.room_id != 0 and combat_room == null:
			combat_room = room
		if room.room_type == 1:
			boss_room = room
	player.global_position = combat_room.get_spawn_position()
	generator.set_active_room(combat_room.room_id)
	var enemies: Array = _room_enemies(combat_room.room_id)
	check(enemies.size() == 3 and run.room_states[combat_room.room_id].remaining == 3, "First-floor combat room spawns three varied enemies")
	for enemy in enemies:
		check(is_equal_approx(enemy.position_4d.w, combat_room.position_4d.w), "Spawned enemy starts on its room W slice")
		check(enemy.target == player, "Spawned enemy targets the live player immediately")
		var surface_up: Vector3 = (combat_room.global_position - enemy.global_position).normalized()
		check(enemy.global_basis.y.dot(surface_up) > 0.99, "Enemy spawns upright on its sphere surface")
	var sleeping_room: Node
	for room in generator.rooms:
		if room.room_type == 0 and room.room_id != combat_room.room_id and not generator.get_visible_connections(room.room_id).has(combat_room.room_id):
			sleeping_room = room
			break
	player.global_position = sleeping_room.get_spawn_position()
	generator.set_active_room(sleeping_room.room_id)
	run._sync_encounters()
	for enemy in enemies:
		check(not enemy.visible and enemy.collision_layer == 0 and enemy.process_mode == Node.PROCESS_MODE_DISABLED, "Off-graph sleeping enemies hide and stop colliding")
	player.global_position = combat_room.get_spawn_position()
	generator.set_active_room(combat_room.room_id)
	for enemy in enemies:
		check(enemy.visible and enemy.collision_layer == 4 and enemy.process_mode == Node.PROCESS_MODE_INHERIT, "Returning to a room restores its sleeping enemies")
	for enemy in enemies:
		enemy.take_damage(10000, 0)
	check(run.room_states[combat_room.room_id].cleared and _room_pedestals(combat_room.room_id).size() == 1, "Clearing combat creates one world reward pedestal")
	run._on_room_entered(combat_room)
	check(_room_pedestals(combat_room.room_id).size() == 1, "Re-entering a cleared room does not duplicate its reward")
	run._process(0.016)
	check(not paused, "Room rewards leave gameplay active")
	var pedestal: Node3D = _room_pedestals(combat_room.room_id)[0]
	var collected_item: String = pedestal.item.id
	player.global_position = pedestal.global_position
	check(pedestal.interact(run), "The actual world reward can be collected")
	var collected_count: int = run.run_modifiers.size() + int(not run.active_item.is_empty())
	check(collected_count == 1 and not paused, "Collecting one pedestal grants exactly one item during play")
	run.add_bones(17)
	run.add_consumable("bomb", 2)
	run.add_consumable("key", 1)

	player.global_position = boss_room.get_spawn_position()
	generator.set_active_room(boss_room.room_id)
	var bosses := _room_enemies(boss_room.room_id)
	check(bosses.size() == 1 and bosses[0].is_boss(), "Boss room creates one boss encounter")
	run.floor_completed.connect(func(): completion_events += 1)
	bosses[0].take_damage(10000, 0)
	await process_frame
	check(run.floor_won and not paused and completion_events == 0, "Boss defeat keeps gameplay active so its bones can be collected")
	var post_boss_shop: Node3D
	var post_boss_item_room: Node3D
	for room in generator.rooms:
		if room.room_type == LevelGenerator.ROOM_SHOP:
			post_boss_shop = room
		if room.room_type == LevelGenerator.ROOM_ITEM:
			post_boss_item_room = room
	check(not run.room_states.has(post_boss_shop.room_id) and not run.room_states.has(post_boss_item_room.room_id), "Shop and item room remain unvisited before boss completion")
	player.global_position = post_boss_shop.get_spawn_position()
	generator.set_active_room(post_boss_shop.room_id)
	var shop_stock: int = _room_pedestals(post_boss_shop.room_id).size()
	check(shop_stock >= 1 and shop_stock <= 3 and not paused and completion_events == 0, "An unvisited shop still populates after boss defeat")
	for stock in _room_pedestals(post_boss_shop.room_id):
		check(stock.price == int(stock.item.shop_price), "Post-boss shop stock retains its catalog purchase price")
	run._on_room_entered(post_boss_shop)
	check(_room_pedestals(post_boss_shop.room_id).size() == shop_stock, "Post-boss shop revisit cannot duplicate its stock")
	player.global_position = post_boss_item_room.get_spawn_position()
	generator.set_active_room(post_boss_item_room.room_id)
	check(_room_pedestals(post_boss_item_room.room_id).size() == 2 and not paused, "An unvisited item room still offers two choices after boss defeat")
	player.global_position = boss_room.get_spawn_position()
	generator.set_active_room(boss_room.room_id)
	run.request_floor_exit()
	check(paused and completion_events == 1, "Choosing the boss room exit opens floor completion once")
	run._finish_floor()
	check(completion_events == 1, "Repeated completion calls do not duplicate the floor screen")
	var keys_before_floor: int = run.keys
	var bombs_before_floor: int = run.bombs
	await run.advance_floor()
	player.set_physics_process(false)
	check(run.current_floor == 2 and not run.floor_won and not run.loading and not paused, "Continue generates and starts the second floor")
	check(run.run_modifiers.size() + int(not run.active_item.is_empty()) == 1, "Collected treats persist between floors")
	check((not run.active_item.is_empty() and run.active_item.id == collected_item) or (not run.run_modifiers.is_empty() and run.run_modifiers[0].id == collected_item), "Floor advance retains the specific collected item")
	check(run.bones >= 17 and run.bombs == bombs_before_floor and run.keys == keys_before_floor, "Currency and earned consumables persist between floors")
	check(get_nodes_in_group("item_pedestals").is_empty() and get_nodes_in_group("bone_pickups").is_empty(), "Floor regeneration removes old pedestals and bone drops")
	check(_room_enemies(combat_room.room_id).is_empty() if is_instance_valid(combat_room) else get_nodes_in_group("enemies").is_empty(), "New floor removes previous encounters")
	# Exercise final-floor bounds without writing persistent victory statistics.
	run.current_floor = run.max_floors
	run.floor_won = true
	await run.advance_floor()
	check(run.current_floor == 3, "The run cannot advance beyond three floors")
	run.floor_won = false
	if failures.is_empty():
		print("RUN PROGRESSION PASSED: loadout, room lifecycle, W sleep/wake, rewards, boss, floor advance, cap")
	else:
		print("RUN PROGRESSION FAILED: ", failures)
	quit(0 if failures.is_empty() else 1)

func _room_enemies(room_id: int) -> Array:
	var enemies: Array = []
	for enemy in get_nodes_in_group("enemies"):
		if enemy.get_meta("encounter_room", -1) == room_id and not enemy.is_queued_for_deletion():
			enemies.append(enemy)
	return enemies

func _room_pedestals(room_id: int) -> Array:
	var result: Array = []
	for pedestal in get_nodes_in_group("item_pedestals"):
		if not pedestal.is_queued_for_deletion() and pedestal.room_id == room_id:
			result.append(pedestal)
	return result
