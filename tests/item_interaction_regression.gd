extends SceneTree

var failures: Array[String] = []
var acquired: Array[String] = []
var level: Node
var run: Node
var ui: Node
var capture_enabled := false

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	capture_enabled = OS.get_cmdline_user_args().has("--capture")
	if capture_enabled:
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1440, 810)
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
	check(not run.loading, "The real gameplay level loads")
	if run.loading:
		quit(1)
		return
	run.player.set_meta("god_mode", true)
	run.item_acquired.connect(func(item_name: String): acquired.append(item_name))
	var item_room: Node3D = await _enter_room(LevelGenerator.ROOM_ITEM)
	var choices := _stocks(item_room)
	check(choices.size() == 2, "The item room starts with two choices")
	if choices.size() != 2:
		quit(1)
		return
	var chosen: Node3D = choices[0]
	await _stand_in_front(chosen, 3.0)
	var grounded_height: float = (run.player.global_position - chosen.global_position).dot(chosen.global_basis.y)
	check(grounded_height > 1.7, "The test uses the actual grounded body clearance, with player physics enabled")
	ui._process(0.0)
	await process_frame
	check(ui.item_details.visible and ui.item_description.text == chosen.item.description + "\n" + chosen.item.flavor_text, "A nearby aimed item shows its description")
	check(ui.item_details.get_global_rect().position.y >= 311 and ui.item_details.get_global_rect().position.x >= 1560, "Item details appear below the top-right minimap")
	check(ui.item_description.get_global_rect().end.y <= ui.item_details.get_global_rect().end.y, "The description fits inside its panel")
	check(not ui.interaction.text.begins_with("F"), "Free rewards have no manual pickup prompt")
	await _capture("item-walk-pickup-gameplay.png")
	run.player.camera.rotation.y = PI
	ui._process(0.0)
	check(not ui.item_details.visible, "Looking away hides the item description")
	run.player.camera.rotation.y = 0
	var before := acquired.size()
	_move("move_forward", true)
	for frame in range(120):
		await physics_frame
		if not is_instance_valid(chosen) or chosen.is_queued_for_deletion():
			break
	_move("move_forward", false)
	await process_frame
	check(acquired.size() == before + 1 and _stocks(item_room).is_empty(), "Actual walking collects one free item and retires both choices without F")

	var shop: Node3D = await _enter_room(LevelGenerator.ROOM_SHOP)
	var stock: Node3D = _stocks(shop)[0]
	run.add_bones(stock.price + 30)
	await _stand_in_front(stock, 0.7)
	before = acquired.size()
	for frame in range(6):
		await physics_frame
	check(acquired.size() == before and is_instance_valid(stock), "Walking into shop stock cannot buy it automatically")
	await _stand_in_front(stock, 3.0)
	ui._process(0.0)
	check(ui._find_interactable(true) == stock and ui.interaction.text.begins_with("F"), "The displayed shop item can be targeted from normal eye height")
	await _capture("shop-manual-pickup-gameplay.png")
	var balance: int = run.bones
	var purchase_price: int = stock.price
	_key(KEY_F, true)
	await process_frame
	_key(KEY_F, false)
	await process_frame
	check(run.bones == balance - purchase_price and acquired.size() == before + 1, "A real F key event purchases exactly one item at its configured price")
	if capture_enabled:
		var keeper: Node3D = shop.get_node("MildredsCounter")
		await _stand_in_front(keeper, 5.0)
		run.player.camera.look_at(keeper.global_position + keeper.global_basis.y * 2.0, run.player.current_gravity_up)
		await _capture("mildred-box-stack-gameplay.png")

	var gambling: Node3D = await _enter_room(LevelGenerator.ROOM_GAMBLING)
	var machine: Node3D = gambling.get_node("BoneSlotMachine")
	await _stand_in_front(machine, 3.0)
	var bounds := RoomEconomy.model_bounds(machine)
	check(is_equal_approx(bounds.size.y, 4.2), "The imported slot machine is full gameplay size")
	check(ui._find_interactable(true) == machine, "The enlarged slot's reel display can be targeted")
	await _capture("slot-full-size-gameplay.png")
	balance = run.bones
	_key(KEY_F, true)
	await process_frame
	_key(KEY_F, false)
	await process_frame
	check(machine.spinning and run.bones == balance - 3, "A real F key event starts and pays for one slot spin")
	if capture_enabled:
		# Capture an actual enemy death burst while the player continues to stand
		# at normal height; the family regression checks its later collection.
		var enemy: Node3D = load("res://scripts/enemies/enemy_4d.gd").new()
		enemy.configure_archetype(Enemy4D.Archetype.BOSS, 1.0)
		enemy.initial_w = gambling.position_4d.w
		enemy.set_meta("encounter_room", gambling.room_id)
		gambling.add_child(enemy)
		var up: Vector3 = run.player.current_gravity_up
		var forward: Vector3 = run.player.global_basis.x
		enemy.global_position = run.player.global_position + forward * 4.0
		var death_position: Vector3 = enemy.global_position
		enemy.take_damage(10000, GunTypes.Type.EXPLOSIVE)
		run.player.camera.look_at(death_position + up * 1.0, up)
		await create_timer(0.3).timeout
		await _capture("enemy-bone-burst-gameplay.png")
	if failures.is_empty():
		print("ITEM INTERACTION PASSED: live grounded walking, automatic linked choice, aimed descriptions below minimap, manual shop F and full-size slot F")
	quit(0 if failures.is_empty() else 1)

func _enter_room(kind: int) -> Node3D:
	for room in run.generator.rooms:
		if room.room_type != kind:
			continue
		run.player.global_position = room.global_position + Vector3.DOWN * (room.radius - 2.0)
		run.player.position_4d = Vector4D.from_vector3(run.player.global_position, room.position_4d.w)
		run.player.global_basis = Basis.IDENTITY
		run.player.sphere_facing = Vector3.FORWARD
		run.player.current_gravity_up = Vector3.UP
		run.player.velocity = Vector3.ZERO
		run.player.camera.rotation = Vector3.ZERO
		run.generator.set_active_room(room.room_id)
		for frame in range(6):
			await physics_frame
		return room
	return null

func _stand_in_front(actor: Node3D, distance: float) -> void:
	var room: Node3D = run.generator.get_room(actor.room_id)
	var outward := (actor.global_position - room.global_position).normalized()
	var front: Vector3 = (-actor.global_basis.z).slide(outward).normalized()
	var direction: Vector3 = (outward + front * distance / room.radius).normalized()
	var up: Vector3 = -direction
	run.player.global_position = room.global_position + direction * (room.radius - 2.0)
	var forward: Vector3 = (actor.global_position - run.player.global_position).slide(up).normalized()
	run.player.global_basis = Basis.looking_at(forward, up)
	run.player.sphere_facing = forward
	run.player.current_gravity_up = up
	run.player.velocity = Vector3.ZERO
	run.player.camera.rotation = Vector3.ZERO
	run.player.camera.look_at(RoomEconomy.interaction_position(actor), up)
	for frame in range(6):
		await physics_frame

func _stocks(room: Node3D) -> Array:
	var result: Array = []
	for node in get_nodes_in_group("item_pedestals"):
		if node.room_id == room.room_id:
			result.append(node)
	return result

func _move(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func _capture(filename: String) -> void:
	if not capture_enabled:
		return
	for frame in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png("res://assets/items/source/" + filename)
	check(result == OK, "Native gameplay capture saves successfully")
