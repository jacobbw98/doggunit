class_name RunBomb
extends Node3D

## A thrown consumable that stays on its room's curved interior surface.
const FUSE_SECONDS := 1.8
const BLAST_RADIUS := 5.0
const BLAST_DAMAGE := 85
var run: RunManager
var room: Node3D
var room_id: int = -1
var velocity := Vector3.ZERO
var fuse: float = FUSE_SECONDS
var detonated := false
var fuse_light: OmniLight3D

static func spawn(owner_run: RunManager) -> RunBomb:
	var host: Node3D = owner_run.generator.get_room(owner_run.current_room_id)
	if not is_instance_valid(host) or not is_instance_valid(owner_run.player):
		return null
	var bomb := RunBomb.new()
	bomb.fuse = float(PetItems.find_item("bomb").get("duration", FUSE_SECONDS))
	bomb.run = owner_run
	bomb.room = host
	bomb.room_id = host.room_id
	var up: Vector3 = owner_run.player.current_gravity_up.normalized()
	var forward: Vector3 = -owner_run.player.camera.global_basis.z
	bomb.velocity = forward * 4.0 + up * 1.5
	host.add_child(bomb)
	bomb.global_position = owner_run.player.global_position + up * 0.55 + forward * 0.9
	bomb._constrain_to_room()
	return bomb

func _ready() -> void:
	add_to_group("run_bombs")
	var path := "res://assets/items/bomb.glb"
	if ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed:
			var visual := packed.instantiate() as Node3D
			visual.scale = Vector3.ONE * 0.65
			add_child(visual)
	else:
		var visual := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.18
		mesh.height = 0.36
		mesh.radial_segments = 8
		mesh.rings = 4
		visual.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("242231")
		visual.material_override = material
		add_child(visual)
	fuse_light = OmniLight3D.new()
	fuse_light.light_color = Color("ffad45")
	fuse_light.omni_range = 1.8
	fuse_light.position.y = 0.35
	add_child(fuse_light)

func _physics_process(delta: float) -> void:
	if detonated or not is_instance_valid(room):
		return
	visible = room.graph_visible
	fuse -= delta
	var radial := (global_position - room.global_position).normalized()
	velocity += radial * 8.0 * delta
	global_position += velocity * delta
	_constrain_to_room()
	var up := -(global_position - room.global_position).normalized()
	var forward := velocity.slide(up).normalized()
	if forward.is_zero_approx():
		forward = global_basis.z.slide(up).normalized()
	if forward.is_zero_approx():
		forward = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	global_basis = Basis.looking_at(forward, up)
	fuse_light.light_energy = 0.6 + 0.5 * sin((FUSE_SECONDS - fuse) * 25.0)
	if fuse <= 0.0:
		detonate()

func _constrain_to_room() -> void:
	var offset := global_position - room.global_position
	var limit: float = room.radius - 0.24
	if offset.length() > limit:
		var radial := offset.normalized()
		global_position = room.global_position + radial * limit
		if velocity.dot(radial) > 0.0:
			velocity = velocity.slide(radial) * 0.55

func detonate() -> void:
	if detonated or not is_instance_valid(room):
		return
	detonated = true
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or not enemy.has_method("take_damage"):
			continue
		if run._get_enemy_room_id(enemy) != room_id:
			continue
		var distance: float = global_position.distance_to(enemy.global_position)
		if distance <= BLAST_RADIUS:
			enemy.take_damage(roundi(BLAST_DAMAGE * (1.0 - 0.55 * distance / BLAST_RADIUS)), GunTypes.Type.EXPLOSIVE)
			if enemy.has_method("apply_external_force"):
				enemy.apply_external_force((enemy.global_position - global_position).normalized() * 7.0)
	if run.current_room_id == room_id and run.player.global_position.distance_to(global_position) < BLAST_RADIUS * 0.6:
		run.player.take_damage(20, GunTypes.Type.EXPLOSIVE)
	_spawn_blast_visual()
	queue_free()

func _spawn_blast_visual() -> void:
	var effect := Node3D.new()
	effect.name = "BombBlast"
	room.add_child(effect)
	effect.global_position = global_position
	var shell := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	shell.mesh = mesh
	shell.scale = Vector3.ONE * 0.2
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.52, 0.1, 0.3)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shell.material_override = material
	effect.add_child(shell)
	var tween := effect.create_tween().set_parallel(true)
	tween.tween_property(shell, "scale", Vector3.ONE * BLAST_RADIUS, 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.35)
	tween.chain().tween_callback(effect.queue_free)
