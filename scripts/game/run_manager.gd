class_name RunManager
extends Node

signal floor_changed(floor_number: int)
signal item_acquired(item_name: String)
signal floor_completed()
signal status_changed()
signal pickup_message(text: String)

@export var max_floors: int = 3
## Each enemy rolls once to release the breed and weapon type it carried.
@export_range(0.0, 1.0, 0.001) var gun_drop_chance: float = 0.05
var current_floor: int = 1
var run_modifiers: Array[Dictionary] = []
var bones: int = 0
var bombs: int = 0
var keys: int = 0
var active_item: Dictionary = {}
var active_cooldown: float = 0.0
var active_cooldown_rooms: int = 0
var walkies_companion: Node3D
var magnet_boost_remaining: float = 0.0
var generator: LevelGenerator
var player: Node3D
var loading: bool = true
var floor_won: bool = false
var room_states: Dictionary = {}
var current_room_id: int = -1
var _rng := RandomNumberGenerator.new()
var _base_player_stats: Dictionary = {}
var _floor_completion_announced: bool = false
var _counted_deaths: Dictionary = {}
var room_enemy_counts: Dictionary = {}

func _ready() -> void:
	add_to_group("run_manager")
	generator = get_parent().get_node("LevelGenerator")
	player = get_tree().get_first_node_in_group("player")
	generator.room_entered.connect(_on_room_entered)
	get_tree().node_added.connect(_on_tree_node_added)
	player.player_died.connect(func(): GameManager.end_run(false))
	call_deferred("start_new_run")

func start_new_run() -> void:
	GameManager.start_run()
	if GameManager.run_seed <= 0:
		GameManager.run_seed = int(Time.get_unix_time_from_system()) % 2147483647
	_rng.seed = GameManager.run_seed
	current_floor = 1
	run_modifiers.clear()
	bones = 0
	bombs = 0
	keys = 1
	active_item.clear()
	active_cooldown = 0.0
	active_cooldown_rooms = 0
	_end_walkies()
	magnet_boost_remaining = 0.0
	if _base_player_stats.is_empty():
		_base_player_stats = {"walk": player.walk_speed, "jump": player.jump_velocity, "health": player.max_health, "camera_position": player.camera.position}
		for stat in ["acceleration", "deceleration", "air_acceleration", "air_deceleration"]:
			_base_player_stats[stat] = player.get(stat)
	if not player.weapon_manager.weapon_switched.is_connected(_on_stat_dog_changed):
		player.weapon_manager.weapon_switched.connect(_on_stat_dog_changed)
	_apply_player_modifiers()
	_give_starting_pups()
	await _generate_floor()

func _give_starting_pups() -> void:
	var inventory: WeaponManager = player.weapon_manager
	# Restarting in-place must not swap three new pups into one occupied slot.
	for index in range(inventory.guns.size()):
		if is_instance_valid(inventory.guns[index]):
			inventory.guns[index].queue_free()
		inventory.guns[index] = null
	inventory.current_gun_index = -1
	for definition in PetItems.STARTER_DOGS:
		var gun := Gun.new()
		gun.stats = GunStats.new()
		gun.stats.gun_type = {"explosive": GunTypes.Type.EXPLOSIVE, "freezing": GunTypes.Type.FREEZING, "implosive": GunTypes.Type.IMPLOSIVE, "accelerating": GunTypes.Type.ACCELERATING}.get(definition.effect, GunTypes.Type.EXPLOSIVE)
		gun.stats.gun_name = definition.name
		gun.stats.description = definition.description
		gun.stats.flavor_text = definition.flavor_text
		gun.stats.mascot_visual = definition.id == "mappo"
		gun.stats.base_damage = definition.damage
		gun.stats.fire_rate = definition.fire_rate
		gun.stats.projectile_speed = definition.projectile_speed
		gun.stats.max_ammo = definition.max_ammo
		gun.stats.reload_seconds = float(definition.get("reload_seconds", -1.0))
		gun.stats.rarity = {"poor": GunTypes.Rarity.POOR, "mid": GunTypes.Rarity.MID, "ok": GunTypes.Rarity.OK, "common": GunTypes.Rarity.OK, "epic": GunTypes.Rarity.EPIC, "legendary": GunTypes.Rarity.LEGENDARY, "peak": GunTypes.Rarity.PEAK}.get(str(definition.rarity).to_lower(), GunTypes.Rarity.OK)
		inventory.pickup_gun(gun)
	inventory.switch_to_weapon(0)
	_refresh_item_visuals()

