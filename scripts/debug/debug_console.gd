# Debug Console - Press ` (backtick) or F1 to toggle
extends CanvasLayer

var console_container: Control
var output_label: RichTextLabel
var input_field: LineEdit

var is_open: bool = false
var command_history: Array[String] = []
var history_index: int = -1

# Debug flags
var god_mode: bool = false
var noclip_mode: bool = false
var scroll_4d_enabled: bool = false  # When enabled, scroll wheel controls W-axis
var aggro_enabled: bool = true  # When false, enemies don't aggro
var ghost_enabled: bool = false  # When true, show ghost projections of off-slice 4D objects

func _ready() -> void:
	add_to_group("debug_console")  # So enemies can find us for global aggro state
	
	# Find nodes manually with null checks
	console_container = get_node_or_null("ConsoleContainer")
	if console_container:
		output_label = console_container.get_node_or_null("Output")
		input_field = console_container.get_node_or_null("InputField")
		console_container.visible = false
		print("[DebugConsole] Found all UI nodes!")
	else:
		print("[DebugConsole] ERROR: ConsoleContainer not found!")
		return
	
	if input_field:
		input_field.text_submitted.connect(_on_command_submitted)
	
	if output_label:
		_print_line("[color=yellow]Debug Console Ready. Press ` or F1. Type 'help' for commands.[/color]")
	
	print("[DebugConsole] Console initialized!")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key = event.keycode
		var phys = event.physical_keycode
		
		# F1 or backtick
		if key == KEY_F1 or phys == KEY_F1 or key == KEY_QUOTELEFT or phys == KEY_QUOTELEFT or phys == 96:
			toggle_console()
			get_viewport().set_input_as_handled()
			return
	
	if event.is_action_pressed("toggle_console"):
		toggle_console()
		get_viewport().set_input_as_handled()
		return
	
	if is_open and event is InputEventKey and event.pressed:
		if event.keycode == KEY_UP:
			_history_up()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_DOWN:
			_history_down()
			get_viewport().set_input_as_handled()

func toggle_console() -> void:
	is_open = !is_open
	
	if console_container:
		console_container.visible = is_open
		print("[DebugConsole] Set visible = %s" % is_open)
	else:
		print("[DebugConsole] ERROR: No console_container!")
	
	if is_open:
		if input_field:
			input_field.grab_focus()
			input_field.clear()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().paused = true
		print("[DebugConsole] Console OPENED")
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_tree().paused = false
		print("[DebugConsole] Console CLOSED")

func _on_command_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	
	command_history.append(text)
	history_index = command_history.size()
	
	_print_line("> " + text)
	_execute_command(text)
	if input_field:
		input_field.clear()
		input_field.grab_focus()

func _execute_command(command_text: String) -> void:
	var parts = command_text.strip_edges().to_lower().split(" ", false)
	if parts.is_empty():
		return
	
	var cmd = parts[0]
	var args = parts.slice(1)
	
	match cmd:
		"help":
			_cmd_help()
		"spawn_gun", "gun":
			_cmd_spawn_gun(args)
		"god":
			_cmd_god()
		"heal":
			_cmd_heal()
		"noclip":
			_cmd_noclip()
		"clear":
			if output_label:
				output_label.clear()
		"kill":
			_cmd_kill()
		"ammo":
			_cmd_ammo()
		"4d":
			_cmd_4d()
		"spawn":
			_cmd_spawn(args)
		"gun":
			_cmd_spawn_gun(args)
		"aggro":
			_cmd_aggro()
		"ghost":
			_cmd_ghost()
		"level":
			_cmd_level(args)
		"room":
			_cmd_room(args)
		_:
			_print_line("[color=red]Unknown command: %s[/color]" % cmd)

