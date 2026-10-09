class_name BonePickup
extends Node3D

const BURST_DELAY: float = 1.15
const COLLECTION_DISTANCE: float = 0.65
var run: Node
var room: Node3D
var room_id: int = -1
var amount: int = 1
var variant: int = 0
var velocity: Vector3 = Vector3.ZERO
var age: float = 0.0
var collected: bool = false
var _visual: Node3D
var _hit_enemies: Dictionary = {}
var _spikes: Node3D
var swarm_spine: bool = false
var _swarm_hit_cooldowns: Dictionary = {}

func configure(run_owner: Node, owning_room: Node3D, bone_amount: int, model_variant: int) -> void:
	run = run_owner
	room = owning_room
	room_id = int(room.get("room_id"))
	amount = bone_amount
	variant = clampi(model_variant, 0, 3)
	set_meta("room_id", room_id)

func _ready() -> void:
	add_to_group("bone_pickups")
	_visual = RoomEconomy.make_model("bone_%d" % variant, 0.80)
	add_child(_visual)
	# Currency spins around its centre, keeping every tip inside the wall inset.
	var visual_bounds := RoomEconomy.model_bounds(_visual, _visual.transform)
	_visual.position.y -= visual_bounds.get_center().y
	var material := StandardMaterial3D.new()
	material.albedo_color = denomination_color(amount)
	material.metallic = 0.0 if amount == 1 else 0.65
	material.roughness = 0.7 if amount == 1 else 0.40
	material.emission_enabled = true
	material.emission = denomination_color(amount)
	material.emission_energy_multiplier = 0.12
	for mesh in _visual.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = material
	if swarm_spine:
		_make_swarm_spine()

static func denomination_color(value: int) -> Color:
	if value == 10:
		return Color(1.0, 0.72, 0.15)
	if value == 5:
		return Color(0.65, 0.74, 0.83)
	return Color.WHITE

func _physics_process(delta: float) -> void:
	if collected or not is_instance_valid(room) or not is_instance_valid(run):
		return
	visible = RoomEconomy.room_visible(run, room)
	# A bone never targets the player through an overlapping room or W layer.
	if not RoomEconomy.room_active(run, room):
		return
	age += delta
	if run.get_item_count("boneswarm") > 0:
		if run.room_states.get(room_id, {}).get("cleared", false):
			bank_after_room_clear()
			return
		_tick_swarm(delta)
		constrain_to_room()
		return
	_tick_spikes()
	if age < BURST_DELAY:
		var outward := position.normalized()
		velocity += outward * 7.0 * delta
		velocity *= exp(-2.0 * delta)
		position += velocity * delta
	else:
		var player: Node3D = run.get("player")
		var target := room.to_local(player.global_position + player.global_basis.y * 0.65)
		var toward := target - position
		if toward.length() <= COLLECTION_DISTANCE:
			collect()
			return
		var multiplier := 1.0
		if run.has_method("get_bone_pull_multiplier"):
			multiplier = run.get_bone_pull_multiplier()
		var speed := minf(6.0, 1.4 + (age - BURST_DELAY) * 1.3) * multiplier
		velocity = velocity.lerp(toward.normalized() * speed, 1.0 - exp(-4.0 * delta))
		# A chord between two points inside a sphere stays inside its wall, so bones
		# can cross the interior instead of getting stranded on the opposite surface.
		var step := velocity * delta
		if step.length() > toward.length():
			step = toward
		position += step
	constrain_to_room()
	if is_instance_valid(_visual):
		_visual.rotation += Vector3(0.6, 1.5, 0.9) * delta

func constrain_to_room() -> void:
	var maximum := maxf(0.1, float(room.get("radius")) - 0.43)
	if position.length() > maximum:
		var outward := position.normalized()
		position = outward * maximum
		var outward_speed := velocity.dot(outward)
		if outward_speed > 0.0:
			velocity -= outward * outward_speed * 1.35

func collect() -> void:
	if collected or not RoomEconomy.room_active(run, room):
		return
	collected = true
	run.add_bones(amount)
	visible = false
	remove_from_group("bone_pickups")
	queue_free()