func _generate_floor() -> void:
	_end_walkies()
	loading = true
	floor_won = false
	_floor_completion_announced = false
	_counted_deaths.clear()
	room_enemy_counts.clear()
	current_room_id = -1
	room_states.clear()
	for projectile in get_tree().get_nodes_in_group("projectiles"):
		projectile.queue_free()
	player.set_physics_process(false)
	generator.level_depth = current_floor
	generator.num_normal_rooms = 3 + current_floor
	await generator.generate_level(GameManager.run_seed + (current_floor - 1) * 7919)
	generator.spawn_player_in_start_room()
	player.set_physics_process(true)
	player.heal(20)
	for gun in player.weapon_manager.guns:
		if gun:
			gun.refill_magazine()
	loading = false
	floor_changed.emit(current_floor)
	status_changed.emit()
	_on_room_entered(generator.get_start_room())

func _process(delta: float) -> void:
	if loading:
		return
	_tick_inventory(delta)
	_sync_encounters(delta)
	_sync_combat_locks()
	# Include enemies added outside the encounter spawner, and enemies removed
	# without a death signal. Only entered, uncleared rooms can earn a reward.
	for room_id in room_states.keys():
		if not room_states[room_id].cleared and room_enemy_counts.get(room_id, 0) == 0:
			_clear_room(room_id)

func _sync_encounters(delta: float = 0.0) -> void:
	# Displayed room W changes as the player walks. Occupants stay with their room.
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy is Enemy4D or enemy.is_queued_for_deletion() or not enemy.has_meta("encounter_room"):
			continue
		var room_id: int = enemy.get_meta("encounter_room")
		var room = generator.get_room(room_id)
		if not is_instance_valid(room):
			continue
		enemy.set_position_4d(Vector4D.from_vector3(enemy.global_position, room.position_4d.w))
		enemy.target = player
		# A sleeping enemy cannot refresh itself. Update both visuals and collisions
		# here so returning through a doorway cannot leave invisible solid enemies.
		enemy._update_slice_visibility(player.position_4d.w)
		if not room.graph_visible:
			enemy.visible = false
			enemy.collision_layer = 0
		enemy.process_mode = Node.PROCESS_MODE_INHERIT if room_id == current_room_id else Node.PROCESS_MODE_DISABLED
		# Off-room AI sleeps, but incoming portal shots still share this hit window.
		# Active enemies advance it in their own physics step; synchronization-only
		# calls and gameplay pauses cannot spend additional time from either timer.
		if room_id != current_room_id and delta > 0.0:
			enemy._tick_freezing_hit_window(delta)

func _on_room_entered(room: Node) -> void:
	if loading or not is_instance_valid(room):
		return
	current_room_id = room.room_id
	_sync_encounters()
	_sync_combat_locks()
	status_changed.emit()
	if room_states.has(room.room_id):
		return
	# A defeated boss ends new combat, but the player can still visit unopened
	# shops and reward rooms before choosing the floor exit.
	if floor_won and room.room_type not in [LevelGenerator.ROOM_ITEM, LevelGenerator.ROOM_SHOP, LevelGenerator.ROOM_GAMBLING, LevelGenerator.ROOM_SECRET]:
		return
	room_states[room.room_id] = {"remaining": 0, "cleared": false}
	if room.room_id == 0:
		room_states[room.room_id].cleared = true
		return
	if room.room_type in [LevelGenerator.ROOM_ITEM, LevelGenerator.ROOM_SHOP, LevelGenerator.ROOM_GAMBLING]:
		RoomEconomy.populate_room(self, room)
		_clear_room(room.room_id)
		return
	if room.room_type == LevelGenerator.ROOM_SECRET:
		_clear_room(room.room_id)
		return
	_spawn_encounter(room)

