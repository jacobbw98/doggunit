extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var slicer := Slicer4D.new()
	stage.add_child(slicer)
	for outward in [Vector3.RIGHT, Vector3.DOWN, Vector3(1, 0.35, 1).normalized()]:
		# Neighbor first in the scene tree reproduces the ambiguous boundary lookup.
		var neighbor := RoomSphere4D.new()
		neighbor.room_id = 1
		neighbor.position_4d = Vector4(outward.x * 40, outward.y * 40, outward.z * 40, 0)
		root.add_child(neighbor)
		var home := RoomSphere4D.new()
		home.room_id = 2
		root.add_child(home)
		var door := PortalDoor.new()
		var other := PortalDoor.new()
		home.add_child(door)
		neighbor.add_child(other)
		door.position_on_sphere(home, outward)
		other.position_on_sphere(neighbor, -outward)
		door.link_to_portal(other)
		home.add_portal(door)
		neighbor.add_portal(other)
		home.set_combat_locked(true)
		await physics_frame
		await physics_frame
		for kind in range(5):
			var enemy := Enemy4D.new()
			enemy.archetype = kind
			enemy.enable_4d_mode = false
			enemy.set_meta("encounter_room", home.room_id)
			root.add_child(enemy)
			enemy.set_physics_process(false)
			enemy.set_aggro_enabled(false)
			enemy.global_position = outward * 19.15
			enemy.position_4d = Vector4D.from_vector3(enemy.global_position, 0)
			enemy.velocity = Vector3.ZERO
			enemy._physics_process(1.0 / 60.0)
			check(enemy.global_position.dot(outward) < 20.0, "Enemy %d stays on home side of closed portal (%s)" % [kind, outward])
			check(enemy.up_direction.dot(-outward) > 0.9, "Enemy uses home-room gravity at shared boundary")
			# Frozen knockback must obey the same room boundary as regular locomotion.
			enemy.frozen_timer = 2.0
			enemy.external_velocity = outward * 160.0
			for frame in range(8):
				await physics_frame
				enemy._physics_process(1.0 / 60.0)
				check(enemy.global_position.dot(outward) < 20.0, "Frozen knockback cannot push an enemy through its closed exit")
			check(enemy.global_position.distance_to(home.global_position) <= home.radius - 0.79, "Enemy remains contained after knockback")
			enemy.free()
		home.free()
		neighbor.free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("ENEMY PORTAL CONTAINMENT PASSED: five archetypes, three portal orientations, home gravity and frozen knockback")
	quit(0 if failures.is_empty() else 1)
