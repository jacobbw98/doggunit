extends Node3D

## Mildred keeps her original cream calico mesh and follows the held dog.
## This surface frame stays fixed; only the cat's body and head turn.
const CAT_HEIGHT := 1.20
const STACK_HEIGHT := 2.44
const HEAD_COMPONENT_HEIGHT := 0.74

var run: Node
var room: Node3D
var room_id := -1
var body: Node3D
var head: Node3D
var eyes: Marker3D
var box_stack: Node3D
var tracked_gun: Node3D
var is_tracking := false
var _eye_offset := Vector3.ZERO

func configure(owner_run: Node, owner_room: Node3D) -> void:
	run = owner_run
	room = owner_room
	room_id = int(owner_room.get("room_id"))
	name = "MildredsCounter"

func _ready() -> void:
	# Switch input and weapon recoil process first, then update the cat's gaze.
	process_priority = 10
	_build_boxes()
	_build_cat()
	var fill := OmniLight3D.new()
	fill.name = "MildredFillLight"
	fill.position = Vector3(0.15, STACK_HEIGHT + 1.0, -1.60)
	fill.light_color = Color(1.0, 0.97, 0.91)
	fill.light_energy = 0.22
	fill.omni_range = 3.0
	fill.omni_attenuation = 1.5
	fill.shadow_enabled = false
	add_child(fill)
	var label := RoomEconomy.make_label("MILDRED'S SHOP\nEverything 15 bones", Color(1.0, 0.87, 0.55))
	label.position.y = STACK_HEIGHT + CAT_HEIGHT + 0.50
	add_child(label)

func _process(_delta: float) -> void:
	visible = RoomEconomy.room_visible(run, room)
	is_tracking = false
	tracked_gun = null
	if not RoomEconomy.room_active(run, room) or not is_instance_valid(body) or not is_instance_valid(head):
		_rest_pose()
		return
	var player: Node3D = run.get("player")
	var manager: Node = player.get("weapon_manager")
	if not is_instance_valid(manager):
		manager = player.get_node_or_null("Camera3D/WeaponManager")
	if not is_instance_valid(manager) or not manager.has_method("get_current_gun"):
		_rest_pose()
		return
	var gun = manager.get_current_gun()
	if not gun is Node3D or not is_instance_valid(gun) or not gun.is_visible_in_tree():
		_rest_pose()
		return
	tracked_gun = gun
	_look_at_dog(get_gun_target(gun))
	is_tracking = true

## The imported Mappo adapter exposes its actual normalized model bounds.
## Other pups use their head mesh, so swapping guns immediately changes target.
func get_gun_target(gun: Node3D) -> Vector3:
	var mascot = gun.get("mascot_model")
	if mascot is Node3D and is_instance_valid(mascot):
		var bounds = mascot.get("normalized_bounds")
		if bounds is AABB and bounds.size.length_squared() > 0.0:
			return mascot.global_transform * bounds.get_center()
		return mascot.global_position
	var mesh = gun.get("mesh_instance")
	if mesh is MeshInstance3D and is_instance_valid(mesh) and mesh.mesh:
		return mesh.global_transform * mesh.mesh.get_aabb().get_center()
	return gun.global_position

func _look_at_dog(target: Vector3) -> void:
	var local_target := to_local(target) - body.position
	var flat := Vector3(local_target.x, 0, local_target.z)
	if not flat.is_zero_approx():
		body.rotation.y = atan2(-flat.x, -flat.z)
	var at_head := body.to_local(target) - head.position
	var distance := Vector2(-at_head.z, at_head.y).length()
	if distance <= 0.0001:
		return
	# Aim from the eye midpoint rather than the neck pivot. This small offset
	# correction keeps her stare directly on the dog at close range too.
	var pitch := atan2(at_head.y, -at_head.z) - asin(clampf(_eye_offset.y / distance, -1.0, 1.0))
	head.rotation.x = pitch

func _rest_pose() -> void:
	if is_instance_valid(body):
		body.rotation = Vector3.ZERO
	if is_instance_valid(head):
		head.rotation = Vector3.ZERO