func _spawn_encounter(room: Node3D) -> void:
	var boss: bool = room.room_type == LevelGenerator.ROOM_BOSS
	var count: int = 1 if boss else 2 + current_floor
	room_states[room.room_id].remaining = count
	room_states[room.room_id]["combat_started"] = true
	var entry_up: Vector3 = (room.global_position - player.global_position).normalized()
	if entry_up.is_zero_approx():
		entry_up = Vector3.UP
	var tangent := entry_up.cross(Vector3.FORWARD).normalized()
	if tangent.is_zero_approx():
		tangent = Vector3.RIGHT
	for i in range(count):
		var enemy := Enemy4D.new()
		var kind: int = Enemy4D.Archetype.BOSS if boss else (i + current_floor - 1 + room.room_id) % 4
		var dolphin: Dictionary = DolphinCatalog.pick_for_archetype(kind, _rng)
		enemy.configure_dolphin(str(dolphin.id), get_floor_difficulty_multiplier(), _rng)
		enemy.initial_w = room.position_4d.w
		enemy.set_meta("encounter_room", room.room_id)
		var outward := (-entry_up).rotated(tangent, 0.65 + i * 0.4)
		enemy.position = outward * (room.radius - 1.2)
		var surface_up: Vector3 = -outward
		var facing: Vector3 = (player.global_position - room.to_global(enemy.position)).slide(surface_up).normalized()
		if not facing.is_zero_approx():
			enemy.basis = Basis.looking_at(facing, surface_up)
		enemy.up_direction = surface_up
		enemy.died.connect(_on_enemy_died.bind(room.room_id))
		enemy.set_meta("run_death_hook", get_instance_id())
		room.add_child(enemy)
	_sync_encounters()
	_sync_combat_locks()
	status_changed.emit()

func _on_enemy_died(enemy: Enemy4D, room_id: int) -> void:
	if _counted_deaths.has(enemy.get_instance_id()):
		return
	_counted_deaths[enemy.get_instance_id()] = true
	if GameManager.current_state in [GameManager.GameState.GAME_OVER, GameManager.GameState.VICTORY]:
		return
	var room = generator.get_room(room_id)
	if is_instance_valid(room):
		RoomEconomy.drop_enemy_bones(self, enemy, room)
		try_drop_enemy_gun(enemy, room)
	player.heal(roundi(get_stat_bonus("heal_on_kill") * get_player_all_stats_factor()))
	if not room_states.has(room_id) or room_states[room_id].cleared:
		status_changed.emit()
		return
	room_states[room_id].remaining = maxi(0, room_states[room_id].remaining - 1)
	_sync_combat_locks()
	if room_states[room_id].remaining == 0:
		_clear_room(room_id)
	status_changed.emit()

func try_drop_enemy_gun(enemy: Enemy4D, room: Node3D, roll: float = -1.0) -> DogGunPickup:
	if not is_instance_valid(enemy) or not is_instance_valid(room) or enemy.gun_stats == null or enemy.has_meta("gun_drop_rolled"):
		return null
	enemy.set_meta("gun_drop_rolled", true)
	var chance := clampf(gun_drop_chance, 0.0, 1.0)
	var result := _rng.randf() if roll < 0.0 else roll
	if chance <= 0.0 or (chance < 1.0 and result >= chance):
		return null
	var gun := Gun.new()
	# A drop keeps the enemy's breed and rolled type. Enemy combat tuning lives
	# in a separate resource and never weakens the player's acquired weapon.
	gun.stats = enemy.gun_stats.duplicate(true) as GunStats
	var pickup := DogGunPickup.new()
	pickup.configure(self, room, gun)
	room.add_child(pickup)
	var outward := (enemy.global_position - room.global_position).normalized()
	if outward.is_zero_approx():
		outward = Vector3.DOWN
	RoomEconomy.place_on_surface(pickup, room, outward, (player.global_position - room.global_position).normalized())
	return pickup

func _clear_room(room_id: int) -> void:
	if room_states[room_id].cleared or room_enemy_counts.get(room_id, 0) > 0:
		return
	room_states[room_id].remaining = 0
	room_states[room_id].cleared = true
	if room_states[room_id].get("combat_started", false):
		recharge_active_from_room()
		# A key earned on every second combat clear keeps special rooms available
		# without making their locks mandatory on the route to the boss.
		var combat_clears := 0
		for state in room_states.values():
			if state.get("cleared", false) and state.get("combat_started", false):
				combat_clears += 1
		if combat_clears % 2 == 0:
			add_consumable("key")
			pickup_message.emit("Room clear: +1 key")
	GameManager.room_cleared()
	player.heal(8)
	var room = generator.get_room(room_id)
	for bone in get_tree().get_nodes_in_group("bone_pickups"):
		if bone.room_id == room_id and get_item_count("boneswarm") > 0:
			bone.bank_after_room_clear()
	if room.room_type == LevelGenerator.ROOM_BOSS:
		floor_won = true
	elif room.room_type in [LevelGenerator.ROOM_NORMAL, LevelGenerator.ROOM_SPECIAL, LevelGenerator.ROOM_SECRET]:
		RoomEconomy.spawn_reward(self, room, 1, false)
	status_changed.emit()

