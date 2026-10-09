extends SceneTree

class LayoutRoom extends Node3D:
	var room_id: int = 7
	var room_type: int = RoomTypes.Type.SHOP
	var radius: float = 20.0
	var graph_visible: bool = true
	var position_4d := Vector4D.zero()
	var portals: Array = []

class LayoutPortal extends Node3D:
	var portal_radius: float = 2.0
	var available: bool = true

class LayoutPlayer extends Node3D:
	var position_4d := Vector4D.zero()
	var camera: Camera3D
	var weapon_manager: WeaponManager

class LayoutRun extends Node:
	var player: Node3D
	var current_room_id: int = 7
	var current_floor: int = 1
	var loading: bool = false
	var bones: int = 30
	var active_item: Dictionary = {}
	var weapon_manager: WeaponManager
	var _rng := RandomNumberGenerator.new()

var failures: Array[String] = []
var run: LayoutRun
var player: LayoutPlayer
var checked_entries: int = 0
var minimum_clearance: float = INF

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	run = LayoutRun.new()
	root.add_child(run)
	player = LayoutPlayer.new()
	root.add_child(player)
	run.player = player
	_test_generated_layouts()
	_test_hidden_portal_and_surface_axes()
	_test_real_population()
	_test_item_room_unchanged()
	if failures.is_empty():
		print("SHOP LAYOUT PASSED: 120 generated seeds, %d doorway entries, %.2f m minimum clear corridor, hidden portals, tilted surfaces, persistent stock and slots" % [checked_entries, minimum_clearance])
	else:
		print("SHOP LAYOUT FAILED: ", failures)
	quit(0 if failures.is_empty() else 1)

func _make_room(center: Vector3 = Vector3.ZERO, orientation: Basis = Basis.IDENTITY) -> LayoutRoom:
	var room := LayoutRoom.new()
	# Geometry tests do not advance shopkeeper animation or pedestal timers.
	room.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(room)
	room.global_transform = Transform3D(orientation, center)
	return room

func _add_portal(room: LayoutRoom, direction: Vector3, hidden: bool = false) -> LayoutPortal:
	var portal := LayoutPortal.new()
	room.add_child(portal)
	portal.global_position = room.global_position + direction.normalized() * room.radius
	portal.available = not hidden
	portal.visible = not hidden
	room.portals.append(portal)
	return portal

func _place_player(room: LayoutRoom, outward: Vector3, bearing: float = 0.0) -> void:
	var tangent := RoomEconomy._surface_right(outward).cross(-outward).normalized()
	tangent = tangent.rotated(outward, bearing)
	player.global_position = room.global_position + outward * (room.radius - 2.0)
	player.global_basis = Basis.looking_at(tangent, -outward)
	player.position_4d = Vector4D.from_vector3(player.global_position, room.position_4d.w)
	run.current_room_id = room.room_id

func _check_actor(room: LayoutRoom, actor: Node3D, context: String) -> void:
	var radial := actor.global_position - room.global_position
	check(absf(radial.length() - (room.radius - 0.04)) < 0.001, context + ": actor remains grounded inside its sphere")
	check(actor.global_basis.y.normalized().dot(-radial.normalized()) > 0.999, context + ": actor stands upright on its local curved floor")
	for portal: Node3D in room.portals:
		var portal_direction := (portal.global_position - room.global_position).normalized()
		# Measure the walking corridor along the curved floor, allowing the
		# doorway's entire opening and the model's footprint on either side.
		var corridor := radial.normalized().angle_to(portal_direction) * room.radius - float(portal.get("portal_radius")) - RoomEconomy.COMMERCE_FOOTPRINT
		minimum_clearance = minf(minimum_clearance, corridor)
		check(corridor >= RoomEconomy.COMMERCE_PORTAL_CLEARANCE - 0.001, context + ": portal corridor is %.3f m, expected at least 10 m" % corridor)

func _check_anchor(room: LayoutRoom, offsets: Array[float], context: String) -> void:
	var entry := (player.global_position - room.global_position).normalized()
	var anchor := RoomEconomy._commerce_direction(run, room, offsets)
	check(anchor.is_finite() and is_equal_approx(anchor.length(), 1.0), context + ": anchor is a finite surface direction")
	check(entry.angle_to(anchor) * room.radius >= RoomEconomy.COMMERCE_ENTRY_DISTANCE - 0.001, context + ": commerce is at least 14 m from its entry location")
	var rng_state := run._rng.state
	var repeated := RoomEconomy._commerce_direction(run, room, offsets)
	check(anchor.is_equal_approx(repeated) and run._rng.state == rng_state, context + ": layout does not depend on or consume reward randomness")
	var actor := Node3D.new()
	room.add_child(actor)
	var right := RoomEconomy._surface_right(anchor)
	for offset in offsets:
		var direction := (anchor + right * offset / room.radius).normalized()
		RoomEconomy.place_on_surface(actor, room, direction, entry)
		_check_actor(room, actor, context + " offset %.1f" % offset)
	actor.free()
	checked_entries += 1

