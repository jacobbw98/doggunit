extends SceneTree

class EncounterFixture extends Node:
	var rooms: Array = []
	var player: Node3D
	var _original_room_w := {0: 0.0, 1: 30.0}
	var current_lit_room_id := 0
	var lock_on_entry := true
	func set_active_room(id: int) -> void:
		current_lit_room_id = id
		for room in rooms:
			var p: Vector4 = room.position_4d
			room.position_4d = Vector4(p.x, p.y, p.z, player.position_4d.w)
			room.update_slice(player.position_4d.w)
		if id == 1 and lock_on_entry:
			rooms[1].set_combat_locked(true, player)

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var slicer := Slicer4D.new()
	root.add_child(slicer)
	for outward in [Vector3.RIGHT, Vector3.DOWN, Vector3(1, 0.35, 1).normalized()]:
		slicer.slice_w = 0.0
		var source := RoomSphere4D.new()
		var destination := RoomSphere4D.new()
		destination.room_id = 1
		destination.position_4d = Vector4(outward.x * 40, outward.y * 40, outward.z * 40, 30)
		root.add_child(source)
		root.add_child(destination)
		var doorway := PortalDoor.new()
		var receiving := PortalDoor.new()
		source.add_child(doorway)
		destination.add_child(receiving)
		doorway.position_on_sphere(source, outward)
		receiving.position_on_sphere(destination, -outward)
		doorway.link_to_portal(receiving)
		source.add_portal(doorway)
		destination.add_portal(receiving)
		doorway._is_ready_for_transitions = true
		receiving._is_ready_for_transitions = true
		check(not doorway.portal_surface.visible and not receiving.portal_surface.visible, "Unlocked openings must be completely clear on both sides")
		var tangent: Vector3 = outward.cross(Vector3.UP).normalized()
		if tangent.is_zero_approx():
			tangent = Vector3.FORWARD
		var player = load("res://scenes/player/player.tscn").instantiate()
		root.add_child(player)
		player.set_physics_process(false)
		player.global_position = outward * 17.9 + tangent * 1.5
		player.current_gravity_up = -outward
		player.sphere_facing = -tangent
		var fixture := EncounterFixture.new()
		fixture.rooms = [source, destination]
		fixture.player = player
		root.add_child(fixture)
		fixture.add_to_group("level_generator")
		fixture.set_active_room(0)
		Input.action_press("move_forward")
		var last: Vector3 = player.global_position
		var maximum_step := 0.0
		var tried_retreat := false
		for frame in 120:
			await physics_frame
			if destination.combat_locked and not tried_retreat:
				tried_retreat = true
				# The lock begins while the entrant is still straddling the plane.
				check(receiving._entrant_grace.has(player), "The closing doorway must allow the current capsule to finish entering")
				player.apply_external_force(-outward * 40.0)
				Input.action_release("move_forward")
				Input.action_press("move_backward")
			player._physics_process(1.0 / 60.0)
			maximum_step = maxf(maximum_step, player.global_position.distance_to(last))
			last = player.global_position
		Input.action_release("move_forward")
		Input.action_release("move_backward")
		check(tried_retreat and destination.combat_locked, "Entering the encounter must lock its exits")
		check(doorway.combat_locked and receiving.combat_locked, "Combat lock must apply to both sides")
		check(doorway.portal_surface.visible and receiving.portal_surface.visible, "Combat lock must show its glowing seal")
		check(player.global_position.dot(outward) > 21.5 and is_equal_approx(player.position_4d.w, 30), "Retreat and knockback during entry must not escape the encounter")
		check(receiving._entrant_grace.is_empty() and doorway._entrant_grace.is_empty(), "The capsule exception must retire after entry")
		check(maximum_step < 0.4, "Closing during entry must remain continuous, max step %.3f for %s" % [maximum_step, outward])
		check(not receiving.contains_player_aperture(receiving.global_position, player), "After entry the player must be physically blocked")
		check(not receiving.contains_aperture(receiving.global_position), "The same seal must block projectiles")
		destination.set_combat_locked(false)
		fixture.lock_on_entry = false
		await physics_frame
		check(not doorway.combat_locked and not receiving.combat_locked, "Clearing the encounter must unlock both sides")
		check(not doorway.portal_surface.visible and not receiving.portal_surface.visible, "Unlock must remove the surface completely")
		check(doorway._combat_seal_shape.disabled and receiving._combat_seal_shape.disabled, "Unlock must remove physical seals")
		player.free()
		fixture.free()
		source.free()
		destination.free()
	slicer.free()
	if failures.is_empty():
		print("PASS: combat seals close around entry without teleporting; retreat denied, grace expires, clear removes both visual and physical seals")
	quit(0 if failures.is_empty() else 1)
