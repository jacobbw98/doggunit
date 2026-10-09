extends SceneTree

const SHOPKEEPER_SCRIPT = preload("res://scripts/items/mildred_shopkeeper.gd")

class FakeRoom extends Node3D:
	var room_id := 1
	var radius := 20.0
	var graph_visible := true
	var position_4d := Vector4D.zero()

class FakeRun extends Node:
	var player: Node3D
	var loading := false
	var current_room_id := 1

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var room := FakeRoom.new()
	stage.add_child(room)
	var run := FakeRun.new()
	stage.add_child(run)
	var player: Node3D = load("res://scenes/player/player.tscn").instantiate()
	stage.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	run.player = player
	player.position_4d = Vector4D.zero()
	var mascot_gun := Gun.new()
	mascot_gun.stats = GunStats.new()
	mascot_gun.stats.mascot_visual = true
	player.weapon_manager.pickup_gun(mascot_gun)
	var other_gun := Gun.new()
	other_gun.stats = GunStats.new()
	player.weapon_manager.pickup_gun(other_gun)
	var shopkeeper: Node3D = SHOPKEEPER_SCRIPT.new()
	shopkeeper.configure(run, room)
	room.add_child(shopkeeper)
	shopkeeper.position = Vector3(0, -19.96, 0)
	player.position = shopkeeper.position + Vector3(0, 2.0, -3.0)
	player.basis = Basis.IDENTITY
	player.camera.rotation = Vector3.ZERO
	shopkeeper._process(0.0)
	check(shopkeeper.name == "MildredsCounter" and shopkeeper.has_node("Mildred"), "The existing shopkeeper node path is preserved")
	check(shopkeeper.box_stack.get_child_count() == 3, "Mildred stands on exactly three stationary cardboard boxes")
	var stack_bounds := RoomEconomy.model_bounds(shopkeeper.box_stack)
	check(absf(stack_bounds.size.y - shopkeeper.STACK_HEIGHT) < 0.03, "The three boxes form the intended 2.44m perch")
	var target: Vector3 = shopkeeper.get_gun_target(mascot_gun)
	check(absf((shopkeeper.get_eye_position() - target).dot(shopkeeper.global_basis.y)) < 0.20, "Mildred's eye height matches the actual held Mappo model")
	check(shopkeeper.is_tracking and shopkeeper.tracked_gun == mascot_gun, "Mildred targets the actual current equipped dog")
	_check_aim(shopkeeper, target, "Mildred aims directly at the held dog from her eye midpoint")
	var original := RoomEconomy.make_model("mildred", 1.20, true)
	var original_bounds := RoomEconomy.model_bounds(original, original.transform)
	var geometry_count := _triangle_count(original)
	shopkeeper._rest_pose()
	var rebuilt_bounds := RoomEconomy.model_bounds(shopkeeper.body)
	check(absf(rebuilt_bounds.size.y - original_bounds.size.y) < 0.0001, "Splitting the head preserves Mildred's original 1.20m size")
	check(_triangle_count(shopkeeper.body) == geometry_count, "Every original GLB triangle is preserved when separating the head")
	original.free()
	var box_pose: Transform3D = shopkeeper.box_stack.global_transform
	for offset in [Vector3(4, 2, -2), Vector3(-3, 2, 2), Vector3(0.3, 2.6, -1.5)]:
		player.position = shopkeeper.position + offset
		player.camera.rotation.x = 0.18
		shopkeeper._process(0.0)
		_check_aim(shopkeeper, shopkeeper.get_gun_target(mascot_gun), "Gaze follows the moving gun without lag")
		check(shopkeeper.box_stack.global_transform.is_equal_approx(box_pose), "Tracking does not rotate the supporting boxes")
		check(shopkeeper.body.global_basis.y.dot(shopkeeper.global_basis.y) > 0.9999, "Body yaw stays upright in the surface gravity frame")
	player.weapon_manager.switch_to_weapon(1)
	shopkeeper._process(0.0)
	check(shopkeeper.tracked_gun == other_gun, "Changing weapon slots immediately targets the selected new dog")
	_check_aim(shopkeeper, shopkeeper.get_gun_target(other_gun), "The smaller regular dog is tracked directly too")
	# Rotate the whole shop onto a wall while keeping gun and player in that
	# surface's gravity frame; no world-Y assumptions should affect the stare.
	shopkeeper.basis = Basis(Vector3.FORWARD, 1.15)
	player.global_position = shopkeeper.global_transform * Vector3(3.0, 2.0, -2.5)
	player.global_basis = shopkeeper.global_basis
	player.camera.rotation = Vector3(0.22, -0.35, 0)
	shopkeeper._process(0.0)
	_check_aim(shopkeeper, shopkeeper.get_gun_target(other_gun), "Curved-gravity shop placement preserves exact gaze alignment")
	check(shopkeeper.body.global_basis.y.dot(shopkeeper.global_basis.y) > 0.9999, "Mildred remains seated upright on a curved room surface")
	run.current_room_id = 2
	shopkeeper._process(0.0)
	check(not shopkeeper.is_tracking and shopkeeper.tracked_gun == null, "Leaving the shop stops tracking the player")
	run.current_room_id = 1
	player.position_4d.w = 2.0
	shopkeeper._process(0.0)
	check(not shopkeeper.is_tracking, "A different W slice cannot keep the shopkeeper tracking")
	player.position_4d.w = 25.0
	shopkeeper._process(0.0)
	check(not shopkeeper.visible, "The shopkeeper and boxes hide outside the room's visible W slice")
	player.position_4d.w = 0.0
	shopkeeper._process(0.0)
	check(shopkeeper.visible and shopkeeper.is_tracking, "Returning to the shop resumes current-dog tracking")
	stage.queue_free()
	await process_frame
	if failures.is_empty():
		print("MILDRED TRACKING PASSED: three-box height, exact dog gaze, original geometry, gun swaps, fixed boxes, curved gravity, room and W gating")
	quit(0 if failures.is_empty() else 1)

func _check_aim(shopkeeper: Node3D, target: Vector3, message: String) -> void:
	var direction: Vector3 = (target - shopkeeper.get_eye_position()).normalized()
	check(shopkeeper.get_gaze_direction().dot(direction) > 0.99999, message)

func _triangle_count(model: Node) -> int:
	var total := 0
	var pending: Array[Node] = [model]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D and node.mesh:
			for surface in range(node.mesh.get_surface_count()):
				var arrays: Array = node.mesh.surface_get_arrays(surface)
				var indices = arrays[Mesh.ARRAY_INDEX]
				total += (indices.size() if indices != null and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()) / 3
		for child in node.get_children():
			pending.append(child)
	return total