func _sync_combat_locks() -> void:
	room_enemy_counts.clear()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or not enemy is Node3D:
			continue
		var health = enemy.get("current_health")
		if (health != null and health <= 0) or enemy.get("_dead") == true:
			continue
		var room_id := _get_enemy_room_id(enemy)
		if room_id >= 0:
			room_enemy_counts[room_id] = int(room_enemy_counts.get(room_id, 0)) + 1
			if enemy is Enemy4D and enemy.get_meta("run_death_hook", -1) != get_instance_id():
				enemy.died.connect(_on_external_enemy_died)
				enemy.set_meta("run_death_hook", get_instance_id())
	for room in generator.rooms:
		room.set_combat_locked(room_enemy_counts.get(room.room_id, 0) > 0, player)

func _on_external_enemy_died(enemy: Enemy4D) -> void:
	_on_enemy_died(enemy, _get_enemy_room_id(enemy))

func _on_tree_node_added(node: Node) -> void:
	# External enemies can die during the same frame they spawn, before the
	# encounter scan. Connect immediately; native encounters already own a hook.
	if node is Enemy4D and node.get_meta("run_death_hook", -1) != get_instance_id():
		node.died.connect(_on_external_enemy_died)
		node.set_meta("run_death_hook", get_instance_id())

func _get_enemy_room_id(enemy: Node3D) -> int:
	var assigned: int = enemy.get_meta("encounter_room", -1)
	if assigned >= 0 and assigned < generator.rooms.size():
		return assigned
	# Console-spawned enemies do not own encounter metadata. Resolve the room
	# physically containing them on their W slice; never count distant layers.
	var best_id := -1
	var best_inside := -INF
	var enemy_position_4d = enemy.get("position_4d")
	for room in generator.rooms:
		if enemy_position_4d != null:
			if absf(enemy_position_4d.w - room.position_4d.w) > 1.0:
				continue
		elif not room.graph_visible:
			continue
		var inside: float = room.radius - enemy.global_position.distance_to(room.global_position)
		if inside >= 0.0 and inside > best_inside:
			best_inside = inside
			best_id = room.room_id
	return best_id

func _finish_floor() -> void:
	if _floor_completion_announced or not floor_won or GameManager.current_state != GameManager.GameState.PLAYING:
		return
	_floor_completion_announced = true
	if current_floor >= max_floors:
		GameManager.end_run(true)
	else:
		GameManager.pause_game()
		floor_completed.emit()

func request_floor_exit() -> void:
	if loading or not floor_won:
		return
	var room = generator.get_room(current_room_id)
	if not is_instance_valid(room) or room.room_type != LevelGenerator.ROOM_BOSS or room_enemy_counts.get(current_room_id, 0) > 0:
		return
	_finish_floor()

func advance_floor() -> void:
	if not floor_won or loading or current_floor >= max_floors:
		return
	current_floor += 1
	GameManager.resume_game()
	await _generate_floor()

