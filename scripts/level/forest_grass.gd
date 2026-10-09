# Seeded, GPU-animated tufts rooted to the room's curved inner surface.
extends Node3D

@export_range(0.0, 0.6) var wind_strength: float = 0.19
@export_range(0.5, 4.0) var interaction_radius: float = 2.2
var _material: ShaderMaterial
var _player: Node3D
var _room: Node3D
var _trail: Array[Vector4] = []
var _sample_time: float = 0.0
var _blade_mesh: ArrayMesh
var tuft_count: int = 0

func populate(room: Node3D, seed_value: int) -> void:
	_room = room
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_material = ShaderMaterial.new()
	_material.shader = load("res://resources/shaders/forest_grass.gdshader")
	_blade_mesh = load("res://resources/Models/forest_grass_tuft.tres") as ArrayMesh
	if not _blade_mesh:
		_blade_mesh = _make_tuft()
	var batches: Array = []
	for i in range(8):
		batches.append([])
	var radius: float = room.radius
	var desired := clampi(int(4.6 * radius * radius), 1000, 6500)
	# Shorter, sparser grass in commerce and boss arenas for readability.
	if room.room_type in [1, 3, 4]:
		desired = int(desired * 0.55)
	for i in range(desired):
		var y := rng.randf_range(-1.0, 1.0)
		var angle := rng.randf() * TAU
		var radial := sqrt(maxf(0.0, 1.0 - y * y))
		var direction := Vector3(radial * cos(angle), y, radial * sin(angle))
		var blocked := false
		for portal in room.portals:
			var portal_dir: Vector3 = (portal.global_position - room.global_position).normalized()
			if direction.angle_to(portal_dir) * radius < portal.portal_radius + 1.8:
				blocked = true
				break
		if blocked:
			continue
		# Broad clearings alternating with soft dense patches.
		var patch := sin(direction.x * 13.0 + direction.y * 8.0) * cos(direction.z * 11.0)
		if patch > 0.30 and rng.randf() < 0.72:
			continue
		var up := -direction
		var reference := Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT
		var forward := (reference - up * reference.dot(up)).normalized().rotated(up, rng.randf() * TAU)
		var size := rng.randf_range(0.65, 1.35)
		if room.room_type in [1, 3, 4]:
			size *= 0.75
		var basis_value := Basis.looking_at(forward, up).scaled(Vector3(size, size, size))
		var pose := Transform3D(basis_value, direction * (radius - 0.045))
		var tint := Color(rng.randf_range(0.86, 1.14), rng.randf_range(0.91, 1.10), rng.randf_range(0.80, 1.13))
		var octant := (1 if direction.x > 0.0 else 0) + (2 if direction.y > 0.0 else 0) + (4 if direction.z > 0.0 else 0)
		batches[octant].append([pose, tint])
		tuft_count += 1
	for i in range(8):
		var entries: Array = batches[i]
		if entries.is_empty():
			continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = _blade_mesh
		multi.instance_count = entries.size()
		var bounds := AABB()
		for j in range(entries.size()):
			var pose: Transform3D = entries[j][0]
			multi.set_instance_transform(j, pose)
			multi.set_instance_color(j, entries[j][1])
			var tuft_bounds := AABB(pose.origin - Vector3.ONE * 1.6, Vector3.ONE * 3.2)
			bounds = tuft_bounds if j == 0 else bounds.merge(tuft_bounds)
		multi.custom_aabb = bounds
		var batch := MultiMeshInstance3D.new()
		batch.name = "GrassPatch_%d" % i
		batch.multimesh = multi
		batch.material_override = _material
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(batch)
	for i in range(4):
		_trail.append(Vector4.ZERO)

func _process(delta: float) -> void:
	if not _material or not is_instance_valid(_room):
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	var generator = get_tree().get_first_node_in_group("level_generator")
	var active: bool = is_instance_valid(_player) and _room.is_visible_in_tree()
	if is_instance_valid(generator):
		active = active and generator.current_lit_room_id == _room.room_id
	_material.set_shader_parameter("player_active", active)
	_material.set_shader_parameter("wind_strength", wind_strength)
	_material.set_shader_parameter("interaction_radius", interaction_radius)
	if not active:
		for i in range(_trail.size()):
			_trail[i].w = 0.0
		_sample_time = 0.0
		return
	_material.set_shader_parameter("player_position", _player.global_position)
	# A brief footprint trail makes the blades ease upright after passage.
	for i in range(_trail.size()):
		_trail[i].w = maxf(0.0, _trail[i].w - delta * 2.0)
	_sample_time += delta
	if _sample_time >= 0.10:
		_sample_time = 0.0
		for i in range(3, 0, -1):
			_trail[i] = _trail[i - 1]
		var p := _player.global_position
		_trail[0] = Vector4(p.x, p.y, p.z, 0.45)
	_material.set_shader_parameter("player_trail", _trail)

func _make_tuft() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in range(5):
		var angle := float(blade) * TAU / 5.0 + 0.35
		var side := Vector3(cos(angle), 0.0, sin(angle))
		var lean := Vector3(-sin(angle), 0.0, cos(angle))
		var height := 0.48 + float(blade % 3) * 0.12
		var base := lean * 0.09
		for segment in range(4):
			var t0 := float(segment) / 4.0
			var t1 := float(segment + 1) / 4.0
			var center0 := base + Vector3.UP * height * t0 + lean * 0.20 * t0 * t0
			var center1 := base + Vector3.UP * height * t1 + lean * 0.20 * t1 * t1
			var width0 := 0.065 * (1.0 - t0)
			var width1 := 0.065 * (1.0 - t1)
			var points := [center0 - side * width0, center0 + side * width0, center1 - side * width1,
				center0 + side * width0, center1 + side * width1, center1 - side * width1]
			var heights := [t0, t0, t1, t0, t1, t1]
			for index in range(6):
				surface.set_uv(Vector2(0.0, heights[index]))
				surface.set_color(Color.WHITE)
				surface.add_vertex(points[index])
	surface.generate_normals()
	return surface.commit()