func _test_generated_layouts() -> void:
	var generator := LevelGenerator.new()
	root.add_child(generator)
	generator.set_process(false)
	var shop_offsets: Array[float] = [-3.2, 0.0, 3.2, 5.0]
	var slot_offsets: Array[float] = [0.0]
	for seed_value in range(1, 121):
		generator.num_normal_rooms = [1, 5, 15][seed_value % 3]
		generator.num_secret_rooms = seed_value % 4
		generator._rng.seed = seed_value
		generator.layout_style = seed_value % 3
		generator._generate_branching_graph()
		generator._assign_room_types()
		var positions: Dictionary = {}
		for attempt in range(16):
			positions = generator._layout_positions()
			if not positions.is_empty():
				break
		check(not positions.is_empty(), "Seed %d has a generated physical layout" % seed_value)
		if positions.is_empty():
			continue
		var orientation := Basis.from_euler(Vector3(0.37, seed_value * 0.131, -0.29))
		for id in generator.room_graph:
			var data: Dictionary = generator.room_graph[id]
			if data.type not in [RoomTypes.Type.SHOP, RoomTypes.Type.GAMBLING]:
				continue
			var room := _make_room(positions[id] + Vector3(23, -17, 11), orientation)
			room.room_type = data.type
			room.room_id = id
			room.position_4d.w = seed_value * 100.0
			for neighbor in data.connections:
				var direction: Vector3 = orientation * data.portal_dirs[neighbor]
				_add_portal(room, direction, generator.room_graph[neighbor].type == RoomTypes.Type.SECRET)
			for entry_portal: Node3D in room.portals:
				var entry := (entry_portal.global_position - room.global_position).normalized()
				_place_player(room, entry, seed_value * 0.41)
				_check_anchor(room, shop_offsets if data.type == RoomTypes.Type.SHOP else slot_offsets, "Seed %d room %d" % [seed_value, id])
			room.free()
	generator.free()

func _test_hidden_portal_and_surface_axes() -> void:
	var offsets: Array[float] = [-3.2, 0.0, 3.2, 5.0]
	for entry in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var room := _make_room(Vector3(51, -28, 13), Basis.from_euler(Vector3(0.5, 0.9, -0.4)))
		_place_player(room, entry)
		_add_portal(room, entry)
		var tangent: Vector3 = (-player.global_basis.z).slide(entry).normalized()
		var preferred: Vector3 = (entry * cos(14.0 / room.radius) + tangent * sin(14.0 / room.radius)).normalized()
		var hidden := _add_portal(room, preferred, true)
		_add_portal(room, (entry * cos(1.4) - tangent * sin(1.4)).normalized())
		var actual := RoomEconomy._commerce_direction(run, room, offsets)
		check(not actual.is_equal_approx(preferred), "A hidden doorway at the preferred location moves the whole shop away")
		_check_anchor(room, offsets, "Axis " + str(entry))
		hidden.available = true
		hidden.visible = true
		check(actual.is_equal_approx(RoomEconomy._commerce_direction(run, room, offsets)), "Revealing a reserved doorway does not change the safe shop layout")
		room.free()

func _test_real_population() -> void:
	for kind in [RoomTypes.Type.SHOP, RoomTypes.Type.GAMBLING]:
		var room := _make_room(Vector3(71, 32, -44), Basis.from_euler(Vector3(-0.3, 1.1, 0.4)))
		room.room_type = kind
		room.position_4d.w = 400.0
		var entry := Vector3(-0.4, -0.8, 0.3).normalized()
		_add_portal(room, entry)
		_add_portal(room, Vector3(0.5, -0.3, 0.8).normalized(), true)
		_add_portal(room, Vector3(0.2, 0.9, -0.3).normalized())
		_place_player(room, entry)
		run._rng.seed = 11
		RoomEconomy.populate_room(run, room)
		var actors: Array[Node3D] = []
		for child in room.get_children():
			if child is ItemPedestal or child is SlotMachine or child.name == "MildredsCounter":
				actors.append(child)
		check(actors.size() >= 2 if kind == RoomTypes.Type.SHOP else actors.size() == 1, "Native shop or slot actors populate once")
		var transforms: Array[Transform3D] = []
		for actor in actors:
			_check_actor(room, actor, "Native commerce " + str(actor.name))
			transforms.append(actor.global_transform)
			if actor is ItemPedestal or actor is SlotMachine:
				player.global_position = actor.global_position + actor.global_basis.y * 2.0 - actor.global_basis.z * 3.0
				player.position_4d = Vector4D.from_vector3(player.global_position, room.position_4d.w)
				player.global_basis = actor.global_basis
				check(RoomEconomy.can_interact(run, room, actor), "Relocated " + str(actor.name) + " remains reachable from normal player height")
		var child_count := room.get_child_count()
		_place_player(room, -entry, 1.7)
		player.position_4d.w += 100.0
		RoomEconomy.populate_room(run, room)
		player.position_4d.w = room.position_4d.w
		RoomEconomy.populate_room(run, room)
		check(room.get_child_count() == child_count, "Returning through another portal or W slice does not duplicate commerce actors")
		for index in range(actors.size()):
			check(actors[index].global_transform.is_equal_approx(transforms[index]), "Shop and slot placements persist across room reentry")
		room.free()

func _test_item_room_unchanged() -> void:
	var room := _make_room()
	room.room_type = RoomTypes.Type.ITEM
	_place_player(room, Vector3.DOWN)
	var expected := RoomEconomy._display_direction(run, room)
	var choices := RoomEconomy.spawn_reward(run, room, 2, true)
	var midpoint := Vector3.ZERO
	for pedestal: Node3D in choices:
		midpoint += (pedestal.global_position - room.global_position).normalized()
	midpoint = midpoint.normalized()
	check(expected.is_equal_approx(midpoint), "Free item choices retain their nearby entry placement")
	check(absf(Vector3.DOWN.angle_to(midpoint) * room.radius - 4.0) < 0.001, "Only shop and slot layouts move farther from entry")
	room.free()