func _cmd_help() -> void:
	_print_line("[color=cyan]--- Commands ---[/color]")
	_print_line("[color=green]gun[/color] <type> <rarity> - Give gun")
	_print_line("  Types: explosive, implosive, freezing, accelerating")
	_print_line("  Rarities: poor, mid, ok, epic, legendary, peak")
	_print_line("[color=green]spawn[/color] <type> - Spawn entity at crosshair")
	_print_line("  Types: hypersphere, klein, enemy, enemy4d")
	_print_line("[color=green]god[/color] - Toggle invincibility")
	_print_line("[color=green]heal[/color] - Full health")
	_print_line("[color=green]ammo[/color] - Refill ammo")
	_print_line("[color=green]noclip[/color] - Toggle collision")
	_print_line("[color=green]kill[/color] - Kill all enemies")
	_print_line("[color=green]4d[/color] - Toggle scroll wheel W-axis movement")
	_print_line("[color=green]ghost[/color] - Toggle ghost projections for off-slice 4D objects")
	_print_line("[color=green]level[/color] [seed] - Generate procedural level")
	_print_line("[color=green]room[/color] <type> - Spawn room sphere (normal, boss, item, shop, gambling, special)")
	_print_line("[color=green]clear[/color] - Clear console")

func _cmd_spawn_gun(args: Array) -> void:
	var type_str = "" if args.size() < 1 else args[0]
	var rarity_str = "" if args.size() < 2 else args[1]
	
	# Random type if not specified
	var gun_type: GunTypes.Type
	if type_str == "" or type_str == "random":
		var types = [GunTypes.Type.EXPLOSIVE, GunTypes.Type.IMPLOSIVE, GunTypes.Type.FREEZING, GunTypes.Type.ACCELERATING]
		gun_type = types[randi() % types.size()]
	else:
		match type_str:
			"explosive": gun_type = GunTypes.Type.EXPLOSIVE
			"implosive": gun_type = GunTypes.Type.IMPLOSIVE
			"freezing": gun_type = GunTypes.Type.FREEZING
			"accelerating": gun_type = GunTypes.Type.ACCELERATING
			_:
				_print_line("[color=red]Invalid type. Use: explosive, implosive, freezing, accelerating, or random[/color]")
				return
	
	# Random rarity if not specified
	var rarity: GunTypes.Rarity
	if rarity_str == "" or rarity_str == "random":
		var rarities = [GunTypes.Rarity.POOR, GunTypes.Rarity.MID, GunTypes.Rarity.OK, GunTypes.Rarity.EPIC, GunTypes.Rarity.LEGENDARY, GunTypes.Rarity.PEAK]
		# Weighted random - lower rarities more common
		var roll = randf()
		if roll < 0.35:
			rarity = GunTypes.Rarity.POOR
		elif roll < 0.60:
			rarity = GunTypes.Rarity.MID
		elif roll < 0.80:
			rarity = GunTypes.Rarity.OK
		elif roll < 0.92:
			rarity = GunTypes.Rarity.EPIC
		elif roll < 0.98:
			rarity = GunTypes.Rarity.LEGENDARY
		else:
			rarity = GunTypes.Rarity.PEAK
	else:
		match rarity_str:
			"poor": rarity = GunTypes.Rarity.POOR
			"mid": rarity = GunTypes.Rarity.MID
			"ok": rarity = GunTypes.Rarity.OK
			"epic": rarity = GunTypes.Rarity.EPIC
			"legendary": rarity = GunTypes.Rarity.LEGENDARY
			"peak": rarity = GunTypes.Rarity.PEAK
			_:
				_print_line("[color=red]Invalid rarity. Use: poor, mid, ok, epic, legendary, peak, or random[/color]")
				return
	
	var stats = GunStats.new()
	stats.gun_name = "Debug Dog"
	stats.gun_type = gun_type
	stats.rarity = rarity
	
	var gun = Gun.new()
	gun.stats = stats
	
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_node("Camera3D/WeaponManager"):
		var wm = player.get_node("Camera3D/WeaponManager")
		wm.pickup_gun(gun)
		_print_line("[color=green]Gave: %s[/color]" % stats.get_display_name())
	else:
		_print_line("[color=red]Player not found[/color]")

