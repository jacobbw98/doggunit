extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var results: Array[Vector3] = []
	for tick_rate in [30, 120]:
		Engine.physics_ticks_per_second = tick_rate
		await physics_frame
		var player = load("res://scenes/player/player.tscn").instantiate()
		root.add_child(player)
		player.set_physics_process(false)
		player.global_position = Vector3(0, 20, 0)
		player.freeze(2.0)
		player.apply_external_force(Vector3(12, 0, 0))
		Input.action_press("move_left")
		Input.action_press("jump")
		for frame in tick_rate:
			await physics_frame
			player._physics_process(1.0 / tick_rate)
			check(player.velocity.x <= 12.01, "Knockback must never reapply a consumed impulse")
		Input.action_release("move_left")
		Input.action_release("jump")
		check(player.velocity.x > 6.5, "Freeze must suppress movement controls without cancelling knockback")
		check(player.velocity.y < -9.0 and player.global_position.y < 16.0, "Freeze must continue gravity and movement")
		check(player.external_velocity.is_zero_approx(), "Impulse queue must be empty after movement")
		results.append(player.velocity)
		player.set_meta("god_mode", true)
		player.take_damage(1000)
		check(player.current_health == player.max_health, "God mode must ignore damage")
		player.set_meta("god_mode", false)
		player.take_damage(10)
		check(player.current_health == player.max_health - 10, "Disabling god mode must restore damage")
		player.free()
	check(results[0].distance_to(results[1]) < 0.15, "One-second impulse decay must agree at 30 and 120 physics ticks")
	Engine.physics_ticks_per_second = 60
	var moving_player = load("res://scenes/player/player.tscn").instantiate()
	root.add_child(moving_player)
	moving_player.set_physics_process(false)
	moving_player.fly_mode = true
	check(is_equal_approx(moving_player.walk_speed, 8.0), "Default movement must use the former 8 m/s sprint speed")
	Input.action_press("move_forward")
	await physics_frame
	moving_player._physics_process(1.0 / 60.0)
	var regular_speed: float = moving_player.velocity.length()
	var shift := InputEventKey.new()
	shift.keycode = KEY_SHIFT
	shift.physical_keycode = KEY_SHIFT
	shift.pressed = true
	Input.parse_input_event(shift)
	await physics_frame
	moving_player._physics_process(1.0 / 60.0)
	check(is_equal_approx(regular_speed, 8.0) and is_equal_approx(moving_player.velocity.length(), regular_speed), "Holding Shift must not change movement speed")
	shift.pressed = false
	Input.parse_input_event(shift)
	Input.action_release("move_forward")
	moving_player.free()
	if failures.is_empty():
		print("PASS: single knockback impulse, freeze gravity and input lock, 30/120 Hz decay, god mode, default 8 m/s and Shift-independent movement")
	quit(0 if failures.is_empty() else 1)