func bank_after_room_clear() -> void:
	if collected:
		return
	collected = true
	run.add_bones(amount)
	visible = false
	remove_from_group("bone_pickups")
	queue_free()

func _tick_swarm(delta: float) -> void:
	for id in _swarm_hit_cooldowns.keys():
		_swarm_hit_cooldowns[id] -= delta
		if _swarm_hit_cooldowns[id] <= 0.0:
			_swarm_hit_cooldowns.erase(id)
	var target: Enemy4D
	var nearest := INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy is Enemy4D or enemy._dead or run._get_enemy_room_id(enemy) != room_id or absf(enemy.position_4d.w - room.position_4d.w) > 0.5:
			continue
		if _swarm_hit_cooldowns.has(enemy.get_instance_id()):
			continue
		var distance := global_position.distance_to(enemy.global_position)
		if distance < nearest:
			nearest = distance
			target = enemy
	if is_instance_valid(target):
		var toward := room.to_local(target.global_position) - position
		var copies: int = run.get_item_count("boneswarm")
		velocity = velocity.move_toward(toward.normalized() * (10.0 + copies), (24.0 + copies) * delta)
		if nearest <= 0.9:
			_swarm_hit_cooldowns[target.get_instance_id()] = 0.35
			var spiky_damage: float = run.get_bone_damage()
			if spiky_damage > 0.0 and not swarm_spine:
				_split_swarm_spines()
			target.take_damage(maxi(1, roundi(copies + spiky_damage)), GunTypes.Type.EXPLOSIVE)
			velocity = -toward.normalized() * 9.0
			position += -toward.normalized() * 0.3
	position += velocity * delta
	if is_instance_valid(_visual):
		_visual.rotation += Vector3(0.6, 1.5, 0.9) * delta

func _make_swarm_spine() -> void:
	_visual.queue_free()
	_visual = MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = 0.0
	shape.bottom_radius = 0.06
	shape.height = 0.3
	shape.radial_segments = 5
	_visual.mesh = shape
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("f8e0aa")
	_visual.material_override = material
	add_child(_visual)

func _split_swarm_spines() -> void:
	swarm_spine = true
	_make_swarm_spine()
	# The original carries all currency. Seven extra spines are combat effects,
	# so splitting never increases or loses the death's bone payout.
	for i in range(7):
		var spine := BonePickup.new()
		spine.swarm_spine = true
		spine.configure(run, room, 0, variant)
		spine.position = position
		spine.velocity = Vector3(cos(i * TAU / 7.0), 0.5, sin(i * TAU / 7.0)) * 8.0
		room.add_child(spine)

func _tick_spikes() -> void:
	if not run.has_method("get_bone_damage"):
		return
	var damage: float = run.get_bone_damage()
	if damage <= 0.0:
		return
	if not is_instance_valid(_spikes):
		_spikes = Node3D.new()
		_spikes.name = "CactusSpikes"
		_visual.add_child(_spikes)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("f8e0aa")
		for i in range(8):
			var spike := MeshInstance3D.new()
			var shape := CylinderMesh.new()
			shape.top_radius = 0.0
			shape.bottom_radius = 0.045
			shape.height = 0.22
			shape.radial_segments = 5
			spike.mesh = shape
			spike.material_override = mat
			var direction := Vector3(cos(i * TAU / 8.0), 0.5 if i % 2 else -0.5, sin(i * TAU / 8.0)).normalized()
			spike.position = direction * 0.25
			spike.basis = Basis.looking_at(direction.cross(Vector3.UP), direction)
			_spikes.add_child(spike)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy is Enemy4D or enemy._dead or run._get_enemy_room_id(enemy) != room_id or absf(enemy.position_4d.w - room.position_4d.w) > 0.5:
			continue
		if _hit_enemies.has(enemy.get_instance_id()) or enemy.global_position.distance_to(global_position) > 0.85:
			continue
		_hit_enemies[enemy.get_instance_id()] = true
		enemy.take_damage(roundi(damage), GunTypes.Type.EXPLOSIVE)