func _cmd_spawn_enemy(_args: Array) -> void:
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		_print_line("[color=red]Player not found[/color]")
		return
	
	var enemy_scene = load("res://scenes/enemies/test_enemy.tscn")
	if not enemy_scene:
		_print_line("[color=red]Enemy scene not found[/color]")
		return
	
	var enemy = enemy_scene.instantiate()
	
	# Spawn in front of player
	var spawn_pos = player.global_position + player.get_camera_direction() * 5
	spawn_pos.y = player.global_position.y
	
	get_tree().current_scene.add_child(enemy)
	enemy.global_position = spawn_pos
	
	_print_line("[color=green]Spawned test enemy![/color]")

func _cmd_god() -> void:
	god_mode = !god_mode
	_print_line("[color=green]God mode: %s[/color]" % ("ON" if god_mode else "OFF"))

func _cmd_heal() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("heal"):
		player.heal(9999)
		_print_line("[color=green]Healed![/color]")

func _cmd_ammo() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_node("Camera3D/WeaponManager"):
		var wm = player.get_node("Camera3D/WeaponManager")
		for gun in wm.guns:
			if gun:
				gun.reload()
		_print_line("[color=green]Ammo refilled![/color]")

func _cmd_noclip() -> void:
	noclip_mode = !noclip_mode
	_print_line("[color=green]Noclip + Fly: %s[/color]" % ("ON" if noclip_mode else "OFF"))
	var player = get_tree().get_first_node_in_group("player")
	if player:
		# Disable collision
		var col = player.get_node_or_null("CollisionShape3D")
		if col:
			col.disabled = noclip_mode
		# Enable fly mode
		if player.has_method("set_fly_mode"):
			player.set_fly_mode(noclip_mode)

func _cmd_aggro() -> void:
	aggro_enabled = !aggro_enabled
	_print_line("[color=green]Enemy Aggro: %s[/color]" % ("ON" if aggro_enabled else "OFF"))
	# Update all existing enemies
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.has_method("set_aggro_enabled"):
			enemy.set_aggro_enabled(aggro_enabled)

func _cmd_kill() -> void:
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy.has_method("take_damage"):
			enemy.take_damage(99999, GunTypes.Type.EXPLOSIVE)
	_print_line("[color=green]Killed %d enemies[/color]" % enemies.size())

func _cmd_4d() -> void:
	scroll_4d_enabled = !scroll_4d_enabled
	_print_line("[color=green]4D Scroll Mode: %s[/color]" % ("ON - Scroll wheel moves in W" if scroll_4d_enabled else "OFF"))
	
	# Notify player controller
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_4d_scroll_mode"):
		player.set_4d_scroll_mode(scroll_4d_enabled)
	
	# Notify Slicer4D if it exists
	var slicer = get_tree().get_first_node_in_group("slicer_4d")
	if not slicer:
		# Try finding by class
		for node in get_tree().get_nodes_in_group("objects_4d"):
			if node.get_parent():
				var parent = node.get_parent()
				for child in parent.get_children():
					if child.has_method("set_scroll_4d_mode"):
						slicer = child
						break
	if slicer and slicer.has_method("set_scroll_4d_mode"):
		slicer.set_scroll_4d_mode(scroll_4d_enabled)
		_print_line("[color=yellow]Slicer4D connected![/color]")
	else:
		_print_line("[color=yellow]Note: No Slicer4D found - scroll affects player W only[/color]")

func _cmd_ghost() -> void:
	ghost_enabled = !ghost_enabled
	_print_line("[color=green]Ghost Projections: %s[/color]" % ("ON - off-slice objects shown as ghosts" if ghost_enabled else "OFF"))
	
	# Notify all 4D objects to update ghost mode
	for obj in get_tree().get_nodes_in_group("objects_4d"):
		if obj.has_method("set_ghost_mode"):
			obj.set_ghost_mode(ghost_enabled)

