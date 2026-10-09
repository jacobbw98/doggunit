extends SceneTree

# Keep native firing, ammo, timers and reload animation, while recording shots
# instead of running unrelated impact physics in the timing fixtures.
class RecordingGun:
	extends Gun
	var shots := 0
	func _spawn_projectile(_origin: Vector3, _direction: Vector3, _crit: bool, _w: float = 0.0, _tiers: int = 1) -> void:
		shots += 1
	func roll_crit_tiers(_roll: float = -1.0) -> int:
		return 0

var failures: Array[String] = []
var level: Node
var run: Node

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		push_error(label)

func _run() -> void:
	_test_base_magazine_cycles()
	await _test_reload_timing_and_pause()
	root.get_node("GameManager").run_seed = 73921
	level = load("res://scenes/levels/procedural_level.tscn").instantiate()
	level.get_node("RunUI").free()
	level.get_node("LevelGenerator").enable_decorations = false
	root.add_child(level)
	current_scene = level
	run = level.get_node("RunManager")
	for frame in range(180):
		await process_frame
		if not run.loading:
			break
	check(not run.loading, "Item-stack fixture loads native gameplay")
	if run.loading:
		quit(1)
		return
	run.set_process(false)
	run.generator.set_process(false)
	run.player.set_physics_process(false)
	run.player.set_meta("god_mode", true)
	_test_hidden_reload_slot()
	_test_reload_ownership_transfer()
	_test_inactive_freeze_window()
	await process_frame
	_test_health_stacks()
	_test_fungus_stacks()
	_test_swarm_currency()
	await process_frame
	print("RELOAD ITEM STACKS: %d failures; all 23 base profiles and four types, last-shot timing, pause, animations, slot switching, inactive freeze windows, additive health, fungus identity and swarm currency" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _starter_stats(definition: Dictionary, type: int) -> GunStats:
	var stats := GunStats.new()
	stats.gun_name = definition.name
	stats.gun_type = type as GunTypes.Type
	stats.base_damage = definition.damage
	stats.fire_rate = definition.fire_rate
	stats.max_ammo = definition.max_ammo
	stats.projectile_speed = definition.projectile_speed
	if definition.has("reload_seconds"):
		stats.reload_seconds = definition.reload_seconds
	return stats

func _test_inactive_freeze_window() -> void:
	var active_room: Node3D = run.generator.get_room(run.current_room_id)
	var inactive_room: Node3D
	for room in run.generator.rooms:
		if room.room_id != run.current_room_id:
			inactive_room = room
			break
	check(is_instance_valid(inactive_room), "Native freeze-window fixture has an inactive neighboring room")
	if not is_instance_valid(inactive_room):
		return
	var active := Enemy4D.new()
	var inactive := Enemy4D.new()
	for pair in [[active, active_room], [inactive, inactive_room]]:
		var enemy: Enemy4D = pair[0]
		var room: Node3D = pair[1]
		enemy.enable_4d_mode = false
		enemy.initial_w = room.position_4d.w
		enemy.set_meta("encounter_room", room.room_id)
		enemy.position = Vector3.DOWN * (room.radius - 1.2)
		room.add_child(enemy)
		enemy.set_physics_process(false)
		enemy.register_freezing_hit(1.0)
		enemy.frozen_timer = 2.0
	inactive.stunned_timer = 2.0
	run._sync_encounters(0.5)
	check(inactive.process_mode == Node.PROCESS_MODE_DISABLED and inactive.freezing_hit_count == 1 and is_equal_approx(inactive.freezing_hit_window, 0.0), "An inactive enemy retains its chain at exactly half a second despite sleeping AI")
	check(is_equal_approx(active.freezing_hit_window, 0.5) and active.frozen_timer == 2.0 and inactive.frozen_timer == 2.0 and inactive.stunned_timer == 2.0, "Encounter synchronization advances neither active hit windows nor unrelated freeze/stun durations")
	check(inactive.register_freezing_hit(0.015) and inactive.freezing_hit_count == 2 and is_equal_approx(inactive.freezing_hit_window, 0.5), "Another hit refreshes a sleeping enemy's chain and uses its accumulated chance")
	run._sync_encounters(0.49)
	var before_sync: float = inactive.freezing_hit_window
	run._sync_encounters()
	check(is_equal_approx(inactive.freezing_hit_window, before_sync), "A zero-delta synchronization caller cannot advance a sleeping hit window")
	run._sync_encounters(0.02)
	check(inactive.freezing_hit_count == 0 and inactive.freezing_hit_window == 0.0 and inactive.frozen_timer == 2.0 and inactive.stunned_timer == 2.0, "A sleeping target's chance resets after more than half a second while its status durations remain asleep")
	check(not inactive.register_freezing_hit(0.01) and inactive.freezing_hit_count == 1, "The next inactive target hit starts again at one percent")
	active._physics_process(0.25)
	run._sync_encounters(0.25)
	check(is_equal_approx(active.freezing_hit_window, 0.25) and is_equal_approx(active.frozen_timer, 1.75), "Active enemies spend time once in their own physics callback without a second synchronization tick")
	var before_pause: float = inactive.freezing_hit_window
	paused = true
	run._sync_encounters(1.0)
	check(inactive.freezing_hit_window == before_pause and inactive.freezing_hit_count == 1, "Paused synchronization preserves an inactive target's remaining chain")
	paused = false
	run._process(0.51)
	check(inactive.freezing_hit_count == 0 and inactive.freezing_hit_window == 0.0, "The native RunManager processing path forwards elapsed time to inactive freeze windows")
	check(is_equal_approx(active.freezing_hit_window, 0.25) and is_equal_approx(active.frozen_timer, 1.75), "RunManager processing still does not double-tick active enemy timers")
	active.queue_free()
	inactive.queue_free()
	run._sync_combat_locks()

func _test_base_magazine_cycles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1729
	var definitions: Array = PetItems.STARTER_DOGS + DogBreeds.CATALOG
	for definition in definitions:
		for type in range(4):
			var gun := RecordingGun.new()
			gun.stats = _starter_stats(definition, type) if not DogBreeds.get_definition(definition.id).size() else DogBreeds.create_stats(rng, definition.id)
			gun.stats.gun_type = type as GunTypes.Type
			root.add_child(gun)
			gun.set_process(false)
			var elapsed := 0.0
			var magazine := gun.get_magazine_size()
			for shot in range(magazine):
				gun.fire(Vector3.ZERO, Vector3.FORWARD)
				check(gun.current_ammo == magazine - shot - 1, "Native trigger consumes one round: %s/type%d" % [definition.id, type])
				gun._process(gun.get_shot_interval())
				elapsed += gun.get_shot_interval()
			check(gun.shots == magazine and gun.is_reloading and gun.current_ammo == 0, "Empty magazine starts timed reload: %s/type%d" % [definition.id, type])
			var remaining := gun.reload_remaining
			gun._process(remaining)
			elapsed += remaining
			check(not gun.is_reloading and gun.current_ammo == magazine, "Reload completes native cycle: %s/type%d" % [definition.id, type])
			# Independent expected-value calculation: base hits, 10% standard
			# double crits, and the elapsed native trigger/cooldown/reload cycle.
			var expected_damage := magazine * float(definition.damage) * 1.1
			check(absf(expected_damage / elapsed - 44.0) < 0.02, "Initial sustained expected DPS is 44 across every type: %s/type%d" % [definition.id, type])
			gun.free()

func _test_reload_timing_and_pause() -> void:
	var gun := RecordingGun.new()
	gun.stats = GunStats.new()
	gun.stats.max_ammo = 4
	gun.stats.fire_rate = 0.25
	gun.stats.reload_seconds = 1.2
	gun.transform = Transform3D(Basis.from_euler(Vector3(0.04, 0.08, -0.03)), Vector3(0.2, -0.3, -0.4))
	root.add_child(gun)
	gun.set_process(false)
	var baseline := gun.transform
	var completions := [0]
	gun.gun_reloaded.connect(func(): completions[0] += 1)
	gun.fire(Vector3.ZERO, Vector3.FORWARD)
	gun.reload()
	check(gun.is_reloading and gun.current_ammo == 3 and gun.reload_duration == 1.2, "Manual reload begins without refilling ammo")
	gun.fire(Vector3.ZERO, Vector3.FORWARD)
	gun.reload()
	check(gun.shots == 1 and completions[0] == 0, "Reload blocks firing and repeated reload input")
	gun._process(0.1)
	check(is_equal_approx(gun.reload_remaining, 1.2), "Manual reload respects remaining cooldown of previous shot")
	gun._process(0.3)
	check(gun.current_ammo == 3 and gun.reload_remaining < 1.2 and not gun.transform.is_equal_approx(baseline), "Reload time advances and native feed animation moves the dog")
	check(gun.get_node_or_null("ReloadTreat") != null, "Reload animation includes a visible feeding treat")
	gun.set_process(true)
	await process_frame
	paused = true
	var before_pause := gun.reload_remaining
	var paused_transform := gun.transform
	for frame in range(3):
		await process_frame
	check(is_equal_approx(gun.reload_remaining, before_pause) and gun.transform.is_equal_approx(paused_transform), "SceneTree pause freezes native reload progress and animation")
	paused = false
	gun.set_process(false)
	gun._process(gun.reload_remaining - 0.01)
	check(gun.current_ammo == 3 and gun.is_reloading and completions[0] == 0, "Ammo stays unchanged until the completion boundary")
	gun._process(0.02)
	check(gun.current_ammo == 4 and not gun.is_reloading and completions[0] == 1, "Completion refills once and emits one reload event")
	check(gun.transform.is_equal_approx(baseline), "Reload restores the exact dog transform baseline")
	gun._process(1.0)
	check(completions[0] == 1, "Later frames cannot finish an already completed reload twice")
	gun.fire(Vector3.ZERO, Vector3.FORWARD)
	check(gun.current_ammo == 3 and gun.shots == 2, "Completed reload resumes normal firing")
	gun.free()

func _test_hidden_reload_slot() -> void:
	var inventory: WeaponManager = run.player.weapon_manager
	var gun: Gun = inventory.get_current_gun()
	gun.current_ammo = 1
	gun.fire_timer = 0.0
	gun.reload()
	var initial := gun.reload_remaining
	inventory.switch_to_weapon(1)
	check(not gun.visible and gun.is_reloading, "Switching slots hides the reloading dog without cancelling its timer")
	gun._process(initial * 0.5)
	check(gun.is_reloading and gun.current_ammo == 1 and gun.reload_remaining < initial, "A hidden dog continues reloading instead of granting an instant full magazine")
	gun._process(initial)
	check(not gun.is_reloading and gun.current_ammo == gun.get_magazine_size(), "Hidden dog completes its own reload normally")
	inventory.switch_to_weapon(0)

func _reset_modifiers() -> void:
	run.run_modifiers.clear()
	run.player.weapon_manager.switch_to_weapon(0)
	run._apply_player_modifiers()
	for gun in run.player.weapon_manager.guns:
		gun.refill_magazine()

func _test_reload_ownership_transfer() -> void:
	var inventory: WeaponManager = run.player.weapon_manager
	var gun: Gun = inventory.get_current_gun()
	gun.set_process(false)
	gun.current_ammo = 1
	gun.fire_timer = 0.0
	gun.reload()
	gun._process(gun.reload_duration * 0.2)
	var remaining := gun.reload_remaining
	check(inventory.drop_current_gun() == gun, "Dropping a reloading dog retains the same object")
	var stand := DogGunPickup.new()
	var host: Node3D = run.generator.get_start_room()
	stand.configure(run, host, gun)
	host.add_child(stand)
	stand.set_process(false)
	stand.global_position += run.player.camera.global_position - stand.get_interaction_position()
	var display_transform := gun.transform
	stand._process(0.5)
	check(gun.is_reloading and gun.current_ammo == 1 and is_equal_approx(gun.reload_remaining, remaining) and gun.transform.is_equal_approx(display_transform), "Drop stand rebases active animation and does not bob over a reload pose")
	check(stand.interact(run) and gun.get_parent() == inventory.gun_holder and gun.is_reloading and gun.current_ammo == 1, "Picking up an active reload retains its timer and incomplete magazine")
	gun._process(remaining)
	check(not gun.is_reloading and gun.transform.is_equal_approx(Transform3D.IDENTITY) and gun.current_ammo == gun.get_magazine_size(), "Reload finishes at held identity rather than the old display transform")
	inventory.switch_to_weapon(0)
	gun.current_ammo = 1
	gun.fire_timer = 0.0
	gun.reload()
	gun._process(gun.reload_duration * 0.2)
	run.acquire_item(PetItems.find_item("leash"))
	check(run.activate_item() and gun.get_meta("on_walkies", false), "Walkies accepts the actual reloading dog")
	if is_instance_valid(run.walkies_companion):
		run.walkies_companion.set_process(false)
		gun._process(gun.reload_duration * 0.2)
		check(gun.is_reloading and gun.current_ammo == 1, "Walking dog keeps its incomplete timed reload")
		run._end_walkies()
		gun._process(gun.reload_remaining)
		check(not gun.is_reloading and gun.get_parent() == inventory.gun_holder and gun.transform.is_equal_approx(Transform3D.IDENTITY), "Returning from Walkies restores held scale and position after reload")
	gun.set_process(true)
	inventory.switch_to_weapon(0)
	run.active_item.clear()
	run.active_cooldown = 0.0
	run.active_cooldown_rooms = 0

func _test_health_stacks() -> void:
	_reset_modifiers()
	for copy in range(3):
		run.acquire_item(PetItems.find_item("flesh"))
		check(run.player.max_health == 110 + copy * 10, "Flesh adds ten percentage points per copy")
	check(is_equal_approx(run.get_stat_multiplier("health"), 1.3), "Three Flesh copies use additive 1.3 multiplier")
	for copy in range(10):
		run.acquire_item(PetItems.find_item("flesh"))
	check(run.get_item_count("flesh") == 13 and run.player.max_health == 230, "Health copies have no twelve-item cap")
	_reset_modifiers()
	run.player.current_health = 100
	for maximum in [150, 210, 280]:
		run.acquire_item(PetItems.find_item("tofu"))
		check(run.player.max_health == maximum and run.player.current_health == maximum, "TOFU adds and heals 50, then 60, then 70")
	for copy in range(3):
		run.acquire_item(PetItems.find_item("flesh"))
	check(run.player.max_health == 364, "Flat TOFU health is multiplied once by additive Flesh")

func _test_fungus_stacks() -> void:
	_reset_modifiers()
	var inventory: WeaponManager = run.player.weapon_manager
	var bound: Gun = inventory.get_current_gun()
	var other: Gun = inventory.guns[1]
	var base_walk: float = run._base_player_stats.walk
	var base_jump: float = run._base_player_stats.jump
	var base_reload := bound.get_reload_seconds()
	run.acquire_item(PetItems.find_item("cubensis"))
	check(run.get_all_stats_factor(bound.get_instance_id()) == 2.0 and run.get_all_stats_factor(other.get_instance_id()) == 1.0, "Cubensis doubles only its actual bound dog")
	check(run.player.size_multiplier == 1.0 and run.player.max_health == 100 and is_equal_approx(run.player.walk_speed, base_walk), "Cubensis alone does not change player stats")
	check(is_equal_approx(bound._multiplier("damage"), 2.0) and bound.get_magazine_size() == 60 and is_equal_approx(bound.get_shot_interval(), bound.stats.fire_rate / 2.0) and is_equal_approx(bound.get_reload_seconds(), base_reload / 2.0), "Gun fungus doubles damage/ammo and halves shot/reload intervals")
	run.acquire_item(PetItems.find_item("aminita"))
	check(run.get_all_stats_factor(bound.get_instance_id()) == 4.0 and run.get_all_stats_factor(other.get_instance_id()) == 2.0, "Combined fungi give bound dog fourfold stats and other dogs twofold")
	check(run.player.size_multiplier == 4.0 and run.player.max_health == 400 and is_equal_approx(run.player.walk_speed, base_walk * 4.0) and is_equal_approx(run.player.jump_velocity, base_jump * 4.0), "Combined fungi multiply actual player size, health, speed and jump fourfold")
	inventory.switch_to_weapon(1)
	check(run.player.size_multiplier == 2.0 and run.player.max_health == 200, "Player synergy follows selected dog instead of leaking its bound upgrade")
	inventory.switch_to_weapon(0)
	check(run.player.size_multiplier == 4.0, "Selecting the fungus dog restores its player synergy")
	run.acquire_item(PetItems.find_item("cubensis"))
	check(run.get_all_stats_factor(bound.get_instance_id()) == 8.0 and run.player.size_multiplier == 8.0 and run.get_all_stats_factor(other.get_instance_id()) == 2.0, "Additional dog fungi continue multiplying their bound dog and player synergy")
	run.acquire_item(PetItems.find_item("aminita"))
	check(run.player.size_multiplier == 16.0 and run.get_all_stats_factor(bound.get_instance_id()) == 16.0 and run.get_all_stats_factor(other.get_instance_id()) == 4.0, "Additional global fungi continue stacking across all dogs")
	_reset_modifiers()
	check(run.player.size_multiplier == 1.0 and run.player.max_health == 100, "Clearing modifiers restores original player size and health")

func _test_swarm_currency() -> void:
	_reset_modifiers()
	var host: Node3D = run.generator.get_start_room()
	var remote: Node3D = run.generator.rooms[1]
	var enemy := Enemy4D.new()
	enemy.max_health = 1000
	enemy.initial_w = host.position_4d.w
	enemy.set_meta("encounter_room", host.room_id)
	host.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.enemy_type = GunTypes.Type.EXPLOSIVE
	enemy.gun_stats.gun_type = GunTypes.Type.EXPLOSIVE
	enemy.set_position_4d(Vector4D.from_vector3(run.player.global_position + Vector3.RIGHT * 2, host.position_4d.w))
	run.acquire_item(PetItems.find_item("boneswarm"))
	var plain := BonePickup.new()
	plain.configure(run, host, 1, 0)
	host.add_child(plain)
	plain.set_physics_process(false)
	plain.global_position = enemy.global_position - Vector3.RIGHT * 0.4
	plain._tick_swarm(0.01)
	check(enemy.current_health == 999 and not plain.swarm_spine, "Plain bone swarm contacts deal one damage without splitting")
	plain.global_position = enemy.global_position - Vector3.RIGHT * 0.4
	plain._tick_swarm(0.10)
	check(enemy.current_health == 999, "Bone contact cooldown prevents repeated damage while overlapping")
	for frame in range(150):
		plain._tick_swarm(0.01)
		if enemy.current_health < 999:
			break
	check(enemy.current_health == 998, "A bone can bounce back and damage the same live enemy again")
	plain.free()
	run.acquire_item(PetItems.find_item("magnet"))
	_test_wrong_w_bones(host, enemy)
	var spiky := BonePickup.new()
	spiky.configure(run, host, 5, 0)
	host.add_child(spiky)
	spiky.set_physics_process(false)
	spiky.global_position = enemy.global_position - Vector3.RIGHT * 0.4
	var before_health: int = enemy.current_health
	spiky._tick_swarm(0.01)
	var spines: Array = []
	var carried_value := 0
	var zero_value_spines := 0
	for bone in get_nodes_in_group("bone_pickups"):
		if bone.room_id == host.room_id and not bone.collected:
			bone.set_physics_process(false)
			spines.append(bone)
			carried_value += bone.amount
			if bone.amount == 0:
				zero_value_spines += 1
	check(spiky.swarm_spine and spines.size() == 8 and zero_value_spines == 7 and carried_value == 5, "Cactus swarm splits into one currency spine and seven zero-value combat spines")
	check(enemy.current_health == before_health - 19, "Cactus first contact combines one swarm damage with current dog damage times 0.4")
	spiky.global_position = enemy.global_position - Vector3.RIGHT * 0.4
	spiky._tick_swarm(0.36)
	check(enemy.current_health == before_health - 38 and get_nodes_in_group("bone_pickups").size() == 8, "Existing spines keep swarming without recursive currency or spine duplication")
	var outside := BonePickup.new()
	outside.configure(run, remote, 10, 0)
	remote.add_child(outside)
	outside.set_physics_process(false)
	var wallet: int = run.bones
	enemy.free()
	run._sync_combat_locks()
	run.room_states[host.room_id] = {"remaining": 0, "cleared": false, "combat_started": true}
	run._clear_room(host.room_id)
	check(run.bones == wallet + 5 and not outside.collected, "Room clear banks only that room's original conserved bone currency")
	for spine in spines:
		spine.bank_after_room_clear()
	run._clear_room(host.room_id)
	check(run.bones == wallet + 5, "Rebanking spines or clearing again cannot pay duplicate currency")
	outside.free()

func _test_wrong_w_bones(host: Node3D, same_layer_enemy: Enemy4D) -> void:
	var same_position := same_layer_enemy.position_4d
	same_layer_enemy.set_position_4d(Vector4D.from_vector3(run.player.global_position + Vector3.RIGHT * 10, host.position_4d.w))
	var wrong_layer := Enemy4D.new()
	wrong_layer.max_health = 1000
	wrong_layer.initial_w = host.position_4d.w + 100.0
	wrong_layer.set_meta("encounter_room", host.room_id)
	host.add_child(wrong_layer)
	wrong_layer.set_physics_process(false)
	wrong_layer.enemy_type = GunTypes.Type.EXPLOSIVE
	wrong_layer.gun_stats.gun_type = GunTypes.Type.EXPLOSIVE
	wrong_layer.set_position_4d(Vector4D.from_vector3(run.player.global_position + Vector3.RIGHT * 2, host.position_4d.w + 100.0))
	var bone := BonePickup.new()
	bone.configure(run, host, 1, 0)
	host.add_child(bone)
	bone.set_physics_process(false)
	bone.global_position = wrong_layer.global_position
	bone._tick_swarm(0.01)
	bone._tick_spikes()
	check(wrong_layer.current_health == 1000 and not bone.swarm_spine, "Swarm and legacy cactus contacts ignore overlapping enemies in another W layer")
	bone.free()
	wrong_layer.free()
	same_layer_enemy.set_position_4d(same_position)
