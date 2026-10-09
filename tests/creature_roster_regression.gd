extends SceneTree

var failures: Array[String] = []
var level: Node
var run: Node
var ui: Node

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
		push_error(description)

func _run() -> void:
	_test_catalogs_and_random_types()
	if not failures.is_empty():
		quit(1)
		return
	root.get_node("GameManager").run_seed = 73921
	level = load("res://scenes/levels/procedural_level.tscn").instantiate()
	level.get_node("LevelGenerator").enable_decorations = false
	root.add_child(level)
	current_scene = level
	run = level.get_node("RunManager")
	ui = level.get_node("RunUI")
	for frame in range(180):
		await process_frame
		if not run.loading:
			break
	check(not run.loading, "Creature test loads the native gameplay level")
	if run.loading:
		quit(1)
		return
	run.set_process(false)
	run.generator.set_process(false)
	run.player.set_physics_process(false)
	run.player.set_meta("god_mode", true)
	await _test_enemy_visuals_and_carried_stats()
	await _test_native_death_drops_and_pickups()
	print("CREATURE ROSTER: %d failures; all 40 models, seeded breed/type rolls, dolphin roles, carried stats, death loot, room/W isolation and manual inventory swaps" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _test_catalogs_and_random_types() -> void:
	check(DogBreeds.CATALOG.size() == 20, "There are twenty unusual dog breeds")
	check(DolphinCatalog.CATALOG.size() == 20, "There are twenty dolphin enemies")
	var dog_ids: Dictionary = {}
	var dog_models: Dictionary = {}
	var dolphin_ids: Dictionary = {}
	var dolphin_models: Dictionary = {}
	for definition in DogBreeds.CATALOG:
		var id := str(definition.id)
		check(not dog_ids.has(id), "Dog breed has a unique ID: " + id)
		dog_ids[id] = true
		check(DogBreeds.get_definition(id).name == definition.name, "Dog definition resolves by ID: " + id)
		var path := DogBreeds.model_path(id)
		dog_models[FileAccess.get_sha256(path)] = true
		_validate_model(path, true)
		var rng := RandomNumberGenerator.new()
		var repeat := RandomNumberGenerator.new()
		rng.seed = 104729
		repeat.seed = rng.seed
		var seen_types: Dictionary = {}
		for draw in range(128):
			var stats := DogBreeds.create_stats(rng, id, GunTypes.Rarity.EPIC)
			var again := DogBreeds.create_stats(repeat, id, GunTypes.Rarity.EPIC)
			check(stats.breed_id == id and stats.rarity == GunTypes.Rarity.EPIC, "Breed and requested rarity survive generation: " + id)
			check(stats.gun_type >= 0 and stats.gun_type <= GunTypes.Type.ACCELERATING, "Generated type belongs to the four supported types")
			check(_stats_identity(stats) == _stats_identity(again), "Seeded generation reproduces the same individual gun")
			seen_types[stats.gun_type] = true
		check(seen_types.size() == 4, "Every breed can roll every gun type: " + id)
	for definition in DolphinCatalog.CATALOG:
		var id := str(definition.id)
		check(not dolphin_ids.has(id), "Dolphin has a unique ID: " + id)
		dolphin_ids[id] = true
		check(DolphinCatalog.get_definition(id).name == definition.name, "Dolphin definition resolves by ID: " + id)
		var path := DolphinCatalog.model_path(id)
		dolphin_models[FileAccess.get_sha256(path)] = true
		_validate_model(path, false)
	check(dog_models.size() == 20, "All twenty breed models have distinct asset contents")
	check(dolphin_models.size() == 20, "All twenty dolphin models have distinct asset contents")
	var rng := RandomNumberGenerator.new()
	rng.seed = 271828
	for role in range(5):
		var choices := DolphinCatalog.for_archetype(role)
		check(choices.size() == 4, "Each combat role has four dolphin variants")
		var selected: Dictionary = {}
		for draw in range(64):
			var definition := DolphinCatalog.pick_for_archetype(role, rng)
			check(int(definition.archetype) == role, "Dolphin selection preserves the requested combat role")
			selected[definition.id] = true
		check(selected.size() == 4, "The seeded encounter selector can choose every dolphin in a role")

func _validate_model(path: String, dog: bool) -> void:
	check(ResourceLoader.exists(path), "Imported creature model exists: " + path)
	if not ResourceLoader.exists(path):
		return
	var packed = load(path)
	check(packed is PackedScene, "Creature model is a usable scene: " + path)
	if not packed is PackedScene:
		return
	var model: Node3D = packed.instantiate()
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	check(not meshes.is_empty(), "Creature asset has actual meshes: " + path)
	var triangles := 0
	for instance in meshes:
		if not instance.mesh:
			continue
		for surface in range(instance.mesh.get_surface_count()):
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var indices = arrays[Mesh.ARRAY_INDEX]
			triangles += int(indices.size() / 3) if indices != null and indices.size() > 0 else int(arrays[Mesh.ARRAY_VERTEX].size() / 3)
	check(triangles > 0 and triangles <= 6000, "Creature model remains low poly: %s (%d triangles)" % [path, triangles])
	if dog:
		check(model.find_child("HeadRoot", true, false) != null, "Breed model has a movable head for neck upgrades: " + path)
		for anchor in ["MouthAnchor", "GlassesAnchor", "CollarAnchor"]:
			check(model.find_child(anchor, true, false) != null, "Breed model includes its attachment anchor: " + anchor)
	model.free()

func _stats_identity(stats: GunStats) -> Array:
	return [stats.breed_id, stats.gun_name, stats.gun_type, stats.rarity, stats.base_damage, stats.fire_rate, stats.projectile_speed, stats.max_ammo]

func _test_enemy_visuals_and_carried_stats() -> void:
	var host: Node3D = run.generator.get_start_room()
	var rng := RandomNumberGenerator.new()
	rng.seed = 32452843
	for definition in DolphinCatalog.CATALOG:
		var enemy := Enemy4D.new()
		enemy.configure_dolphin(str(definition.id), 1.0, rng)
		enemy.enable_4d_mode = false
		enemy.initial_w = host.position_4d.w
		enemy.set_meta("encounter_room", host.room_id)
		host.add_child(enemy)
		enemy.set_physics_process(false)
		check(enemy.dolphin_id == definition.id and enemy.display_name == definition.name, "Configured native enemy retains its dolphin identity")
		check(enemy.archetype == int(definition.archetype) and enemy.current_health > 0, "Dolphin variant spawns with the correct combat role and health")
		check(enemy.get_node_or_null("MeshInstance3D/DolphinModel") != null, "Native enemy displays the imported dolphin model")
		check(enemy.get_node_or_null("GunMesh/CarriedDog") != null, "Native enemy visibly carries its dog gun")
		check(not DogBreeds.get_definition(enemy.gun_stats.breed_id).is_empty(), "Enemy carries one of the twenty real breed guns")
		check(enemy._attack_stats != enemy.gun_stats and enemy._attack_stats.rarity == GunTypes.Rarity.POOR, "Enemy attacks use a separate combat tuning resource")
		var original := _stats_identity(enemy.gun_stats)
		if enemy.is_boss():
			enemy.take_damage(roundi(enemy.max_health * 0.6), enemy.enemy_type)
			check(enemy.boss_phase == 2, "A dolphin boss still transitions into its second phase")
			enemy.target = run.player
			enemy._fire_at_target()
			enemy._fire_at_target()
			check(_stats_identity(enemy.gun_stats) == original, "Boss attack pattern changes never mutate the droppable gun")
		enemy.queue_free()
	await process_frame
	for projectile in get_nodes_in_group("projectiles"):
		projectile.queue_free()
	await process_frame

func _make_enemy(room: Node3D, seed_value: int = 982451653) -> Enemy4D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var enemy := Enemy4D.new()
	enemy.configure_dolphin("reef_scout", 1.0, rng)
	enemy.initial_w = room.position_4d.w
	enemy.set_meta("encounter_room", room.room_id)
	enemy.position = Vector3.DOWN * (room.radius - 1.2)
	room.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy

func _test_native_death_drops_and_pickups() -> void:
	var room: Node3D = run.generator.get_start_room()
	check(is_equal_approx(run.gun_drop_chance, 0.05), "Default dog-gun loot chance is five percent")
	# Deterministic boundary fixtures prove rarity without a flaky sample count.
	var below := _make_enemy(room)
	var boundary := _make_enemy(room)
	var dropped: DogGunPickup = run.try_drop_enemy_gun(below, room, 0.049999)
	check(is_instance_valid(dropped), "A roll below five percent drops the carried gun")
	check(run.try_drop_enemy_gun(boundary, room, 0.05) == null, "A roll at or above the rarity boundary drops no gun")
	check(run.try_drop_enemy_gun(below, room, 0.0) == null, "A second request cannot duplicate the same enemy's loot")
	if is_instance_valid(dropped):
		dropped.queue_free()
	below.queue_free()
	boundary.queue_free()
	await process_frame

	run.gun_drop_chance = 0.0
	var unlucky := _make_enemy(room)
	var previous_count := get_nodes_in_group("dog_gun_pickups").size()
	unlucky.take_damage(10000, unlucky.enemy_type)
	check(get_nodes_in_group("dog_gun_pickups").size() == previous_count, "A zero-percent native death drops no dog gun")
	run.gun_drop_chance = 1.0
	var victim := _make_enemy(room, 49979687)
	var carried := _stats_identity(victim.gun_stats)
	victim.take_damage(10000, victim.enemy_type)
	check(get_nodes_in_group("dog_gun_pickups").size() == previous_count + 1, "A real same-frame death signal spawns one physical dog-gun pickup")
	victim.take_damage(10000, victim.enemy_type)
	check(get_nodes_in_group("dog_gun_pickups").size() == previous_count + 1, "Repeated lethal hits cannot spawn additional dog-gun loot")
	var candidates := get_nodes_in_group("dog_gun_pickups")
	if candidates.size() != previous_count + 1:
		return
	var pickup: DogGunPickup = candidates.back()
	check(pickup.get_parent() == room and pickup.room_id == room.room_id, "Death loot stays in its actual owning room")
	check(_stats_identity(pickup.gun.stats) == carried, "Loot preserves the enemy's breed, type, rarity and player gun stats")
	check(pickup.requires_interaction(), "Dog-gun loot requires a deliberate manual pickup")
	var displayed_bounds := RoomEconomy.model_bounds(pickup.gun, pickup.gun.transform)
	check(is_equal_approx(displayed_bounds.position.y, 0.95), "A breed's held offset cannot bury its dropped model inside the pedestal")
	var inventory: WeaponManager = run.player.weapon_manager
	var previous_gun: Gun = inventory.get_current_gun()
	previous_gun.current_ammo = 7
	run.acquire_item(PetItems.find_item("flagella"))
	var modifier_count: int = previous_gun._bonus_count("flagella")
	var incoming: Gun = pickup.gun
	incoming.current_ammo = 11
	_place_near_pickup(pickup)
	pickup._process(0.0)
	check(inventory.get_current_gun() == previous_gun and pickup.gun == incoming, "Walking over a dropped dog does not silently replace the held gun")
	var correct_room: int = run.current_room_id
	run.current_room_id = correct_room + 999
	check(not pickup.interact(run) and pickup.get_interaction_text(run).is_empty(), "A pickup cannot be collected through another room")
	run.current_room_id = correct_room
	var correct_w: float = run.player.position_4d.w
	run.player.position_4d.w += 10.0
	check(not pickup.interact(run) and pickup.get_interaction_text(run).is_empty(), "An overlapping pickup cannot be collected through another W layer")
	run.player.position_4d.w = correct_w
	ui._process(0.0)
	check(ui._find_interactable(true) == pickup, "The native HUD can target dog-gun loot from normal camera height")
	await process_frame
	ui._process(0.0)
	check(ui.item_details.size.y >= ui.item_details.get_combined_minimum_size().y, "The dog pickup HUD panel contains its wrapped effect and flavor text")
	_key(KEY_F, true)
	await process_frame
	_key(KEY_F, false)
	await process_frame
	check(inventory.get_current_gun() == incoming and pickup.gun == previous_gun, "A real F key event swaps a full inventory and leaves the old gun on the pedestal")
	check(previous_gun.current_ammo == 7 and incoming.current_ammo == 11, "Swapping retains both individual guns' ammunition")
	check(previous_gun._bonus_count("flagella") == modifier_count and incoming._bonus_count("flagella") == 0, "Selected-dog upgrades remain bound to the original gun object")
	_test_breed_attachments(incoming, previous_gun)
	check(pickup.interact(run), "The previous held dog can be picked back up")
	check(inventory.get_current_gun() == previous_gun and pickup.gun == incoming and previous_gun.current_ammo == 7, "Swapping back restores the exact original gun and ammo")
	check(previous_gun._bonus_count("flagella") == modifier_count, "Swapping back preserves original item modifier identity")
	# Empty slots collect without losing an existing gun or leaving phantom stock.
	var removed: Gun = inventory.drop_current_gun()
	removed.queue_free()
	check(pickup.interact(run) and not pickup.available and inventory.guns.has(incoming), "An empty inventory slot consumes the pickup without a replacement pedestal")
	await process_frame

func _test_breed_attachments(gun: Gun, other: Gun) -> void:
	check(is_instance_valid(gun.breed_model), "Collected breed gun retains its imported visual")
	if not is_instance_valid(gun.breed_model):
		return
	var body := gun.breed_model.find_child("BodyMesh", true, false) as Node3D
	if not body:
		body = gun.breed_model.find_child("Body", true, false) as Node3D
	check(is_instance_valid(body), "Breed model has a body separate from its movable head")
	var body_before := gun.to_local(body.global_position) if body else Vector3.ZERO
	var mouth_before := gun.get_breed_anchor("MouthAnchor")
	run.acquire_item(PetItems.find_item("spring"))
	run.acquire_item(PetItems.find_item("spring"))
	var raised := gun.get_breed_anchor("MouthAnchor") - mouth_before
	check(raised.is_equal_approx(Vector3.UP * 0.12), "Two spring collars extend the collected breed's neck by the held-gun amount")
	check(not body or gun.to_local(body.global_position).is_equal_approx(body_before), "Spring upgrades keep the breed's body and feet fixed")
	run.acquire_item(PetItems.find_item("tennis"))
	run.acquire_item(PetItems.find_item("tag"))
	var attachments := gun.get_node("ItemAttachments")
	check(attachments.get_node_or_null("MouthBall_0") != null and attachments.get_node_or_null("Glasses_0") != null, "Breed anchors support visible mouth balls and glasses")
	check(attachments.find_children("SpringNeck_*", "Node3D", false, false).size() == 2, "Both global spring collars are visible on the new breed")
	check(gun._bonus_count("tennis") == 1 and gun._bonus_count("tag") == 1 and other._bonus_count("tennis") == 0 and other._bonus_count("tag") == 0, "New breed's selected-dog upgrades stay bound to that dog")

func _place_near_pickup(pickup: DogGunPickup) -> void:
	var room: Node3D = pickup.room
	var outward := (pickup.global_position - room.global_position).normalized()
	var up := -outward
	var front: Vector3 = -pickup.global_basis.z
	run.player.global_position = pickup.global_position + up * 2.0 + front * 2.0
	run.player.global_basis = Basis.looking_at(-front, up)
	run.player.current_gravity_up = up
	run.player.velocity = Vector3.ZERO
	run.player.position_4d = Vector4D.from_vector3(run.player.global_position, room.position_4d.w)
	run.current_room_id = room.room_id
	run.generator.set_active_room(room.room_id)
	run.player.camera.rotation = Vector3.ZERO
	run.player.camera.look_at(pickup.get_interaction_position(), up)

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