func _cmd_spawn(args: Array) -> void:
	var type_str: String = "hypersphere" if args.size() < 1 else args[0]
	
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		_print_line("[color=red]Player not found[/color]")
		return
	
	# Get spawn position in front of player
	var spawn_pos: Vector3 = player.global_position + player.get_camera_direction() * 10
	
	match type_str:
		"hypersphere", "sphere":
			_spawn_hypersphere(spawn_pos)
		"klein", "kleinbottle":
			_spawn_klein_bottle(spawn_pos)
		"torus":
			_spawn_torus(spawn_pos)
		"enemy":
			_spawn_enemy(spawn_pos)
		"enemy4d", "4denemy":
			var count: int = 1
			if args.size() >= 2 and args[1].is_valid_int():
				count = maxi(int(args[1]), 1)  # Minimum 1, no upper limit
			_spawn_enemy_4d(spawn_pos, count)
		"enemy4dp", "4denemyp":
			var count: int = 1
			if args.size() >= 2 and args[1].is_valid_int():
				count = maxi(int(args[1]), 1)
			_spawn_enemy_4d_p(spawn_pos, count)
		_:
			_print_line("[color=red]Unknown spawn type: %s[/color]" % type_str)
			_print_line("  Valid types: hypersphere, klein, torus, enemy, enemy4d, enemy4dp [count]")

func _spawn_hypersphere(pos: Vector3) -> void:
	var hypersphere = Hypersphere4D.new()
	hypersphere.radius = 8.0
	hypersphere.glow_color = Color(randf(), randf(), 1.0)
	hypersphere.position_4d = Vector4(pos.x, pos.y, pos.z, 0.0)
	hypersphere.slice_threshold = 10.0
	
	get_tree().current_scene.add_child(hypersphere)
	hypersphere.global_position = pos
	
	# Notify all SurfaceWalker4D instances to refresh their surface list
	await get_tree().process_frame
	for walker in get_tree().get_nodes_in_group("surface_walkers_4d"):
		if walker.has_method("refresh_surfaces"):
			walker.refresh_surfaces()
	
	_print_line("[color=green]Spawned Hypersphere at %s[/color]" % str(pos))

func _spawn_klein_bottle(pos: Vector3) -> void:
	var klein = KleinBottle4D.new()
	klein.major_radius = 4.0
	klein.tube_radius = 1.5
	klein.glow_color = Color(1.0, randf(), randf())
	klein.position_4d = Vector4(pos.x, pos.y, pos.z, 0.0)
	klein.slice_threshold = 8.0
	
	get_tree().current_scene.add_child(klein)
	klein.global_position = pos
	
	_print_line("[color=green]Spawned Klein Bottle at %s[/color]" % str(pos))

func _spawn_torus(pos: Vector3) -> void:
	var torus = Torus4D.new()
	torus.major_radius = 6.0
	torus.minor_radius = 2.0
	torus.glow_color = Color(1.0, 0.8, randf())
	torus.position_4d = Vector4(pos.x, pos.y, pos.z, 0.0)
	torus.slice_threshold = 8.0
	
	get_tree().current_scene.add_child(torus)
	torus.global_position = pos
	
	# Notify all SurfaceWalker4D instances to refresh their surface list
	await get_tree().process_frame
	for walker in get_tree().get_nodes_in_group("surface_walkers_4d"):
		if walker.has_method("refresh_surfaces"):
			walker.refresh_surfaces()
	
	_print_line("[color=green]Spawned Torus4D at %s[/color]" % str(pos))

func _spawn_enemy(pos: Vector3) -> void:
	var enemy_scene = load("res://scenes/enemies/test_enemy.tscn")
	if not enemy_scene:
		_print_line("[color=red]Enemy scene not found[/color]")
		return
	
	var spawn_pos: Vector3 = pos + Vector3(0, 10, 0)  # Spawn above so they fall
	var enemy = enemy_scene.instantiate()
	get_tree().current_scene.add_child(enemy)
	enemy.global_position = spawn_pos
	
	_print_line("[color=green]Spawned Enemy at %s[/color]" % str(spawn_pos))

