extends SceneTree

class TestRoom extends Node3D:
	var position_4d := Vector4.ZERO
	var room_id := 0
	var radius := 20.0
	var portals: Array = []
	func get_spawn_position() -> Vector3:
		return global_position + Vector3.DOWN * 15.0
	func get_portals() -> Array:
		return portals

class TestBody extends CharacterBody3D:
	var position_4d := Vector4D.zero()

class TestProjectile extends Area3D:
	var position_4d := Vector4D.zero()

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var source := TestRoom.new()
	var destination := TestRoom.new()
	destination.position = Vector3(40, 0, 0)
	destination.position_4d = Vector4(40, 0, 0, 30)
	destination.room_id = 1
	root.add_child(source)
	root.add_child(destination)
	var doorway := PortalDoor.new()
	var receiving := PortalDoor.new()
	source.add_child(doorway)
	destination.add_child(receiving)
	doorway.position_on_sphere(source, Vector3.RIGHT)
	receiving.position_on_sphere(destination, Vector3.LEFT)
	doorway.link_to_portal(receiving)
	source.portals = [doorway]
	destination.portals = [receiving]
	doorway._is_ready_for_transitions = true
	receiving._is_ready_for_transitions = true
	var body := TestBody.new()
	root.add_child(body)
	body.add_to_group("player")
	body.global_position = doorway.to_global(Vector3(0, 0, 2))
	doorway._on_transition_body_entered(body)
	body.global_position = doorway.to_global(Vector3(0, 0, 5))
	doorway._on_transition_body_exited(body)
	check(is_zero_approx(body.position_4d.w), "Backing out of the approach must not change W")

	body.global_position = doorway.to_global(Vector3(0, 0, 2))
	doorway._on_transition_body_entered(body)
	body.velocity = Vector3(5, 1, 2)
	body.global_position = doorway.to_global(Vector3(0, 0, -0.2))
	var crossing_position := body.global_position
	var crossing_velocity := body.velocity
	doorway._update_w_transitions(1.0 / 60.0)
	check(is_equal_approx(body.position_4d.w, 30.0), "Crossing the plane must change to the destination W")
	check(body.global_position.is_equal_approx(crossing_position), "Crossing must never teleport XYZ")
	check(body.velocity.is_equal_approx(crossing_velocity), "Crossing must preserve velocity without a launch")
	receiving._on_transition_body_entered(body)
	body.global_position = receiving.to_global(Vector3(0, 0, -0.2))
	receiving._update_w_transitions(1.0 / 60.0)
	check(is_zero_approx(body.position_4d.w), "An immediate deliberate return must not be blocked by a cooldown")
	receiving._on_transition_body_exited(body)

	doorway._on_transition_body_exited(body)
	body.position_4d.w = 0.0
	body.global_position = doorway.to_global(Vector3(3, 0, 2))
	doorway._on_transition_body_entered(body)
	body.global_position = doorway.to_global(Vector3(3, 0, -1))
	doorway._update_w_transitions(1.0 / 60.0)
	check(is_zero_approx(body.position_4d.w), "Crossing outside the circular aperture must not transition")
	check(not doorway.contains_aperture(doorway.to_global(Vector3(1.9, 1.9, 0))), "A trigger-box corner is not a hole")
	doorway.set_available(false)
	check(not doorway.contains_aperture(doorway.global_position), "An undiscovered portal must not create a floor hole")
	doorway.set_available(true)
	body.free()
	var projectile := TestProjectile.new()
	root.add_child(projectile)
	projectile.add_to_group("projectiles")
	projectile.global_position = doorway.to_global(Vector3(0, 0, 2))
	doorway._on_transition_area_entered(projectile)
	check(is_zero_approx(projectile.position_4d.w), "Projectile approach must not change its visible slice")
	projectile.global_position = doorway.to_global(Vector3(0, 0, -1))
	var projectile_position := projectile.global_position
	doorway._update_projectile_transitions()
	check(is_equal_approx(projectile.position_4d.w, 30), "Projectile plane crossing must follow the destination slice")
	check(projectile.global_position.is_equal_approx(projectile_position), "Projectile crossing must preserve XYZ")
	destination.position_4d.w = 0.0
	projectile.position_4d.w = 0.0
	projectile.global_position = doorway.to_global(Vector3(0, 0, 2))
	doorway._on_transition_area_entered(projectile)
	projectile.global_position = doorway.to_global(Vector3(0, 0, -1))
	doorway._update_projectile_transitions()
	check(is_zero_approx(projectile.position_4d.w), "Projectile must share a W-synced room's visible slice instead of its cached home W")
	destination.position_4d.w = 30.0
	doorway._on_transition_area_exited(projectile)
	projectile.free()

	# The exact antipodal gravity change at two tangent spheres must remain finite
	# and converge; lerp(normal, -normal) otherwise never leaves the source normal.
	var controller = load("res://scripts/player/player_controller.gd").new()
	controller.current_gravity_up = Vector3.LEFT
	controller.sphere_facing = Vector3.FORWARD
	for frame in 120:
		controller._align_to_gravity(Vector3.RIGHT, 1.0 / 60.0)
		check(controller.current_gravity_up.is_finite(), "Gravity interpolation must remain finite")
		check(absf(controller.current_gravity_up.dot(controller.sphere_facing)) < 0.001, "Facing must remain tangent during gravity rotation")
	check(controller.current_gravity_up.dot(Vector3.RIGHT) > 0.999, "Antipodal gravity must reach the receiving room")
	controller.free()

	# Walk a real CharacterBody through two tangent rooms at a fixed physics rate.
	source.add_to_group("room_spheres_4d")
	destination.add_to_group("room_spheres_4d")
	for outward in [Vector3.RIGHT, Vector3.DOWN, Vector3(1, 0.35, 1).normalized()]:
		for move_speed in [8.0, 12.0]:
			destination.position = outward * 40.0
			doorway.position_on_sphere(source, outward)
			receiving.position_on_sphere(destination, -outward)
			var tangent: Vector3 = outward.cross(Vector3.UP).normalized()
			if tangent.is_zero_approx():
				tangent = Vector3.FORWARD
			var player = load("res://scenes/player/player.tscn").instantiate()
			root.add_child(player)
			player.global_position = outward * 17.9 + tangent * 1.5
			player.current_gravity_up = -outward
			player.sphere_facing = -tangent
			player.walk_speed = move_speed
			player.set_physics_process(false)
			Input.action_press("move_forward")
			var max_step := 0.0
			var last_position: Vector3 = player.global_position
			for frame in 120:
				await physics_frame
				player._physics_process(1.0 / 60.0)
				max_step = maxf(max_step, player.global_position.distance_to(last_position))
				last_position = player.global_position
			Input.action_release("move_forward")
			var case_name := "direction=%s speed=%s" % [outward, move_speed]
			check(player.global_position.dot(outward) > 20.5, "Walk must reach the receiving sphere: %s, position=%s" % [case_name, player.global_position])
			check(max_step < 0.35, "Walk must remain continuous: %s (max frame displacement %.3f)" % [case_name, max_step])
			check(is_equal_approx(player.position_4d.w, 30.0), "Physics-driven walk must commit W: %s" % case_name)
			player.free()
	source.free()
	destination.free()
	if failures.is_empty():
		print("PASS: portal crossing, backing out, aperture boundaries, hidden doors, gravity and continuous traversal")
	quit(0 if failures.is_empty() else 1)
