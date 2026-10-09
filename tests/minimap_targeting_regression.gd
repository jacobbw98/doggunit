extends SceneTree

class TestRoom:
	extends Node3D
	var room_id: int = 0
	var radius: float = 20.0
	var portals: Array = []
	func get_portals() -> Array:
		return portals

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
		push_error(description)

func _door(room: TestRoom, target: TestRoom, at: Vector3) -> PortalDoor:
	var portal := PortalDoor.new()
	room.add_child(portal)
	portal.source_room = room
	portal.target_room = target
	portal.global_position = at
	portal.set_process(false)
	room.portals.append(portal)
	return portal

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var room := TestRoom.new()
	var target := TestRoom.new()
	var unknown := TestRoom.new()
	target.room_id = 1
	unknown.room_id = 2
	world.add_child(room)
	world.add_child(target)
	world.add_child(unknown)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current = true
	# Load after autoload startup; RunManager's GameManager singleton is then registered.
	var map: Control = load("res://scripts/player/room_minimap.gd").new()
	root.add_child(map)
	map.set_process(false)
	map.visited = {0: true, 1: true}
	var portal := _door(room, target, Vector3(0, 0, -10))
	check(map.get_targeted_room_id(camera, room) == 1, "Crosshair targets the explored destination")
	map.visited.erase(1)
	check(map.get_targeted_room_id(camera, room) == -1 and map.visited.keys() == [0], "Aimed unknown doorway cannot reveal its destination")
	map.visited[1] = true
	camera.rotation.y = PI / 2.0
	check(map.get_targeted_room_id(camera, room) == -1, "Looking away clears the highlight")
	camera.rotation = Vector3.ZERO
	portal.position.x = 2.1
	check(map.get_targeted_room_id(camera, room) == -1, "Ray outside circular aperture does not target its room")
	portal.position.x = 1.9
	check(map.get_targeted_room_id(camera, room) == 1, "Ray inside aperture edge still targets room")
	portal.position.x = 0.0
	portal.source_room = target
	check(map.get_targeted_room_id(camera, room) == -1, "A door belonging to another room cannot be targeted")
	portal.source_room = room
	portal.available = false
	check(map.get_targeted_room_id(camera, room) == -1, "Unavailable secret portal remains hidden from aim")
	portal.available = true
	portal.hide()
	check(map.get_targeted_room_id(camera, room) == -1, "Hidden portal remains untargetable")
	portal.show()
	room.hide()
	check(map.get_targeted_room_id(camera, room) == -1, "Invisible room layer remains untargetable")
	room.show()
	portal.position.z = 10
	check(map.get_targeted_room_id(camera, room) == -1, "Door behind camera does not highlight")
	portal.position.z = -45
	check(map.get_targeted_room_id(camera, room) == -1, "Ray does not select a door beyond the current sphere")
	portal.position.z = -10
	var closer := _door(room, unknown, Vector3(0, 0, -5))
	check(map.get_targeted_room_id(camera, room) == -1, "Near unknown portal occludes farther explored destination without leaking fog")
	map.visited[2] = true
	check(map.get_targeted_room_id(camera, room) == 2, "Nearest visible doorway wins when both are explored")
	closer.hide()
	portal.set_combat_lock(room, true)
	check(portal.combat_locked and portal.portal_surface.visible, "Test doorway is actually sealed for combat")
	check(map.get_targeted_room_id(camera, room) == 1, "Visible combat-locked door still highlights its explored destination")
	# Rotate the whole camera/door arrangement, including a ceiling-facing view.
	for rotation in [Vector3(PI / 2.0, 0, 0), Vector3(0.7, 1.2, 0.9), Vector3(-1.1, -0.6, 2.4)]:
		world.rotation = rotation
		world.position = Vector3(70, -35, 15)
		check(map.get_targeted_room_id(camera, room) == 1, "Spherical camera and rotated doorway preserve crosshair targeting")
	check(map.get_targeted_room_id(null, room) == -1 and map.get_targeted_room_id(camera, null) == -1, "Missing camera or current room clears target safely")
	if failures.is_empty():
		print("MINIMAP TARGETING PASSED: explored-only targets, look-away, disc edge, source ownership, hidden secrets, nearest hit, locks, sphere rotation")
	world.queue_free()
	map.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