func _spawn_enemy_4d(pos: Vector3, count: int = 1) -> void:
	var base_spawn_pos: Vector3 = pos + Vector3(0, 10, 0)  # Spawn above so they fall
	
	for i in range(count):
		# Spread enemies in a circle around spawn point
		var offset := Vector3.ZERO
		if count > 1:
			var angle := (TAU / float(count)) * i
			var spread_radius := 2.0 + (count * 0.3)  # Bigger spread for more enemies
			offset = Vector3(cos(angle) * spread_radius, 0, sin(angle) * spread_radius)
		
		var spawn_pos := base_spawn_pos + offset
		
		var enemy = Enemy4D.new()
		enemy.enable_4d_mode = true
		enemy.initial_w = 0.0
		enemy.max_health = 50
		enemy.move_speed = 2.5
		enemy.enemy_type = [GunTypes.Type.EXPLOSIVE, GunTypes.Type.IMPLOSIVE, 
			GunTypes.Type.FREEZING, GunTypes.Type.ACCELERATING].pick_random()
		
		get_tree().current_scene.add_child(enemy)
		enemy.global_position = spawn_pos
		enemy.set_position_4d(Vector4D.from_vector3(spawn_pos, 0.0))
	
	if count == 1:
		_print_line("[color=green]Spawned Enemy4D at %s[/color]" % str(base_spawn_pos))
	else:
		_print_line("[color=green]Spawned %d Enemy4Ds around %s[/color]" % [count, str(base_spawn_pos)])

func _spawn_enemy_4d_p(pos: Vector3, count: int = 1) -> void:
	var base_spawn_pos: Vector3 = pos + Vector3(0, 10, 0)  # Spawn above so they fall
	
	for i in range(count):
		# Spread enemies in a circle around spawn point
		var offset := Vector3.ZERO
		if count > 1:
			var angle := (TAU / float(count)) * i
			var spread_radius := 2.0 + (count * 0.3)
			offset = Vector3(cos(angle) * spread_radius, 0, sin(angle) * spread_radius)
		
		var spawn_pos := base_spawn_pos + offset
		
		var enemy = Enemy4DP.new()
		enemy.enable_4d_mode = true
		enemy.initial_w = 0.0  # Will sync to player's W
		enemy.max_health = 50
		enemy.move_speed = 2.5
		enemy.enemy_type = [GunTypes.Type.EXPLOSIVE, GunTypes.Type.IMPLOSIVE, 
			GunTypes.Type.FREEZING, GunTypes.Type.ACCELERATING].pick_random()
		
		get_tree().current_scene.add_child(enemy)
		enemy.global_position = spawn_pos
	
	if count == 1:
		_print_line("[color=cyan]Spawned Enemy4DP (player W-sync) at %s[/color]" % str(base_spawn_pos))
	else:
		_print_line("[color=cyan]Spawned %d Enemy4DPs (player W-sync) around %s[/color]" % [count, str(base_spawn_pos)])

func _history_up() -> void:
	if command_history.is_empty():
		return
	history_index = max(0, history_index - 1)
	if input_field:
		input_field.text = command_history[history_index]
		input_field.caret_column = input_field.text.length()

func _history_down() -> void:
	if command_history.is_empty():
		return
	history_index = min(command_history.size(), history_index + 1)
	if input_field:
		if history_index >= command_history.size():
			input_field.text = ""
		else:
			input_field.text = command_history[history_index]
		input_field.caret_column = input_field.text.length()

func _print_line(text: String) -> void:
	if output_label:
		output_label.append_text(text + "\n")
	print("[Console] " + text.replace("[color=", "").replace("[/color]", "").replace("green]", "").replace("red]", "").replace("yellow]", "").replace("cyan]", ""))

