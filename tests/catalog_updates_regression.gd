extends SceneTree

var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("_run")
func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		push_error(label)

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
	check(not run.loading, "Catalog test run loads")
	if run.loading:
		quit(1)
		return
	run.set_process(false)
	run.generator.set_process(false)
	run.player.set_physics_process(false)
	var gun: Gun = run.player.weapon_manager.get_current_gun()
	var other: Gun = run.player.weapon_manager.guns[1]
	check(gun.stats.flavor_text == "Mappo Blappo Holiday Inn", "Edited Mappo flavor reaches the gun")
	for id in ["biscuit", "zoomies", "squeaker", "cone", "flagella", "kibble", "tag", "howl_horn", "med_bowl", "magnet", "leash"]:
		var visual := RoomEconomy.make_model(id, 1.0)
		check(not visual.find_children("*", "MeshInstance3D", true, false).is_empty(), "Updated model loads: " + id)
		visual.free()
	run.acquire_item(PetItems.find_item("biscuit"))
	check(is_equal_approx(run.get_current_damage(), 67.5), "Treat multiplies actual Mappo damage by 1.5")
	for i in range(13):
		run.acquire_item(PetItems.find_item("tennis"))
	for i in range(2):
		run.acquire_item(PetItems.find_item("flagella"))
	run.acquire_item(PetItems.find_item("tag"))
	run.acquire_item(PetItems.find_item("tag"))
	check(is_equal_approx(gun._bonus("crit_chance"), 0.199), "Repeated Glasses bonuses diminish by 0.99 per copy")
	check(other._bonus("extra_shots") == 0 and other._bonus_count("flagella") == 0, "Visual upgrades bind to the individual dog")
	var attach: Node = gun.get_node("ItemAttachments")
	check(attach.find_children("MouthBall_*", "Node3D", false, false).size() == 13, "All stacked balls are visible in the dog's mouth")
	gun.stats.crit_chance = 0.0
	gun.can_fire = true
	gun.fire(run.player.global_position, Vector3.UP, run.player.position_4d.w)
	var shots := get_nodes_in_group("projectiles")
	check(shots.size() == 14, "Extra projectiles are uncapped beyond the old limit of twelve")
	for shot in shots:
		check(shot.get_node("Flagella").get_child_count() == 2, "Each shot has one animated flagellum per collected item")
		check(is_equal_approx(shot.speed, 54.08), "Flagella speed modifiers stack on spawned shots")
		shot.free()
	for i in range(2):
		run.acquire_item(PetItems.find_item("spring"))
		run.acquire_item(PetItems.find_item("cone"))
	check(run.player.get_node("StackedCones").get_child_count() == 2, "Player cones stack above the player")
	check(run.player.get_node("StackedCones").get_child(0).position.y > run.player.camera.position.y, "Stacked hats stay above the first-person camera")
	check(gun.get_node("ItemAttachments").find_children("SpringNeck_*", "Node3D", false, false).size() == 2 and is_equal_approx(gun.mascot_model._neck_extension, 0.36), "Spring collars visibly extend Mappo's neck")
	check(other.get_node("ItemAttachments").find_children("SpringNeck_*", "Node3D", false, false).size() == 2, "Global collars appear on every equipped dog")
	# Exact tier boundary uses a fixture modifier; acquisition diminishing is tested above.
	run.run_modifiers.clear()
	run.run_modifiers.append({"id":"crit_fixture", "stat":"crit_chance", "amount":1.1, "category":PetItems.Category.DOG_INCLUSIVE, "gun_id":gun.get_instance_id()})
	check(gun.roll_crit_tiers(0.05) == 2 and gun.roll_crit_tiers(0.5) == 1, "110% crit guarantees X with ten-percent chance of X squared")
	run.run_modifiers.clear()
	run.acquire_item(PetItems.find_item("magnet"))
	check(run.active_item.is_empty() and is_equal_approx(run.get_bone_damage(), 18.0), "Cactus is a passive giving bones 40% of current shot damage")
	var host: Node3D = run.generator.get_start_room()
	var enemy := Enemy4D.new()
	enemy.max_health = 1000
	enemy.initial_w = host.position_4d.w
	enemy.set_meta("encounter_room", host.room_id)
	host.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.gun_stats.gun_type = GunTypes.Type.EXPLOSIVE
	enemy.enemy_type = GunTypes.Type.EXPLOSIVE
	enemy.global_position = run.player.global_position + Vector3.RIGHT
	var bone := BonePickup.new()
	bone.configure(run, host, 1, 0)
	host.add_child(bone)
	bone.global_position = enemy.global_position
	bone._tick_spikes()
	check(enemy.current_health == 982 and bone.get_node_or_null("CactusSpikes") == null and is_instance_valid(bone._spikes), "Spiky pickup damages a nearby enemy and displays cactus spikes")
	bone._tick_spikes()
	check(enemy.current_health == 982, "A bone cannot damage the same enemy repeatedly")
	run.acquire_item(PetItems.find_item("howl_horn"))
	check(run.activate_item() and enemy.stunned_timer > 0 and enemy.get_node_or_null("StunStars") != null, "Sound Stunner actually stuns and shows orbiting stars")
	check(run.active_cooldown_rooms == 2, "Sound Stunner starts two-room recovery")
	run._tick_inventory(10000.0)
	check(run.active_cooldown_rooms == 2, "Time does not recharge room-based actives")
	var combat_room: Node3D = run.generator.rooms[1]
	run.room_states[combat_room.room_id] = {"remaining":0,"cleared":false,"combat_started":true}
	run._clear_room(combat_room.room_id)
	check(run.active_cooldown_rooms == 1, "A new combat clear recharges exactly one room")
	run._clear_room(combat_room.room_id)
	check(run.active_cooldown_rooms == 1, "The same room cannot recharge twice")
	run.recharge_active_from_room()
	run.acquire_item(PetItems.find_item("leash"))
	check(run.activate_item() and gun.get_meta("on_walkies", false) and run.player.weapon_manager.get_current_gun() == other, "Walkies uses the real gun and equips a second dog")
	var companion: Node3D = run.walkies_companion
	gun.can_fire = true
	gun.current_ammo = 10
	companion._process(0.1)
	check(gun.current_ammo == 9, "Walking dog independently fires at a same-room enemy")
	companion._process(12.1)
	check(gun.get_parent() == run.player.weapon_manager.gun_holder and not gun.get_meta("on_walkies", false) and run.active_cooldown_rooms == 4, "Walkies returns the same dog without clearing recharge")
	bone.free()
	enemy.queue_free()
	await process_frame
	print("CATALOG UPDATES: %d failures; models, stacked attachments, uncapped multishot, flagella, crit tiers, spiky bones, stun, room recharge and companion fire" % failures.size())
	quit(0 if failures.is_empty() else 1)
