extends SceneTree

class FixedRollEnemy extends Enemy4D:
	var fixture_roll := 0.99999
	func register_freezing_hit(roll: float = -1.0) -> bool:
		return super.register_freezing_hit(fixture_roll if roll < 0.0 else roll)

class TestRoom extends Node3D:
	var radius := 20.0
	var room_id := 10
	var _position_4d := Vector4D.zero()
	var graph_visible := true
	var portals: Array = []
	var position_4d: Vector4D:
		get:
			return _position_4d
	func get_portals() -> Array:
		return portals

class SliceViewer extends Node3D:
	var position_4d := Vector4D.zero()
	func get_position_4d() -> Vector4D:
		return position_4d

var failures: Array[String] = []
var stage: Node3D

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
		push_error(description)

func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	await _test_freezing_chain()
	await _test_player_freezing_chain()
	await _test_physical_bounces()
	await _test_homing_and_splits()
	await _test_power_scaling_and_unlimited_bounces()
	await _test_hitscan()
	await _test_open_portals_and_effect_cleanup()
	print("FREEZE / PROJECTILE MODIFIERS: %d failures; increasing freeze chance, half-second chain, pause/status timers, ricochets, homing, split inheritance and typed hitscan" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _enemy(at: Vector3, room_id: int = -1, w: float = 0.0) -> FixedRollEnemy:
	var enemy := FixedRollEnemy.new()
	enemy.enable_4d_mode = false
	enemy.max_health = 1000
	enemy.initial_w = w
	enemy.position = at
	if room_id >= 0:
		enemy.set_meta("encounter_room", room_id)
	stage.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.enemy_type = GunTypes.Type.FREEZING
	return enemy

func _shot(type: int, at: Vector3 = Vector3.ZERO) -> Projectile:
	var shot := Projectile.new()
	shot.damage_type = type as GunTypes.Type
	shot.damage = 5.0
	shot.position = at
	shot.position_4d = Vector4D.from_vector3(at, 0.0)
	stage.add_child(shot)
	shot.set_physics_process(false)
	return shot

func _cleanup() -> void:
	for child in stage.get_children():
		child.queue_free()
	await process_frame

func _test_freezing_chain() -> void:
	var enemy := _enemy(Vector3(5, 0, 0))
	check(not enemy.register_freezing_hit(0.01), "The first hit has exactly one-percent chance, excluding the boundary")
	check(enemy.freezing_hit_count == 1 and is_equal_approx(enemy.freezing_hit_window, 0.5), "A direct ice hit starts a half-second chain")
	enemy._tick_freezing_hit_window(0.49)
	check(enemy.register_freezing_hit(0.015), "A second hit within the window has two-percent chance")
	check(enemy.freezing_hit_count == 2 and is_equal_approx(enemy.freezing_hit_window, 0.5) and is_equal_approx(enemy.frozen_timer, 2.0), "Each hit refreshes the chain and a successful roll freezes for two seconds")
	enemy.stunned_timer = 2.0
	enemy._physics_process(0.51)
	check(enemy.freezing_hit_count == 0 and enemy.freezing_hit_window == 0.0 and enemy.frozen_timer > 0.0, "The hit window expires even while frozen and stunned")
	check(not enemy.register_freezing_hit(0.01) and enemy.freezing_hit_count == 1, "A gap over half a second resets the next hit to one percent")
	enemy._tick_freezing_hit_window(0.5)
	check(enemy.register_freezing_hit(0.015) and enemy.freezing_hit_count == 2, "A hit exactly half a second later remains in the chain")
	var time_before := enemy.freezing_hit_window
	var freeze_before := enemy.frozen_timer
	paused = true
	enemy._physics_process(1.0)
	enemy._tick_freezing_hit_window(1.0)
	check(enemy.freezing_hit_window == time_before and enemy.frozen_timer == freeze_before, "Pausing gameplay pauses both the hit window and frozen duration")
	paused = false
	enemy._tick_freezing_hit_window(0.51)
	enemy.frozen_timer = 0.0
	for hit in range(99):
		check(not enemy.register_freezing_hit(0.99999), "Hits before the hundredth are not guaranteed")
	check(enemy.register_freezing_hit(1.0) and enemy.freezing_hit_count == 100, "The hundredth consecutive hit guarantees freezing even with the maximum fixture roll")
	check(enemy.register_freezing_hit(1.0) and enemy.freezing_hit_count == 101, "The hit counter continues beyond a hundred while probability stays guaranteed")
	var boss := _enemy(Vector3(-5, 0, 0))
	boss.archetype = Enemy4D.Archetype.BOSS
	check(boss.register_freezing_hit(0.0) and is_equal_approx(boss.frozen_timer, 0.7), "Successful freezing preserves boss duration resistance")
	enemy._tick_freezing_hit_window(0.51)
	enemy.frozen_timer = 0.0
	var direct := _shot(GunTypes.Type.FREEZING, enemy.global_position)
	direct._on_body_entered(enemy)
	check(enemy.freezing_hit_count == 1 and enemy.frozen_timer == 0.0, "The production ice impact registers a chance-based direct hit")
	var wall := _shot(GunTypes.Type.FREEZING, enemy.global_position)
	wall._handle_wall_collision()
	check(enemy.freezing_hit_count == 1 and enemy.frozen_timer == 0.0, "A wall ice burst cannot add chance or unconditionally freeze nearby enemies")
	var remote := _enemy(enemy.global_position, -1, 20.0)
	var remote_health := remote.current_health
	var wrong_w := _shot(GunTypes.Type.FREEZING, remote.global_position)
	wrong_w._on_body_entered(remote)
	check(remote.freezing_hit_count == 0 and remote.current_health == remote_health, "Wrong-W direct contacts cannot damage or build freeze chance")
	check(_effects("FreezeEffect") >= 2, "Direct and wall ice impacts retain their icy cosmetic bursts")
	await _cleanup()

func _test_player_freezing_chain() -> void:
	var player: CharacterBody3D = load("res://scenes/player/player.tscn").instantiate()
	stage.add_child(player)
	player.set_physics_process(false)
	check(not player.register_freezing_hit(0.01) and player.freezing_hit_count == 1, "Enemy shots start a player freeze chain at one percent")
	player._physics_process(0.5)
	check(player.register_freezing_hit(0.015) and player.freezing_hit_count == 2 and player.frozen_timer == 2.0, "Player freezing shares the exact half-second boundary and two-second duration")
	player._physics_process(0.51)
	check(player.freezing_hit_count == 0 and player.frozen_timer > 0.0, "Player hit chance resets during an existing freeze")
	var window_before: float = player.freezing_hit_window
	var frozen_before: float = player.frozen_timer
	player.set_physics_process(true)
	paused = true
	await process_frame
	await process_frame
	check(player.freezing_hit_window == window_before and player.frozen_timer == frozen_before, "Normal player physics leaves freeze timers unchanged while gameplay is paused")
	player.set_physics_process(false)
	paused = false
	player.freezing_hit_count = 99
	player.freezing_hit_window = 0.5
	var direct := _shot(GunTypes.Type.FREEZING, player.global_position)
	direct._on_body_entered(player)
	check(player.freezing_hit_count == 100 and player.frozen_timer == 2.0, "A production enemy projectile registers the player's guaranteed hundredth hit")
	check(player.register_freezing_hit(1.0) and player.freezing_hit_count == 101, "The player's freeze hit counter also stacks without a limit")
	await _cleanup()

func _test_physical_bounces() -> void:
	var room := TestRoom.new()
	room.radius = 5.0
	room.add_to_group("room_spheres_4d")
	stage.add_child(room)
	var ice := _shot(GunTypes.Type.FREEZING)
	ice.speed = 100.0
	ice.bounce_count = 3
	ice.launch(Vector3.RIGHT)
	ice._physics_process(0.3)
	check(ice.bounce_count == 0 and not ice._impact_handled and ice.global_position.length() < 4.85, "Three ricochets resolve within a high-speed tick and stay inside the sphere")
	check(_effects("FreezeEffect") == 3, "Every ricochet retains its gun-type impact effect")
	ice._physics_process(0.1)
	check(ice._impact_handled and _effects("FreezeEffect") == 4, "The next wall impact stops a shot after its three bounces are used")
	await _cleanup()
	var target := _enemy(Vector3.ZERO)
	target.enemy_type = GunTypes.Type.IMPLOSIVE
	var bounce := _shot(GunTypes.Type.IMPLOSIVE, Vector3(-0.6, 0, 0))
	bounce.damage = 10.0
	bounce.bounce_count = 3
	bounce.launch(Vector3.RIGHT)
	bounce._resolve_collision(target, Vector3.LEFT)
	check(bounce.bounce_count == 2 and bounce.direction.x < 0.0 and target.current_health == 990, "Enemy contact damages once, applies implosion and reflects the shot")
	var first_force := target.external_velocity
	bounce._on_body_entered(target)
	check(target.current_health == 990 and target.external_velocity == first_force and bounce.bounce_count == 2, "Overlap callbacks cannot repeat an enemy impact before the projectile leaves")
	bounce.global_position = Vector3(-3, 0, 0)
	bounce._clear_departed_hits()
	bounce.global_position = Vector3(-0.6, 0, 0)
	bounce.direction = Vector3.RIGHT
	bounce._resolve_collision(target, Vector3.LEFT)
	check(target.current_health == 980 and bounce.bounce_count == 1, "A ricochet can hit the same enemy again after leaving its collision clearance")
	await _cleanup()

func _test_homing_and_splits() -> void:
	var room := TestRoom.new()
	room.add_to_group("room_spheres_4d")
	stage.add_child(room)
	var good := _enemy(Vector3(5, 0, -5), room.room_id)
	var neighbor := _enemy(Vector3(-1, 0, -1), room.room_id + 1)
	var other_w := _enemy(Vector3(-0.5, 0, -0.5), room.room_id, 20.0)
	var homing := _shot(GunTypes.Type.IMPLOSIVE)
	homing.homing_strength = 7.0
	homing.launch(Vector3.FORWARD)
	homing._update_homing(0.1)
	check(homing.direction.x > 0.0 and homing.direction.z < 0.0, "Homing picks the nearest eligible enemy rather than closer enemies in another room or W layer")
	var stronger := _shot(GunTypes.Type.IMPLOSIVE)
	stronger.homing_strength = 8.0
	stronger.launch(Vector3.FORWARD)
	stronger._update_homing(0.1)
	check(stronger.direction.x > homing.direction.x, "Additional homing strength increases steering acceleration")
	good.queue_free()
	neighbor.queue_free()
	other_w.queue_free()
	await process_frame
	var target := _enemy(Vector3(2, 0, 0), room.room_id)
	target.enemy_type = GunTypes.Type.ACCELERATING
	var splitter := _shot(GunTypes.Type.ACCELERATING, Vector3(1.4, 0, 0))
	splitter.damage = 8.0
	splitter.speed = 33.0
	splitter.bounce_count = 4
	splitter.homing_strength = 9.0
	splitter.power_multiplier = 2.0
	splitter.scale = Vector3.ONE * 2.0
	splitter.launch(Vector3.RIGHT)
	splitter._resolve_collision(target, Vector3.LEFT)
	var children: Array[Projectile] = []
	for projectile in get_nodes_in_group("projectiles"):
		if projectile != splitter and projectile.damage_type == GunTypes.Type.ACCELERATING:
			children.append(projectile)
	check(children.size() == 2, "Accelerating enemy impacts still split into two children")
	var health_before := target.current_health
	for child in children:
		check(child.damage == 4.0 and child.speed == 33.0 and child.bounce_count == 3 and child.homing_strength == 9.0 and child.power_multiplier == 2.0, "Split children inherit damage, speed and remaining item modifiers")
		check(child.scale.is_equal_approx(Vector3.ONE * 2.0), "Split children retain broad-stat projectile visual/collision scale")
		check(child.direction.x < 0.0, "Bouncy accelerating children inherit the reflected trajectory")
		child._on_body_entered(target)
	check(target.current_health == health_before, "Split children cannot duplicate damage on their parent's hit enemy")
	await _cleanup()

func _test_open_portals_and_effect_cleanup() -> void:
	var source := TestRoom.new()
	source.radius = 5.0
	source.add_to_group("room_spheres_4d")
	stage.add_child(source)
	var destination := TestRoom.new()
	destination.radius = 5.0
	destination.room_id = 11
	destination.position = Vector3(10, 0, 0)
	destination._position_4d = Vector4D.from_vector3(destination.position, 30.0)
	destination.add_to_group("room_spheres_4d")
	stage.add_child(destination)
	var portal := PortalDoor.new()
	var receiver := PortalDoor.new()
	source.add_child(portal)
	portal.position_on_sphere(source, Vector3.RIGHT)
	portal.target_room = destination
	source.portals.append(portal)
	destination.add_child(receiver)
	receiver.position_on_sphere(destination, Vector3.LEFT)
	receiver.target_room = source
	destination.portals.append(receiver)
	portal.link_to_portal(receiver)
	portal.set_physics_process(false)
	receiver.set_physics_process(false)
	var target := _enemy(Vector3(8, 0, 0), destination.room_id, 30.0)
	var wrong_w := _enemy(Vector3(7, 0, 0), destination.room_id, 0.0)
	var wrong_room := _enemy(Vector3(6, 0, 0), source.room_id, 30.0)
	await physics_frame
	await physics_frame
	var physical := _shot(GunTypes.Type.FREEZING, Vector3(0, 0.75, 0))
	physical.speed = 100.0
	physical.launch(Vector3.RIGHT)
	physical._physics_process(0.1)
	check(target.current_health == 995 and physical._source_room_id == destination.room_id and physical.position_4d.w == 30.0, "A physical projectile crosses an open portal and damages an enemy in the destination room/W")
	check(wrong_w.current_health == 1000 and wrong_room.current_health == 1000, "A portal-crossing shot does not spill into another W or room")
	var laser := _shot(GunTypes.Type.FREEZING, Vector3(0, 0.75, 0))
	laser.laser_guided = true
	laser.launch(Vector3.RIGHT)
	check(target.current_health == 990 and laser.position_4d.w == 30.0 and laser._source_room_id == destination.room_id, "An instant laser traces the open portal plane before hitting the destination enemy")
	var beams: Array[Projectile.SliceEffect] = []
	for effect in stage.get_children():
		if effect is Projectile.SliceEffect and effect.name.begins_with("LaserBeam"):
			beams.append(effect)
	check(beams.size() == 2 and beams[0].impact_w == 0.0 and beams[1].impact_w == 30.0 and beams[0].owning_room == source and beams[1].owning_room == destination, "Laser beam legs retain the source and destination's independent W slices and rooms")
	var viewer := SliceViewer.new()
	viewer.add_to_group("player")
	stage.add_child(viewer)
	for beam in beams:
		beam._process(0.0)
	check(beams.size() == 2 and beams[0].visible and not beams[1].visible, "Laser beam legs obey the viewer's W slice")
	source.graph_visible = false
	if not beams.is_empty():
		beams[0]._process(0.0)
		check(not beams[0].visible, "A detached laser cannot render from an unrelated hidden room on the same W")
	source.graph_visible = true
	viewer.queue_free()
	var probe := _shot(GunTypes.Type.ACCELERATING, Vector3(0, 0.75, 0))
	probe.launch(Vector3.RIGHT)
	probe.global_position = Vector3(5, 0.75, 0)
	var crossing_xyz := probe.global_position
	probe.notify_portal_crossing(portal)
	probe.notify_portal_crossing(portal)
	check(probe.global_position == crossing_xyz and probe.position_4d.to_vector3() == crossing_xyz and probe.position_4d.w == 30.0, "A portal changes projectile W/room once while preserving all XYZ coordinates")
	probe.queue_free()
	portal.set_key_lock(source, true)
	await physics_frame
	await physics_frame
	var before_lock := target.current_health
	var locked := _shot(GunTypes.Type.FREEZING, Vector3(0, 0.75, 0))
	locked.laser_guided = true
	locked.launch(Vector3.RIGHT)
	check(target.current_health == before_lock and locked.position_4d.w == 0.0 and locked.global_position.x < 5.0, "A key-locked seal stops the laser in its source room before any W transition")
	await create_timer(0.8).timeout
	check(_effects("LaserBeam") == 0 and get_nodes_in_group("projectiles").is_empty(), "Queued instant shots and detached laser trails clean themselves up")
	await _cleanup()

func _test_power_scaling_and_unlimited_bounces() -> void:
	var target := _enemy(Vector3(18, 0, 0))
	target.enemy_type = GunTypes.Type.EXPLOSIVE
	var explosion := _shot(GunTypes.Type.EXPLOSIVE)
	explosion.damage = 60.0
	explosion.power_multiplier = 2.0
	explosion._explode()
	check(target.current_health == 985 and target.external_velocity.length() > 9.0, "Broad stat power increases explosion radius and force without doubling already-scaled damage")
	target.global_position = Vector3(10, 0, 0)
	target.external_velocity = Vector3.ZERO
	var implosion := _shot(GunTypes.Type.IMPLOSIVE)
	implosion.power_multiplier = 2.0
	implosion._implode_nearby()
	var expected_force := Vector3.LEFT * (30.0 * (1.0 - 10.0 / 14.0 * 0.5))
	check(target.external_velocity.is_equal_approx(expected_force), "Broad stat power increases implosion radius and pull force exactly once")
	await _cleanup()
	var room := TestRoom.new()
	room.radius = 1.8
	room.add_to_group("room_spheres_4d")
	stage.add_child(room)
	var laser := _shot(GunTypes.Type.ACCELERATING)
	laser.bounce_count = 200
	laser.laser_guided = true
	laser.launch(Vector3.RIGHT)
	check(200 - laser.bounce_count > 64 and _effects("LaserBeam") > 64, "Laser ricochets have no sixty-four-bounce cap and travel their full finite range")
	var physical := _shot(GunTypes.Type.ACCELERATING)
	physical.bounce_count = 200
	physical.speed = 250.0
	physical.launch(Vector3.RIGHT)
	physical._physics_process(1.0)
	check(200 - physical.bounce_count > 64 and not physical._impact_handled, "Physical projectiles also resolve every ricochet required by the travelled segment")
	await _cleanup()

func _test_hitscan() -> void:
	var room := TestRoom.new()
	room.add_to_group("room_spheres_4d")
	stage.add_child(room)
	var target := _enemy(Vector3(0, 0, -10), room.room_id)
	var remote := _enemy(Vector3(0, 0, -3), room.room_id, 20.0)
	var neighbor := _enemy(Vector3(0, 0, -6), room.room_id + 1)
	await physics_frame
	await physics_frame
	for type in range(4):
		target.enemy_type = type as GunTypes.Type
		target.external_velocity = Vector3.ZERO
		var before := target.current_health
		var laser := _shot(type, Vector3(0, 0.75, 0))
		laser.laser_guided = true
		laser.launch(Vector3.FORWARD)
		check(target.current_health == before - 5 and laser._impact_handled, "Hitscan immediately resolves direct damage for type %d" % type)
		if type == GunTypes.Type.EXPLOSIVE or type == GunTypes.Type.IMPLOSIVE:
			check(target.external_velocity.length_squared() > 0.0, "Typed hitscan retains its radial force effect")
		if type == GunTypes.Type.FREEZING:
			check(target.freezing_hit_count == 1 and target.frozen_timer == 0.0, "Freezing hitscan uses the same escalating direct-hit chance")
		if type == GunTypes.Type.ACCELERATING:
			var laser_children := 0
			for child in get_nodes_in_group("projectiles"):
				if child != laser and child.damage_type == GunTypes.Type.ACCELERATING and child.damage == 2.5:
					check(child.laser_guided, "Accelerating split children inherit instant laser travel")
					laser_children += 1
			check(laser_children == 2, "An accelerating hitscan creates two typed laser children")
	check(remote.current_health == 1000 and neighbor.current_health == 1000, "Hitscan and impact splash ignore overlapping targets from another room or W layer")
	check(_effects("LaserBeam") >= 4, "Hitscan renders a short-lived visible beam for each shot")
	var homing_laser := _shot(GunTypes.Type.FREEZING, Vector3(0, 0.75, 0))
	homing_laser.homing_strength = 7.0
	homing_laser.laser_guided = true
	var before_homing := target.current_health
	homing_laser.launch(Vector3.RIGHT)
	check(target.current_health < before_homing, "Homing and laser modifiers combine by aiming the instant ray at an eligible target")
	room.radius = 5.0
	var behind_wall := target.current_health
	var blocked := _shot(GunTypes.Type.FREEZING, Vector3(0, 0.75, 0))
	blocked.laser_guided = true
	blocked.launch(Vector3.FORWARD)
	check(target.current_health == behind_wall and absf(blocked.global_position.z) < 5.0, "Hitscan resolves the nearer analytic room wall before an enemy beyond it")
	await _cleanup()

func _effects(effect_name: String) -> int:
	var result := 0
	for child in stage.get_children():
		if child is Projectile.SliceEffect and child.name.begins_with(effect_name):
			result += 1
	return result
