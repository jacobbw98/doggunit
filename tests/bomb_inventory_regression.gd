extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	root.get_node("GameManager").run_seed = 73921
	var level: Node = load("res://scenes/levels/procedural_level.tscn").instantiate()
	level.get_node("LevelGenerator").enable_decorations = false
	root.add_child(level)
	current_scene = level
	var run: Node = level.get_node("RunManager")
	for frame in range(180):
		await process_frame
		if not run.loading:
			break
	check(not run.loading, "Run loads before bomb test")
	if run.loading:
		quit(1)
		return
	run.player.set_physics_process(false)
	run.generator.set_process(false)
	run.set_process(false)
	run.player.set_meta("god_mode", true)
	var room: Node3D = run.generator.get_start_room()
	var origin: Vector3 = run.player.global_position + run.player.current_gravity_up * 0.55
	var victim := Enemy4D.new()
	victim.max_health = 1000
	victim.initial_w = room.position_4d.w
	victim.set_meta("encounter_room", room.room_id)
	room.add_child(victim)
	victim.global_position = origin
	victim.set_physics_process(false)
	var different_room := Enemy4D.new()
	different_room.max_health = 1000
	different_room.initial_w = room.position_4d.w + 100.0
	different_room.set_meta("encounter_room", 1)
	room.add_child(different_room)
	different_room.global_position = origin
	different_room.set_physics_process(false)
	check(not run.use_bomb(), "An empty bomb inventory cannot spawn explosives")
	var keys_before_consumable: int = run.keys
	run.acquire_item(PetItems.find_item("bomb"))
	run.acquire_item(PetItems.find_item("key"))
	check(run.bombs == 1 and run.keys == keys_before_consumable + 1 and run.active_item.is_empty(), "Consumables increment counters and leave the active slot free")
	check(run.use_bomb() and run.bombs == 0, "Placing a bomb consumes exactly one bomb")
	var placed: Array = get_nodes_in_group("run_bombs")
	check(placed.size() == 1, "Bomb has a physical world instance")
	if placed.is_empty():
		quit(1)
		return
	var bomb: Node3D = placed[0]
	bomb.set_physics_process(false)
	bomb.global_position = origin
	bomb.velocity = Vector3.ZERO
	var health: int = victim.current_health
	var other_health: int = different_room.current_health
	check(is_equal_approx(bomb.fuse, float(PetItems.find_item("bomb").duration)), "The placed bomb starts with the configured fuse")
	bomb.fuse = 0.01
	bomb._physics_process(0.02)
	check(bomb.detonated, "The timed fuse detonates the bomb")
	check(victim.current_health < health, "The bomb damages nearby enemies in its own room")
	check(different_room.current_health == other_health, "An overlapping enemy in another room/W layer stays unharmed")
	var after_blast: int = victim.current_health
	bomb.detonate()
	check(victim.current_health == after_blast, "Bomb detonation applies damage only once")
	check(run.keys == keys_before_consumable + 1, "Bomb placement and detonation preserve keys")
	var ui: Node = level.get_node("RunUI")
	ui._process(0.0)
	check(ui.currency.text.contains("KEYS  %d" % run.keys) and ui.active_name.text == "Empty slot", "HUD exposes current consumables and the single active slot")
	if failures.is_empty():
		print("BOMB INVENTORY PASSED: stock, fuse, blast damage, room isolation, one detonation, stored keys, HUD")
	quit(0 if failures.is_empty() else 1)