func acquire_item(item: Dictionary) -> bool:
	if item.is_empty():
		return false
	var acquired := item.duplicate(true)
	if PetItems.is_consumable(acquired):
		var kind := str(acquired.get("consumable", ""))
		if kind not in ["bomb", "key"]:
			return false
		add_consumable(kind, int(acquired.get("amount", 1)))
	elif PetItems.is_active(acquired):
		# Cooldown belongs to the slot, so swapping cannot bypass recovery.
		active_item = acquired
		active_cooldown = maxf(active_cooldown, float(acquired.get("remaining_cooldown", 0.0)))
		active_cooldown_rooms = maxi(active_cooldown_rooms, int(acquired.get("remaining_cooldown_rooms", 0)))
	else:
		var selected_gun: Gun = player.weapon_manager.get_current_gun() if is_instance_valid(player) else null
		if int(acquired.get("category", PetItems.Category.GLOBAL_PASSIVE)) == PetItems.Category.DOG_INCLUSIVE:
			if not is_instance_valid(selected_gun):
				pickup_message.emit("Select a pup before collecting this item.")
				return false
			acquired["gun_id"] = selected_gun.get_instance_id()
			acquired["dog_name"] = selected_gun.stats.gun_name
		run_modifiers.append(acquired)
		_apply_player_modifiers()
		if acquired.get("stat", "") == "ammo" and is_instance_valid(selected_gun):
			selected_gun.current_ammo = mini(selected_gun.get_magazine_size(), selected_gun.current_ammo + int(acquired.get("amount", 0)))
			selected_gun.ammo_changed.emit(selected_gun.current_ammo, selected_gun.get_magazine_size())
	var acquired_name := str(acquired.get("name", "Treat"))
	_refresh_item_visuals()
	var owner := " · " + str(acquired.dog_name) if acquired.has("dog_name") else ""
	item_acquired.emit(acquired_name)
	pickup_message.emit(acquired_name + owner)
	status_changed.emit()
	return true

func add_modifier(modifier: Dictionary) -> void:
	acquire_item(modifier)

func _apply_player_modifiers() -> void:
	if not is_instance_valid(player):
		return
	player.walk_speed = _base_player_stats.get("walk", 8.0) * get_stat_multiplier("speed", -1)
	player.jump_velocity = _base_player_stats.get("jump", 9.0) * get_stat_multiplier("jump", -1)
	var old_health: int = player.max_health
	player.max_health = roundi((int(_base_player_stats.get("health", 100)) + get_stat_bonus("health")) * get_stat_multiplier("health"))
	player.heal(maxi(0, player.max_health - old_health))
	var size_factor := get_player_all_stats_factor()
	player.set_size_multiplier(size_factor)
	for stat in ["acceleration", "deceleration", "air_acceleration", "air_deceleration"]:
		player.set(stat, float(_base_player_stats.get(stat, player.get(stat))) * size_factor)

func _on_stat_dog_changed(_index: int, _gun: Gun) -> void:
	_apply_player_modifiers()

func get_all_stats_factor(gun_id: int = -1) -> float:
	# Amanita affects the player and every dog; Cubensis affects its bound dog.
	# Together that dog's 2x and Amanita's 2x also apply to the player's stats.
	if gun_id < 0:
		return get_player_all_stats_factor()
	var amanitas := get_item_count("aminita")
	var cubensis := get_item_count("cubensis", gun_id)
	return pow(2.0, amanitas + cubensis)

func _modifier_applies(modifier: Dictionary, gun_type: int, gun_id: int) -> bool:
	if int(modifier.get("category", PetItems.Category.GLOBAL_PASSIVE)) == PetItems.Category.DOG_INCLUSIVE:
		return gun_id >= 0 and int(modifier.get("gun_id", -1)) == gun_id
	return int(modifier.get("type_restriction", -1)) in [-1, gun_type]

func get_stat_multiplier(stat_name: String, gun_type: int = -1, gun_id: int = -1) -> float:
	var multiplier := 1.0
	var flesh_bonus := 0.0
	for mod in run_modifiers:
		if mod.get("stat", "") == stat_name and _modifier_applies(mod, gun_type, gun_id):
			if mod.get("id", "") == "flesh":
				flesh_bonus += float(mod.get("stack_increment", 0.1))
			else:
				multiplier *= float(mod.get("multiplier", 1.0))
	multiplier *= 1.0 + flesh_bonus
	if stat_name != "all":
		var factor := get_all_stats_factor(gun_id) if gun_id >= 0 else get_player_all_stats_factor()
		multiplier *= 1.0 / factor if stat_name in ["fire_rate", "reload"] else factor
	return multiplier

func get_player_all_stats_factor() -> float:
	var amanitas := get_item_count("aminita")
	if amanitas == 0:
		return 1.0
	var selected: Gun = player.weapon_manager.get_current_gun() if is_instance_valid(player) else null
	var cubensis := get_item_count("cubensis", selected.get_instance_id()) if is_instance_valid(selected) else 0
	return pow(2.0, amanitas + cubensis)