func get_eye_position() -> Vector3:
	return eyes.global_position if is_instance_valid(eyes) else global_position

func get_gaze_direction() -> Vector3:
	return -head.global_basis.z.normalized() if is_instance_valid(head) else -global_basis.z.normalized()

func _build_boxes() -> void:
	box_stack = Node3D.new()
	box_stack.name = "ThreeCardboardBoxes"
	add_child(box_stack)
	var sizes := [Vector3(1.72, 0.86, 1.40), Vector3(1.51, 0.80, 1.28), Vector3(1.32, 0.78, 1.14)]
	var offsets := [Vector2(0.0, 0.0), Vector2(-0.06, 0.04), Vector2(0.04, -0.02)]
	var y := 0.0
	for index in range(3):
		var size: Vector3 = sizes[index]
		var offset: Vector2 = offsets[index]
		var carton := StaticBody3D.new()
		carton.name = "CardboardBox%d" % (index + 1)
		carton.position = Vector3(offset.x, y + size.y * 0.5, offset.y)
		box_stack.add_child(carton)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		carton.add_child(collision)
		_add_box(carton, "Cardboard", size, Vector3.ZERO, [Color("bb8551"), Color("cf9c63"), Color("b77b48")][index])
		_add_box(carton, "TopSealingTape", Vector3(0.15, 0.012, size.z + 0.008), Vector3(0, size.y * 0.5 + 0.004, 0), Color("ead2a0"))
		for side in [-1.0, 1.0]:
			_add_box(carton, "FoldSeam", Vector3(size.x + 0.005, 0.020, 0.014), Vector3(0, size.y * 0.23, side * (size.z * 0.5 + 0.002)), Color("8f5d37"))
			_add_box(carton, "TapeEnd", Vector3(0.15, size.y * 0.24, 0.012), Vector3(0, size.y * 0.38, side * (size.z * 0.5 + 0.007)), Color("ead2a0"))
		_add_box(carton, "DeliveryLabel", Vector3(0.36, 0.24, 0.012), Vector3(-size.x * 0.22, -size.y * 0.07, -size.z * 0.5 - 0.008), Color("f3e6cb"))
		for line in range(3):
			_add_box(carton, "PrintedAddress", Vector3(0.23 - line * 0.035, 0.012, 0.008), Vector3(-size.x * 0.22 - 0.025, size.y * -0.01 - line * 0.05, -size.z * 0.5 - 0.018), Color("91654b"))
		y += size.y

func _add_box(parent: Node3D, part_name: String, size: Vector3, position: Vector3, color: Color) -> void:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.position = position
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	part.material_override = material
	parent.add_child(part)

func _build_cat() -> void:
	body = Node3D.new()
	body.name = "Mildred"
	body.position.y = STACK_HEIGHT
	add_child(body)
	var imported := RoomEconomy.make_model("mildred", CAT_HEIGHT, true)
	var surfaces := _model_surfaces(imported)
	if surfaces.is_empty():
		body.add_child(imported)
		return
	var eye_center := Vector3.ZERO
	var eye_vertices := 0
	for surface in surfaces:
		var material: Material = surface.material
		if material != null and material.resource_name.to_lower().contains("green eyes"):
			for vertex in surface.vertices:
				eye_center += vertex
				eye_vertices += 1
	if eye_vertices > 0:
		eye_center /= float(eye_vertices)
	else:
		eye_center = Vector3(0, CAT_HEIGHT * 0.745, -0.20)
	# The asymmetrical tail changes the asset's bounds centre. Turn around the
	# cat's anatomical centre, retaining every original vertex in its rest pose.
	var body_origin := Vector3(eye_center.x, 0, eye_center.z + 0.19)
	body.position += body_origin
	head = Node3D.new()
	head.name = "MildredHeadPivot"
	head.position = Vector3(0, 0.70, 0)
	body.add_child(head)
	_eye_offset = eye_center - body_origin - head.position
	eyes = Marker3D.new()
	eyes.name = "MildredEyeMidpoint"
	eyes.position = _eye_offset
	head.add_child(eyes)
	_split_components(surfaces, body_origin)
	imported.free()