## Level generation command
func _cmd_level(args: Array) -> void:
	var level_seed: int = 0
	if args.size() >= 1 and args[0].is_valid_int():
		level_seed = int(args[0])
	else:
		level_seed = randi()
	
	# Find or create LevelGenerator
	var level_gen = get_tree().get_first_node_in_group("level_generator")
	if not level_gen:
		var LevelGeneratorScript = load("res://scripts/level/level_generator.gd")
		level_gen = LevelGeneratorScript.new()
		level_gen.name = "LevelGenerator"
		get_tree().current_scene.add_child(level_gen)
		_print_line("[color=yellow]Created LevelGenerator[/color]")
	
	# Generate level
	level_gen.generate_level(level_seed)
	
	# Spawn player in start room
	await get_tree().process_frame
	level_gen.spawn_player_in_start_room()
	
	_print_line("[color=green]Generated level with seed: %d[/color]" % level_seed)
	_print_line("[color=cyan]Rooms: %d | Use portals to navigate[/color]" % level_gen.rooms.size())

## Spawn a single room sphere
func _cmd_room(args: Array) -> void:
	var type_str: String = "normal" if args.size() < 1 else args[0]
	
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		_print_line("[color=red]Player not found[/color]")
		return
	
	# Get spawn position in front of player
	var spawn_pos: Vector3 = player.global_position + player.get_camera_direction() * 30
	
	# Parse room type (using integers to avoid class_name dependency)
	# 0=NORMAL, 1=BOSS, 2=ITEM, 3=SHOP, 4=GAMBLING, 5=SPECIAL
	var room_type: int = 0
	var room_color: Color = Color(0.2, 0.8, 1.0)  # Cyan default
	var size_mult: float = 1.0
	var room_name: String = "Normal"
	
	match type_str:
		"normal":
			room_type = 0
			room_color = Color(0.2, 0.8, 1.0)  # Cyan
			size_mult = 1.0
			room_name = "Normal"
		"boss":
			room_type = 1
			room_color = Color(1.0, 0.2, 0.2)  # Red
			size_mult = 2.0
			room_name = "Boss"
		"item":
			room_type = 2
			room_color = Color(1.0, 0.85, 0.2)  # Gold
			size_mult = 1.0
			room_name = "Item"
		"shop":
			room_type = 3
			room_color = Color(1.0, 0.6, 0.2)  # Orange
			size_mult = 1.0
			room_name = "Shop"
		"gambling":
			room_type = 4
			room_color = Color(0.6, 0.2, 1.0)  # Purple
			size_mult = 1.0
			room_name = "Gambling"
		"special":
			room_type = 5
			room_color = Color(0.2, 0.4, 1.0)  # Blue
			size_mult = 1.0
			room_name = "Special"
		_:
			_print_line("[color=red]Unknown room type: %s[/color]" % type_str)
			_print_line("  Valid: normal, boss, item, shop, gambling, special")
			return
	
	# Create room sphere using explicit script loading
	var RoomSphereScript = load("res://scripts/geometry4d/room_sphere4d.gd")
	var room = RoomSphereScript.new()
	room.room_type = room_type
	room.radius = 20.0
	room.size_multiplier = size_mult
	room.room_color = room_color
	room.glow_color = room_color
	room.position_4d = Vector4(spawn_pos.x, spawn_pos.y, spawn_pos.z, 0.0)
	room.slice_threshold = room.radius * size_mult + 10.0
	room.name = "Room_%s" % room_name
	
	get_tree().current_scene.add_child(room)
	room.global_position = spawn_pos
	
	# Notify surface walkers
	await get_tree().process_frame
	for walker in get_tree().get_nodes_in_group("surface_walkers_4d"):
		if walker.has_method("refresh_surfaces"):
			walker.refresh_surfaces()
	
	_print_line("[color=green]Spawned %s room at %s[/color]" % [room_name, str(spawn_pos)])
