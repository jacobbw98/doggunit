extends Node3D

var run: RunManager
var gun: Gun
var remaining: float
var _finished := false

func configure(owner_run: RunManager, walking_gun: Gun, duration: float) -> void:
	run = owner_run
	gun = walking_gun
	remaining = duration

func _ready() -> void:
	name = "WalkiesCompanion"
	global_position = run.player.global_position

func _process(delta: float) -> void:
	if _finished or not is_instance_valid(run) or not is_instance_valid(gun):
		return
	if run.loading or GameManager.current_state != GameManager.GameState.PLAYING:
		return
	remaining -= delta
	if remaining <= 0.0:
		finish()
		return
	var room: Node3D = run.generator.get_room(run.current_room_id)
	if not is_instance_valid(room):
		return
	var player_dir := (run.player.global_position - room.global_position).normalized()
	var own_dir := (global_position - room.global_position).normalized()
	if own_dir.is_zero_approx() or global_position.distance_to(room.global_position) > room.radius + 2.0:
		own_dir = player_dir
	var up := -own_dir
	var target: Enemy4D
	var nearest := float(run.active_item.get("radius", 15.0))
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy is Enemy4D or enemy._dead or run._get_enemy_room_id(enemy) != run.current_room_id:
			continue
		var distance := global_position.distance_to(enemy.global_position)
		if distance < nearest:
			nearest = distance
			target = enemy
	var tangent: Vector3 = run.player.global_basis.x.slide(player_dir).normalized()
	var desired_dir: Vector3 = (player_dir + tangent * 2.0 / float(room.get("radius"))).normalized()
	if is_instance_valid(target):
		var enemy_dir := (target.global_position - room.global_position).normalized()
		desired_dir = own_dir.slerp(enemy_dir, clampf((nearest - 4.0) / maxf(nearest, 0.01), 0.0, 1.0))
	own_dir = own_dir.slerp(desired_dir, minf(1.0, 5.0 * delta / maxf(own_dir.angle_to(desired_dir) * room.radius, 0.01))).normalized()
	global_position = room.global_position + own_dir * (room.radius - 0.75)
	up = -own_dir
	var facing: Vector3 = (target.global_position - global_position).slide(up).normalized() if is_instance_valid(target) else (-run.player.global_basis.z).slide(up).normalized()
	if facing.is_zero_approx():
		facing = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	global_basis = Basis.looking_at(facing, up)
	if is_instance_valid(target):
		if gun.current_ammo <= 0:
			gun.reload()
		var aim := (target.global_position - (global_position + up * 0.4)).normalized()
		# Check the whole firing segment remains in the curved room.
		gun.fire(global_position + up * 0.4 + facing * 0.5, aim, room.position_4d.w)

func finish() -> void:
	if _finished:
		return
	_finished = true
	if is_instance_valid(gun) and is_instance_valid(run.player):
		var inventory: WeaponManager = run.player.weapon_manager
		gun.set_meta("on_walkies", false)
		gun.reparent(inventory.gun_holder, false)
		gun.transform = Transform3D.IDENTITY
		gun.rebase_reload_animation(gun.transform)
		gun.visible = inventory.get_current_gun() == gun
	if is_instance_valid(run):
		run.walkies_companion = null
	queue_free()