func get_stat_bonus(stat_name: String, gun_type: int = -1, gun_id: int = -1) -> float:
	var amount := 0.0
	var crit_copies := 0
	var tofu_copies := 0
	for mod in run_modifiers:
		if mod.get("stat", "") == stat_name and _modifier_applies(mod, gun_type, gun_id):
			if stat_name == "crit_chance":
				amount += float(mod.get("amount", 0.0)) * pow(0.99, crit_copies)
				crit_copies += 1
			else:
				amount += float(mod.get("amount", 0.0))
				if mod.get("id", "") == "tofu":
					amount += tofu_copies * float(mod.get("stack_increment", 10.0))
					tofu_copies += 1
	return amount

func add_bones(amount: int) -> void:
	if amount <= 0:
		return
	bones += amount
	status_changed.emit()

func spend_bones(amount: int) -> bool:
	if amount < 0 or bones < amount:
		return false
	bones -= amount
	status_changed.emit()
	return true

func add_consumable(kind: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	match kind:
		"bomb": bombs += amount
		"key": keys += amount
		_: return
	status_changed.emit()

func spend_key() -> bool:
	if keys <= 0:
		return false
	keys -= 1
	status_changed.emit()
	return true

func _tick_inventory(delta: float) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return
	var old_seconds := ceili(active_cooldown)
	var was_magnetized := magnet_boost_remaining > 0.0
	active_cooldown = maxf(0.0, active_cooldown - delta)
	magnet_boost_remaining = maxf(0.0, magnet_boost_remaining - delta)
	if ceili(active_cooldown) != old_seconds or was_magnetized != (magnet_boost_remaining > 0.0):
		status_changed.emit()

func activate_item() -> bool:
	if loading or not is_instance_valid(player) or GameManager.current_state != GameManager.GameState.PLAYING or active_item.is_empty() or active_cooldown > 0.0 or active_cooldown_rooms > 0:
		return false
	match str(active_item.get("effect", "")):
		"howl", "sound blast":
			var radius := float(active_item.get("radius", 8.0))
			for enemy in get_tree().get_nodes_in_group("enemies"):
				if not enemy is Enemy4D or enemy._dead or _get_enemy_room_id(enemy) != current_room_id:
					continue
				if enemy.global_position.distance_to(player.global_position) <= radius:
					enemy.stun(float(active_item.get("stun_duration", 2.0)))
					enemy.take_damage(int(active_item.get("damage", 65)), GunTypes.Type.EXPLOSIVE)
			_show_howl_pulse(radius)
			_play_air_horn()
		"heal":
			if player.current_health >= player.max_health:
				pickup_message.emit("Already at full health.")
				return false
			player.heal(int(active_item.get("amount", 30)))
		"magnet":
			magnet_boost_remaining = float(active_item.get("duration", 8.0))
		"walkies":
			if not _start_walkies():
				return false
		_: return false
	active_cooldown = float(active_item.get("cooldown", 12.0))
	active_cooldown_rooms = int(active_item.get("cooldown_rooms", 0))
	pickup_message.emit(str(active_item.get("name", "Active item")) + " activated")
	status_changed.emit()
	return true

func _show_howl_pulse(radius: float) -> void:
	var effect := MeshInstance3D.new()
	effect.name = "HowlPulse"
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	effect.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.9, 0.72, 0.25)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	effect.material_override = material
	effect.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var room = generator.get_room(current_room_id)
	if not is_instance_valid(room):
		effect.free()
		return
	room.add_child(effect)
	effect.global_position = player.global_position
	effect.scale = Vector3.ONE * 0.15
	var tween := effect.create_tween().set_parallel(true)
	tween.tween_property(effect, "scale", Vector3.ONE * radius, 0.35)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.35)
	tween.chain().tween_callback(effect.queue_free)

func _play_air_horn() -> void:
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = 22050
	var samples := PackedByteArray()
	samples.resize(6615 * 2)
	for i in range(6615):
		var t := float(i) / 22050.0
		var envelope := minf(t * 50.0, 1.0) * maxf(0.0, 1.0 - t / 0.3)
		var wave := (sin(TAU * 440.0 * t) + sin(TAU * 554.37 * t) + sin(TAU * 659.25 * t)) / 3.0
		samples.encode_s16(i * 2, int(wave * envelope * 16000.0))
	sound.data = samples
	var horn := AudioStreamPlayer.new()
	horn.name = "AirHornSound"
	horn.stream = sound
	horn.volume_db = -12.0
	add_child(horn)
	horn.finished.connect(horn.queue_free)
	horn.play()