## Preserve the joined GLB's disconnected anatomical pieces, including all
## original flat normals and material surfaces. No asset file is rewritten.
func _model_surfaces(model: Node3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var pending: Array = [[model, model.transform]]
	while not pending.is_empty():
		var entry: Array = pending.pop_back()
		var current: Node = entry[0]
		var transform: Transform3D = entry[1]
		if current is MeshInstance3D and current.mesh:
			for index in range(current.mesh.get_surface_count()):
				var arrays: Array = current.mesh.surface_get_arrays(index)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var points := PackedVector3Array()
				var transformed_normals := PackedVector3Array()
				for vertex in vertices:
					points.append(transform * vertex)
				for normal in normals:
					transformed_normals.append((transform.basis.inverse().transposed() * normal).normalized())
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				if indices.is_empty():
					for vertex in range(vertices.size()):
						indices.append(vertex)
				result.append({"vertices": points, "normals": transformed_normals, "indices": indices, "uv": arrays[Mesh.ARRAY_TEX_UV], "colors": arrays[Mesh.ARRAY_COLOR], "material": current.get_active_material(index)})
		for child in current.get_children():
			pending.append([child, transform * child.transform if child is Node3D else transform])
	return result

func _split_components(surfaces: Array[Dictionary], body_origin: Vector3) -> void:
	var welded := {}
	var parents: Array[int] = []
	for surface in surfaces:
		var ids: Array[int] = []
		for vertex in surface.vertices:
			var key: Vector3 = vertex.snapped(Vector3.ONE * 0.00001)
			if not welded.has(key):
				welded[key] = parents.size()
				parents.append(parents.size())
			ids.append(int(welded[key]))
		surface.ids = ids
		var indices: PackedInt32Array = surface.indices
		for index in range(0, indices.size(), 3):
			var first := _component_root(parents, ids[indices[index]])
			for corner in [1, 2]:
				parents[_component_root(parents, ids[indices[index + corner]])] = first
	var bounds := {}
	for surface in surfaces:
		for index in range(surface.vertices.size()):
			var component := _component_root(parents, surface.ids[index])
			var vertex: Vector3 = surface.vertices[index]
			bounds[component] = bounds[component].expand(vertex) if bounds.has(component) else AABB(vertex, Vector3.ZERO)
	var body_mesh := ArrayMesh.new()
	var head_mesh := ArrayMesh.new()
	for surface in surfaces:
		var body_tool := SurfaceTool.new()
		var head_tool := SurfaceTool.new()
		body_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		head_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		body_tool.set_material(surface.material)
		head_tool.set_material(surface.material)
		var counts := [0, 0]
		var indices: PackedInt32Array = surface.indices
		for index in range(0, indices.size(), 3):
			var component := _component_root(parents, surface.ids[indices[index]])
			var component_bounds: AABB = bounds[component]
			var is_head := component_bounds.get_center().y >= HEAD_COMPONENT_HEIGHT
			var tool: SurfaceTool = head_tool if is_head else body_tool
			var offset := body_origin + head.position if is_head else body_origin
			for corner in range(3):
				var vertex_index: int = indices[index + corner]
				if surface.normals.size() > vertex_index:
					tool.set_normal(surface.normals[vertex_index])
				if surface.uv != null and surface.uv.size() > vertex_index:
					tool.set_uv(surface.uv[vertex_index])
				if surface.colors != null and surface.colors.size() > vertex_index:
					tool.set_color(surface.colors[vertex_index])
				tool.add_vertex(surface.vertices[vertex_index] - offset)
			counts[1 if is_head else 0] += 3
		if counts[0] > 0:
			body_tool.commit(body_mesh)
		if counts[1] > 0:
			head_tool.commit(head_mesh)
	var torso := MeshInstance3D.new()
	torso.name = "MildredOriginalBody"
	torso.mesh = body_mesh
	body.add_child(torso)
	var face := MeshInstance3D.new()
	face.name = "MildredOriginalHead"
	face.mesh = head_mesh
	head.add_child(face)

func _component_root(parents: Array[int], index: int) -> int:
	var current := index
	while parents[current] != current:
		parents[current] = parents[parents[current]]
		current = parents[current]
	return current
