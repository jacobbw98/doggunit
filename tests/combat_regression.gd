extends SceneTree

class AlwaysCriticalStats extends GunStats:
	func roll_crit() -> bool:
		return true

class TargetDummy extends CharacterBody3D:
	var position_4d := Vector4D.zero()
	var health: int = 100
	var frozen: float = 0.0
	var force := Vector3.ZERO
	func get_position_4d() -> Vector4D:
		return position_4d
	func take_damage(amount: int, _type: int) -> void:
		health -= amount
	func freeze(duration: float) -> void:
		frozen = duration
	func apply_external_force(value: Vector3) -> void:
		force += value

class TestDoor extends Node3D:
	var available: bool = true
	func contains_aperture(point: Vector3, _depth: float = 4.0) -> bool:
		return available and absf(point.x - 5.0) < 1.0 and absf(point.y) < 1.0 and absf(point.z) < 1.0

class TestRoom extends Node3D:
	var radius: float = 5.0
	var _position_4d := Vector4D.zero()
	var portals: Array = []
	func get_portals() -> Array:
		return portals

var failures: Array[String] = []
var death_count: int = 0
var phase_count: int = 0

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
	var target := TargetDummy.new()
	target.position = Vector3(0, 0, -10)
	target.add_to_group("player")
	stage.add_child(target)
	var boss: Enemy4D
	for kind in range(5):
		var enemy := Enemy4D.new()
		enemy.configure_archetype(kind, 1.0)
		enemy.enable_4d_mode = false
		enemy.position = Vector3(kind * 4.0, 0, 0)
		stage.add_child(enemy)
		enemy.set_physics_process(false)
		enemy.target = target
		check(enemy.current_health > 0 and enemy.get_node_or_null("MeshInstance3D") != null, "Every archetype spawns with a visual and positive health")
		if enemy.is_boss():
			boss = enemy
		else:
			enemy.queue_free()
	boss.died.connect(func(_enemy: Enemy4D): death_count += 1)
	boss.boss_phase_changed.connect(func(_phase: int): phase_count += 1)
	# The carried breed's random type must not alter this phase-threshold fixture.
	boss.enemy_type = GunTypes.Type.EXPLOSIVE
	boss.take_damage(220, GunTypes.Type.EXPLOSIVE)
	check(boss.boss_phase == 2 and phase_count == 1, "Boss enters second phase once at half health")
	boss.freeze(2.0)
	check(is_equal_approx(boss.frozen_timer, 0.7) and boss._ice_shell.visible, "Boss freeze resistance keeps a visible, shortened status")
	boss.apply_external_force(Vector3(20, 0, 0))
	check(is_equal_approx(boss.external_velocity.x, 5.0), "Boss knockback resistance applies")
	boss.take_damage(1000, GunTypes.Type.EXPLOSIVE)
	boss.take_damage(1000, GunTypes.Type.EXPLOSIVE)
	check(death_count == 1, "Repeated same-frame lethal hits emit one death")
	await process_frame

	var rusher := Enemy4D.new()
	rusher.configure_archetype(Enemy4D.Archetype.RUSHER)
	rusher.enable_4d_mode = false
	stage.add_child(rusher)
	rusher.set_physics_process(false)
	rusher.target = target
	target.position = Vector3(0, 0, -2)
	check(rusher._can_attack_target(), "Rusher can attack in melee range on its W slice")
	target.position_4d.w = 20
	check(not rusher._can_attack_target(), "Enemy cannot attack a target in another W slice")
	target.position_4d.w = 0
	target.position = Vector3(0, 4, -2)
	rusher.up_direction = Vector3.RIGHT
	rusher._state_chasing_3d(0.016)
	check(absf(rusher.velocity.dot(Vector3.RIGHT)) < 0.001 and rusher.velocity.y > 0.0, "Wall chase uses the surface tangent instead of flattening world Y")
	rusher.freeze(2.0)
	rusher.apply_external_force(Vector3(10, 0, 0))
	rusher._physics_process(0.016)
	check(rusher.get_position_4d().to_vector3().is_equal_approx(rusher.global_position), "Frozen displacement stays synchronized with the 4D position")
	rusher.queue_free()
	await process_frame
	# Exercise production firing paths, including a transformed scene parent.
	var shot_parent := Node3D.new()
	shot_parent.position = Vector3(30, 8, 12)
	root.add_child(shot_parent)
	current_scene = shot_parent
	var critical_stats := AlwaysCriticalStats.new()
	var world_origin := Vector3(3, 4, 5)
	var critical_shot := Projectile.create_from_stats(critical_stats, world_origin, Vector3.FORWARD, target, 7.0)
	shot_parent.add_child(critical_shot)
	critical_shot.set_physics_process(false)
	check(critical_shot.global_position.is_equal_approx(world_origin) and critical_shot.position_4d.w == 7.0, "Factory resolves world muzzle position after parenting, including transformed parents")
	check(critical_shot.damage == 20.0, "Factory default retains one critical roll for enemy callers")
	var ordinary_shot := Projectile.create_from_stats(critical_stats, world_origin, Vector3.FORWARD, target, 0.0, false)
	shot_parent.add_child(ordinary_shot)
	ordinary_shot.set_physics_process(false)
	check(ordinary_shot.damage == 10.0, "Factory critical opt-out leaves damage for the caller to scale exactly once")
	var gun_script: Script = load("res://scripts/weapons/gun.gd")
	var gun: Node3D = gun_script.new()
	gun.stats = critical_stats
	stage.add_child(gun)
	gun._spawn_projectile(world_origin, Vector3.FORWARD, true, 0.0)
	var gun_shot: Projectile = shot_parent.get_child(shot_parent.get_child_count() - 1)
	gun_shot.set_physics_process(false)
	check(gun_shot.damage == 20.0, "A gun critical shot applies its multiplier once, without a second factory critical")
	var before_fire: int = shot_parent.get_child_count()
	gun.fire(world_origin, Vector3.FORWARD, 0.0)
	check(shot_parent.get_child_count() == before_fire + 1 and gun.current_ammo == 29, "Actual Gun.fire emits a visible projectile and consumes one round")
	gun.queue_free()
	current_scene = stage
	var firing_enemy := Enemy4D.new()
	firing_enemy.configure_archetype(Enemy4D.Archetype.GRUNT)
	firing_enemy.enable_4d_mode = false
	stage.add_child(firing_enemy)
	firing_enemy.set_physics_process(false)
	firing_enemy.target = target
	target.position = Vector3(0, 0, -10)
	var enemy_shots_before: int = get_nodes_in_group("projectiles").size()
	firing_enemy._fire_at_target()
	check(get_nodes_in_group("projectiles").size() == enemy_shots_before + 1, "Enemy firing creates a projectile through the production factory")
	firing_enemy.queue_free()
	shot_parent.queue_free()
	for projectile in get_nodes_in_group("projectiles"):
		projectile.queue_free()
	await process_frame

	target.position = Vector3(0, 0, -2)
	target.position_4d = Vector4D.from_vector3(target.position, 0)
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	target.add_child(shape)
	var remote := TargetDummy.new()
	remote.position = target.position
	remote.position_4d = Vector4D.from_vector3(remote.position, 20)
	remote.add_to_group("enemies")
	stage.add_child(remote)
	var freezing := Projectile.new()
	freezing.damage_type = GunTypes.Type.FREEZING
	freezing.position_4d = Vector4D.zero()
	stage.add_child(freezing)
	freezing.set_physics_process(false)
	freezing._freeze_nearby()
	check(target.frozen == 0.0 and remote.frozen == 0.0, "An icy impact burst is cosmetic and never freezes nearby targets")
	var implosion := Projectile.new()
	implosion.damage_type = GunTypes.Type.IMPLOSIVE
	stage.add_child(implosion)
	implosion.set_physics_process(false)
	implosion._implode_nearby()
	check(target.force.z > 0.0 and remote.force == Vector3.ZERO, "Implosion pulls toward impact without reaching other W slices")
	await physics_frame
	await physics_frame
	var shot := Projectile.new()
	shot.speed = 200
	shot.damage_type = GunTypes.Type.ACCELERATING
	shot.damage = 1
	shot.direction = Vector3.FORWARD
	stage.add_child(shot)
	shot.set_physics_process(false)
	shot._physics_process(0.05)
	check(target.health == 99, "Swept projectile detects a character crossed within one physics tick")
	freezing._handle_wall_collision()
	var effect_count: int = _effect_count(stage)
	freezing._on_body_entered(target)
	check(_effect_count(stage) == effect_count, "Wall and body callbacks produce only one impact")
	var room := TestRoom.new()
	room.add_to_group("room_spheres_4d")
	stage.add_child(room)
	var doorway := TestDoor.new()
	room.add_child(doorway)
	room.portals = [doorway]
	var doorway_shot := Projectile.new()
	doorway_shot.direction = Vector3.RIGHT
	doorway_shot.speed = 1000.0
	stage.add_child(doorway_shot)
	doorway_shot.set_physics_process(false)
	doorway_shot._physics_process(0.02)
	check(not doorway_shot._impact_handled and doorway_shot.global_position.x > room.radius, "Fast projectiles pass through the open doorway instead of striking the sphere wall")
	doorway_shot.queue_free()
	doorway.available = false
	var wall_shot := Projectile.new()
	wall_shot.direction = Vector3.RIGHT
	wall_shot.speed = 1000.0
	stage.add_child(wall_shot)
	wall_shot.set_physics_process(false)
	wall_shot._physics_process(0.02)
	check(wall_shot._impact_handled and is_equal_approx(wall_shot.global_position.x, 4.85), "A closed doorway stops a fast shot exactly at the analytic sphere wall")
	room.queue_free()
	implosion.queue_free()
	await create_timer(0.8).timeout
	check(_effect_count(stage) == 0, "Detached impact visuals clean up after animation")
	if failures.is_empty():
		print("COMBAT REGRESSION PASSED: archetypes, boss phase/death, W isolation, tangent motion, freeze, sweep, effects")
	else:
		print("COMBAT REGRESSION FAILED: ", failures)
	quit(0 if failures.is_empty() else 1)

func _effect_count(stage: Node) -> int:
	var count: int = 0
	for child in stage.get_children():
		if child is Projectile.SliceEffect:
			count += 1
	return count