func get_bone_pull_multiplier() -> float:
	return 2.75 if magnet_boost_remaining > 0.0 else 1.0

func recharge_active_from_room() -> void:
	active_cooldown_rooms = maxi(0, active_cooldown_rooms - 1)
	status_changed.emit()

func get_active_status() -> String:
	if active_item.is_empty():
		return "Find an active item on a pedestal"
	if active_cooldown_rooms > 0:
		return "Recharging  %d room clear%s" % [active_cooldown_rooms, "s" if active_cooldown_rooms != 1 else ""]
	return "Recharging  %.1fs" % active_cooldown if active_cooldown > 0.0 else "Ready  ·  press E"

func get_item_count(id: String, gun_id: int = -1) -> int:
	var count := 0
	for item in run_modifiers:
		if item.get("id", "") == id and _modifier_applies(item, -1, gun_id):
			count += 1
	return count

func get_current_damage() -> float:
	var gun: Gun = player.weapon_manager.get_current_gun() if is_instance_valid(player) else null
	return gun.stats.get_scaled_damage() * gun._multiplier("damage") if is_instance_valid(gun) else 0.0

func get_bone_damage() -> float:
	var factor := 0.0
	for item in run_modifiers:
		if item.get("id", "") == "magnet":
			factor += float(item.get("multiplier", 0.4))
	return get_current_damage() * factor

func _refresh_item_visuals() -> void:
	if not is_instance_valid(player):
		return
	load("res://scripts/items/item_attachments.gd").refresh_player(self)
	for gun in player.weapon_manager.guns:
		if is_instance_valid(gun):
			gun.refresh_item_visuals()

func _start_walkies() -> bool:
	var inventory: WeaponManager = player.weapon_manager
	var gun: Gun = inventory.get_current_gun()
	if not is_instance_valid(gun) or is_instance_valid(walkies_companion):
		return false
	var next_slot := -1
	for i in range(inventory.guns.size()):
		if is_instance_valid(inventory.guns[i]) and inventory.guns[i] != gun:
			next_slot = i
			break
	if next_slot < 0:
		pickup_message.emit("Walkies needs another pup in your pack.")
		return false
	walkies_companion = load("res://scripts/items/walkies_companion.gd").new()
	walkies_companion.configure(self, gun, float(active_item.get("duration", 12.0)))
	get_tree().current_scene.add_child(walkies_companion)
	gun.set_meta("on_walkies", true)
	gun.reparent(walkies_companion, false)
	gun.transform = Transform3D.IDENTITY
	gun.scale = Vector3.ONE * 2.0
	gun.rebase_reload_animation(gun.transform)
	inventory.switch_to_weapon(next_slot)
	gun.visible = true
	return true

func _end_walkies() -> void:
	if is_instance_valid(walkies_companion):
		walkies_companion.finish()
	walkies_companion = null

func use_bomb() -> bool:
	if loading or bombs <= 0 or not is_instance_valid(player) or GameManager.current_state != GameManager.GameState.PLAYING:
		return false
	if RunBomb.spawn(self) == null:
		return false
	bombs -= 1
	status_changed.emit()
	return true

func get_floor_difficulty_multiplier() -> float:
	return 1.0 + (current_floor - 1) * 0.3

func get_status_text() -> String:
	if loading:
		return "Sniffing out a new dimension..."
	var room = generator.get_room(current_room_id)
	var room_name: String = RoomTypes.ROOM_NAMES.get(room.room_type, "Unknown") if room else "Between rooms"
	var remaining: int = room_enemy_counts.get(current_room_id, room_states.get(current_room_id, {}).get("remaining", 0))
	return "FLOOR %d / %d  ·  %s  ·  %d hostile%s\nSEED %d  ·  %d treats  ·  SCORE %d" % [current_floor, max_floors, room_name, remaining, "s" if remaining != 1 else "", GameManager.run_seed, run_modifiers.size(), GameManager.current_score]
