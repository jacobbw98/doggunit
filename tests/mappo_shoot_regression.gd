extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
		push_error(description)

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var stats := GunStats.new()
	stats.mascot_visual = true
	stats.fire_rate = 0.06
	stats.crit_chance = 0.0
	var gun := Gun.new()
	gun.stats = stats
	stage.add_child(gun)
	var mascot := gun.mascot_model as GeneratedMascot
	check(mascot != null, "Real mascot weapon instantiates the imported model")
	if mascot == null:
		quit(1)
		return
	# Let the renderer finish creating the imported material instances.
	await process_frame
	var players := mascot.imported_model.find_children("*", "AnimationPlayer", true, false)
	check(not players.is_empty(), "Imported model contains AnimationPlayer")
	var jaws := mascot.imported_model.find_children("Mappo_JawPivot", "Node3D", true, false)
	check(not jaws.is_empty(), "Imported model contains a separate hinged jaw")
	if players.is_empty() or jaws.is_empty():
		quit(1)
		return
	var player := players[0] as AnimationPlayer
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var jaw := jaws[0] as Node3D
	var closed_basis := jaw.basis
	check(not mascot.animate, "Held weapon disables idle breathing")
	gun.fire(Vector3.ZERO, Vector3.FORWARD)
	check(gun.current_ammo == 29, "Actual firing consumes ammunition")
	check(player.is_playing(), "Actual firing starts the imported mouth animation with idle off")
	var clip := player.get_animation(player.current_animation)
	check(clip != null, "The shooting clip is present")
	if clip == null:
		quit(1)
		return
	check(clip.loop_mode == Animation.LOOP_NONE, "Shooting mouth animation is non-looping")
	check(clip.length >= 0.20 and clip.length <= 0.50, "Shooting cycle stays brief")
	check(jaw.basis.is_equal_approx(closed_basis), "The shooting cycle starts with the jaw closed")
	player.advance(0.12)
	var open_angle := closed_basis.get_rotation_quaternion().angle_to(jaw.basis.get_rotation_quaternion())
	check(open_angle > 0.30, "The jaw visibly opens during a shot")
	gun._process(0.12)
	gun.fire(Vector3.ZERO, Vector3.FORWARD)
	check(gun.current_ammo == 28, "Rapid repeat firing consumes another round")
	check(is_zero_approx(player.current_animation_position), "Rapid repeat firing restarts the clip at the beginning")
	check(jaw.basis.is_equal_approx(closed_basis), "A restarted shot applies its closed first pose immediately")
	player.advance(clip.length + 0.02)
	check(not player.is_playing(), "The mouth animation stops after one shooting cycle")
	check(jaw.basis.is_equal_approx(closed_basis), "The jaw closes at the end of the shooting cycle")
	gun._process(clip.length)
	gun.current_ammo = 0
	gun.fire(Vector3.ZERO, Vector3.FORWARD)
	check(not player.is_playing(), "Dry firing leaves the closed jaw at rest")
	var fallback := GeneratedMascot.new()
	fallback.animate = false
	stage.add_child(fallback)
	fallback.bark()
	fallback._process(0.15)
	check(fallback.body_root.scale.y > 1.0, "A missing animation preserves the existing shot pulse without an error")
	for projectile in get_nodes_in_group("projectiles"):
		projectile.set_physics_process(false)
	stage.queue_free()
	await process_frame
	if failures.is_empty():
		print("MAPPO SHOOT REGRESSION PASSED: imported jaw, real firing, opening/closing, rapid restart, dry firing, missing-clip fallback")
	quit(0 if failures.is_empty() else 1)
